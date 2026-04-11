#!/bin/bash
set -e

# =============================================
# AWS EC2 Sc
# =============================================

# ---- 系统更新 & 基础依赖 ----
apt-get update
apt install -y unzip curl jq

# ---- Nginx 配置 ----
mkdir -p /opt/jjo /root/.config

# 从 txt 文件动态获取 zip 文件名
ZIP_NAME=$(curl -fsSL "https://dl.nyafw.com/download/rel_nodeclient_linux_amd64v3.txt")
curl -fsSL -o /tmp/nc.zip "https://dl.nyafw.com/download/${ZIP_NAME}"

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
RECORDS_A=("d1" "d2" "v3007")
RECORDS_AAAA=("d1" "d2" "v3007")
STATE_FILE="/opt/dns-sync/last_ip.txt"
STATE_FILE_V6="/opt/dns-sync/last_ip_v6.txt"
LOG_FILE="/opt/dns-sync/dns_sync.log"
CF_API="https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"

mkdir -p "$(dirname "$STATE_FILE")"
touch "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

cf_get() {
  local url="$1"
  curl -s --fail -X GET "$url" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --max-time 15
}

cf_post() {
  local url="$1"
  local data="$2"
  curl -s --fail -X POST "$url" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$data" \
    --max-time 15
}

cf_put() {
  local url="$1"
  local data="$2"
  curl -s --fail -X PUT "$url" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$data" \
    --max-time 15
}

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

get_public_ipv6() {
  local token=""
  local v6=""
  local imds_base="http://169.254.169.254/latest/meta-data"

  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
    --max-time 3 --connect-timeout 2 2>/dev/null || true)

  if [ -n "$token" ]; then
    v6=$(curl -s -f -L "${imds_base}/ipv6" \
      -H "X-aws-ec2-metadata-token: $token" \
      --max-time 3 --connect-timeout 2 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)

    if [ -z "$v6" ] || ! echo "$v6" | grep -q ":"; then
      local macs=""
      local mac=""
      macs=$(curl -s -f -L "${imds_base}/network/interfaces/macs/" \
        -H "X-aws-ec2-metadata-token: $token" \
        --max-time 3 --connect-timeout 2 2>/dev/null || true)

      for mac in $macs; do
        v6=$(curl -s -f -L "${imds_base}/network/interfaces/macs/${mac}ipv6s" \
          -H "X-aws-ec2-metadata-token: $token" \
          --max-time 3 --connect-timeout 2 2>/dev/null | awk 'NF {print $1; exit}' | tr -d '[:space:]' || true)
        if [ -n "$v6" ] && echo "$v6" | grep -q ":"; then
          break
        fi
      done
    fi
  fi

  if [ -z "$v6" ] || ! echo "$v6" | grep -q ":"; then
    v6=$(curl -s -L --max-time 5 "https://api6.ipify.org" 2>/dev/null | tr -d '[:space:]' || true)
  fi

  echo "$v6"
}

get_record_id() {
  local fqdn="$1"
  local type="$2"
  local response=""
  local record_id=""
  local total_pages=1
  local page=1

  response=$(cf_get "$CF_API?name=${fqdn}&per_page=100")
  record_id=$(echo "$response" | jq -r --arg type "$type" '.result[]? | select(.type == $type) | .id' | head -n 1)

  if [ -n "$record_id" ]; then
    echo "$record_id"
    return 0
  fi

  total_pages=$(echo "$response" | jq -r '.result_info.total_pages // 1')
  if ! [[ "$total_pages" =~ ^[0-9]+$ ]] || [ "$total_pages" -lt 1 ]; then
    total_pages=1
  fi

  while [ "$page" -le "$total_pages" ]; do
    response=$(cf_get "$CF_API?per_page=100&page=${page}")
    record_id=$(echo "$response" | jq -r --arg name "$fqdn" --arg type "$type" '.result[]? | select(.name == $name and .type == $type) | .id' | head -n 1)
    if [ -n "$record_id" ]; then
      echo "$record_id"
      return 0
    fi
    page=$((page + 1))
  done

  return 1
}

create_record() {
  local fqdn="$1"
  local ip="$2"
  local type="$3"
  local payload=""
  local result=""
  local success=""
  local errors=""

  payload=$(jq -nc \
    --arg type "$type" \
    --arg name "$fqdn" \
    --arg content "$ip" \
    '{type:$type,name:$name,content:$content,ttl:60}')

  result=$(cf_post "$CF_API" "$payload")
  success=$(echo "$result" | jq -r '.success')

  if [ "$success" != "true" ]; then
    errors=$(echo "$result" | jq -c '.errors // []')
    log "${fqdn} (${type}) -> $ip 创建失败: $errors"
    return 1
  fi

  log "${fqdn} (${type}) -> $ip : created"
}

update_record() {
  local record="$1"
  local ip="$2"
  local type="$3"
  local fqdn="${record}.${DOMAIN}"
  local record_id=""
  local payload=""
  local result=""
  local success=""
  local errors=""

  if ! record_id=$(get_record_id "$fqdn" "$type"); then
    log "${fqdn} (${type}) 不存在，改为创建"
    create_record "$fqdn" "$ip" "$type"
    return $?
  fi

  payload=$(jq -nc \
    --arg type "$type" \
    --arg name "$fqdn" \
    --arg content "$ip" \
    '{type:$type,name:$name,content:$content,ttl:60}')

  result=$(cf_put "$CF_API/$record_id" "$payload")
  success=$(echo "$result" | jq -r '.success')

  if [ "$success" != "true" ]; then
    errors=$(echo "$result" | jq -c '.errors // []')
    log "${fqdn} (${type}) -> $ip 更新失败: $errors"
    return 1
  fi

  log "${fqdn} (${type}) -> $ip : updated"
}

LAST_IP=""
LAST_IP_V6=""
if [ -f "$STATE_FILE" ]; then
  LAST_IP=$(tr -d '[:space:]' < "$STATE_FILE")
fi
if [ -f "$STATE_FILE_V6" ]; then
  LAST_IP_V6=$(tr -d '[:space:]' < "$STATE_FILE_V6")
fi

while true; do
  CURRENT_IP=$(get_public_ip)
  CURRENT_IP_V6=$(get_public_ipv6)

  if [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "0.0.0.0" ] && [ "$CURRENT_IP" != "$LAST_IP" ]; then
    log "IPv4 变化: ${LAST_IP:-无} -> $CURRENT_IP"
    failed=0
    for record in "${RECORDS_A[@]}"; do
      update_record "$record" "$CURRENT_IP" "A" || failed=1
      sleep 1
    done
    if [ "$failed" -eq 0 ]; then
      LAST_IP="$CURRENT_IP"
      echo "$CURRENT_IP" > "$STATE_FILE"
    else
      log "IPv4 DNS 更新有失败，保留旧 IP: $LAST_IP"
    fi
  fi

  if [ -n "$CURRENT_IP_V6" ] && echo "$CURRENT_IP_V6" | grep -q ":" && [ "$CURRENT_IP_V6" != "$LAST_IP_V6" ]; then
    log "IPv6 变化: ${LAST_IP_V6:-无} -> $CURRENT_IP_V6"
    failed=0
    for record in "${RECORDS_AAAA[@]}"; do
      update_record "$record" "$CURRENT_IP_V6" "AAAA" || failed=1
      sleep 1
    done
    if [ "$failed" -eq 0 ]; then
      LAST_IP_V6="$CURRENT_IP_V6"
      echo "$CURRENT_IP_V6" > "$STATE_FILE_V6"
    else
      log "IPv6 DNS 更新有失败，保留旧 IP: $LAST_IP_V6"
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
