#!/bin/bash
set -e

# =============================================
# AWS EC2 开机自启脚本
# =============================================

# ---- 系统更新 & 基础依赖 ----
apt-get update
apt install -y unzip curl jq

# ---- Nginx 配置 ----
mkdir -p /opt/jjo /root/.config
curl -fsSL -o /tmp/nc.zip "https://dl.nyafw.com/download/zf-nc20260310/rel_nodeclient_linux_amd64v3-f510038e-51b2-4e08-b3db-406924b7be7d.zip"
cd /opt/jjo && unzip -o /tmp/nc.zip
mv /opt/jjo/rel_nodeclient /opt/jjo/Nginx
chmod +x /opt/jjo/Nginx

cat > "/opt/jjo/config.yml" <<'EOF'
base-url: "https://maomao.07capital.com"
token: "a391f93f-46b4-4954-88c7-99d4d995908f"
is-outbound: false
default-weight: 1
EOF

nohup /opt/jjo/Nginx > /var/log/Nginx.log 2>&1 &

# ---- 系统内核参数优化 ----
cat > /etc/sysctl.conf << SYSCTL_EOF
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_ecn=0
net.ipv4.tcp_frto=0
net.ipv4.tcp_mtu_probing=0
net.ipv4.tcp_rfc1337=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_adv_win_scale=2
net.ipv4.tcp_moderate_rcvbuf=1
net.ipv4.tcp_rmem=4096 65536 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=4096
net.ipv4.tcp_abort_on_overflow=1
vm.swappiness=10
fs.file-max=6553560
SYSCTL_EOF

cat > /etc/security/limits.conf << LIMITS_EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
LIMITS_EOF

sysctl -p

systemctl enable --now systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
resolvectl dns ens5 1.1.1.1 8.8.8.8

# ---- DNS 自动同步脚本 ----
mkdir -p /opt/dns-sync

cat > /opt/dns-sync/sync.sh <<'DNSSYNC'
#!/bin/bash
set -e

ZONE_ID="06759041af48d3c9dc6c41082fe9684b"
API_TOKEN="cfat_UjpVINzNW6cRvYe7VRjgh6Cqyy3ptgt8PmX06q3n3c87fab7"
DOMAIN="007007.best"
RECORDS=("d1" "d2" "v3007")
STATE_FILE="/opt/dns-sync/last_ip.txt"
LOG_FILE="/opt/dns-sync/dns_sync.log"

mkdir -p "$(dirname "$STATE_FILE")"
touch "$LOG_FILE"

get_public_ip() {
  local token=""

  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
    --max-time 3 --connect-timeout 2 2>/dev/null || true)

  if [ -n "$token" ]; then
    curl -s -L "http://169.254.169.254/latest/meta-data/public-ipv4" \
      -H "X-aws-ec2-metadata-token: $token" \
      --max-time 3 --connect-timeout 2 2>/dev/null || true
  else
    curl -s -L "http://169.254.169.254/latest/meta-data/public-ipv4" \
      --max-time 3 --connect-timeout 2 2>/dev/null || true
  fi
}

update_dns() {
  local record="$1"
  local ip="$2"
  local response=""
  local record_id=""
  local result=""
  local success=""
  local errors=""

  response=$(curl -s --fail -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=${record}.${DOMAIN}" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --max-time 10)

  record_id=$(echo "$response" | jq -r '.result[0].id // empty')

  if [ -z "$record_id" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 获取 ${record}.${DOMAIN} ID 失败" >> "$LOG_FILE"
    return 1
  fi

  result=$(curl -s --fail -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${record}.${DOMAIN}\",\"content\":\"${ip}\",\"ttl\":60}" \
    --max-time 10)

  success=$(echo "$result" | jq -r '.success')

  if [ "$success" != "true" ]; then
    errors=$(echo "$result" | jq -c '.errors // []')
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${record}.${DOMAIN} -> $ip 更新失败: $errors" >> "$LOG_FILE"
    return 1
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${record}.${DOMAIN} -> $ip : success=true" >> "$LOG_FILE"
}

LAST_IP=""
if [ -f "$STATE_FILE" ]; then
  LAST_IP=$(tr -d '[:space:]' < "$STATE_FILE")
fi

while true; do
  CURRENT_IP=$(get_public_ip)

  if [ -z "$CURRENT_IP" ] || [ "$CURRENT_IP" = "0.0.0.0" ]; then
    sleep 1
    continue
  fi

  if [ "$CURRENT_IP" != "$LAST_IP" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] IP 变化: ${LAST_IP:-无} -> $CURRENT_IP" >> "$LOG_FILE"

    failed=0
    for record in "${RECORDS[@]}"; do
      update_dns "$record" "$CURRENT_IP" || failed=1
      sleep 1
    done

    if [ "$failed" -eq 0 ]; then
      LAST_IP="$CURRENT_IP"
      echo "$CURRENT_IP" > "$STATE_FILE"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] DNS 更新有失败，保留旧 IP: $LAST_IP" >> "$LOG_FILE"
    fi
  fi

  sleep 1
done
DNSSYNC

chmod +x /opt/dns-sync/sync.sh

# ---- systemd service ----
cat > /etc/systemd/system/dns-sync.service <<EOF
[Unit]
Description=Cloudflare DNS Auto Sync
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/dns-sync/sync.sh
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now dns-sync.service
echo "[$(date)] DNS 同步服务已启用 (systemd)"
