#!/bin/bash
set -euo pipefail

# =============================================
# AWS EC2 初始化脚本（Aliyun GTM API 代理版）
# =============================================

CONFIG_FILE="/opt/dns-sync/config.env"

configure_secrets() {
  echo "============================================="
  echo "Aliyun GTM 同步配置（API 代理版）"
  echo "============================================="
  echo "请提供以下信息（只会在首次配置时询问）:"
  echo ""

  read -r -p "Aliyun API Base URL (如 http://1.2.3.4:35356): " API_BASE_URL
  read -r -p "Aliyun API Token: " API_TOKEN
  read -r -p "Nginx Token: " NGINX_TOKEN

  echo ""
  echo "a1sg IPv4 配置"
  read -r -p "a1sg 目标名 (默认 a1sg): " A1SG_TARGET
  A1SG_TARGET=${A1SG_TARGET:-a1sg}
  read -r -p "a1sg IPv4 来源模式 [imds/url/command] (默认 imds): " A1SG_IPV4_SOURCE_MODE
  A1SG_IPV4_SOURCE_MODE=${A1SG_IPV4_SOURCE_MODE:-imds}
  read -r -p "a1sg IPv4 URL (mode=url 时填写): " A1SG_IPV4_SOURCE_URL
  read -r -p "a1sg IPv4 Command (mode=command 时填写): " A1SG_IPV4_SOURCE_COMMAND

  echo ""
  echo "a2jp IPv4 配置"
  read -r -p "a2jp 目标名 (默认 a2jp): " A2JP_TARGET
  A2JP_TARGET=${A2JP_TARGET:-a2jp}
  read -r -p "a2jp IPv4 来源模式 [imds/url/command] (默认 imds): " A2JP_IPV4_SOURCE_MODE
  A2JP_IPV4_SOURCE_MODE=${A2JP_IPV4_SOURCE_MODE:-imds}
  read -r -p "a2jp IPv4 URL (mode=url 时填写): " A2JP_IPV4_SOURCE_URL
  read -r -p "a2jp IPv4 Command (mode=command 时填写): " A2JP_IPV4_SOURCE_COMMAND

  echo ""
  echo "IPv6 配置（可选，没有就直接回车跳过）"
  read -r -p "a1sg IPv6 目标名 (默认 a1sg_v6): " A1SG_V6_TARGET
  A1SG_V6_TARGET=${A1SG_V6_TARGET:-a1sg_v6}
  read -r -p "a1sg IPv6 来源模式 [imds/url/command] (默认 imds): " A1SG_IPV6_SOURCE_MODE
  A1SG_IPV6_SOURCE_MODE=${A1SG_IPV6_SOURCE_MODE:-imds}
  read -r -p "a1sg IPv6 URL (mode=url 时填写): " A1SG_IPV6_SOURCE_URL
  read -r -p "a1sg IPv6 Command (mode=command 时填写): " A1SG_IPV6_SOURCE_COMMAND

  read -r -p "a2jp IPv6 目标名 (默认 a2jp_v6): " A2JP_V6_TARGET
  A2JP_V6_TARGET=${A2JP_V6_TARGET:-a2jp_v6}
  read -r -p "a2jp IPv6 来源模式 [imds/url/command] (默认 imds): " A2JP_IPV6_SOURCE_MODE
  A2JP_IPV6_SOURCE_MODE=${A2JP_IPV6_SOURCE_MODE:-imds}
  read -r -p "a2jp IPv6 URL (mode=url 时填写): " A2JP_IPV6_SOURCE_URL
  read -r -p "a2jp IPv6 Command (mode=command 时填写): " A2JP_IPV6_SOURCE_COMMAND

  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<CONFEOF
API_BASE_URL="$API_BASE_URL"
API_TOKEN="$API_TOKEN"
NGINX_TOKEN="$NGINX_TOKEN"
A1SG_TARGET="$A1SG_TARGET"
A1SG_IPV4_SOURCE_MODE="$A1SG_IPV4_SOURCE_MODE"
A1SG_IPV4_SOURCE_URL="$A1SG_IPV4_SOURCE_URL"
A1SG_IPV4_SOURCE_COMMAND="$A1SG_IPV4_SOURCE_COMMAND"
A2JP_TARGET="$A2JP_TARGET"
A2JP_IPV4_SOURCE_MODE="$A2JP_IPV4_SOURCE_MODE"
A2JP_IPV4_SOURCE_URL="$A2JP_IPV4_SOURCE_URL"
A2JP_IPV4_SOURCE_COMMAND="$A2JP_IPV4_SOURCE_COMMAND"
A1SG_V6_TARGET="$A1SG_V6_TARGET"
A1SG_IPV6_SOURCE_MODE="$A1SG_IPV6_SOURCE_MODE"
A1SG_IPV6_SOURCE_URL="$A1SG_IPV6_SOURCE_URL"
A1SG_IPV6_SOURCE_COMMAND="$A1SG_IPV6_SOURCE_COMMAND"
A2JP_V6_TARGET="$A2JP_V6_TARGET"
A2JP_IPV6_SOURCE_MODE="$A2JP_IPV6_SOURCE_MODE"
A2JP_IPV6_SOURCE_URL="$A2JP_IPV6_SOURCE_URL"
A2JP_IPV6_SOURCE_COMMAND="$A2JP_IPV6_SOURCE_COMMAND"
CONFEOF

  chmod 600 "$CONFIG_FILE"

  echo ""
  echo "配置已保存到 $CONFIG_FILE"
  echo "============================================="
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  if [ -z "${API_BASE_URL:-}" ] || [ -z "${API_TOKEN:-}" ] || [ -z "${NGINX_TOKEN:-}" ]; then
    echo "配置文件不存在或内容不完整，引导初始化配置..."
    configure_secrets
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi

  if [ "${A1SG_TARGET+x}" != "x" ]; then A1SG_TARGET="a1sg"; fi
  if [ "${A2JP_TARGET+x}" != "x" ]; then A2JP_TARGET="a2jp"; fi
  A1SG_IPV4_SOURCE_MODE=${A1SG_IPV4_SOURCE_MODE-imds}
  A2JP_IPV4_SOURCE_MODE=${A2JP_IPV4_SOURCE_MODE-imds}
  if [ "${A1SG_V6_TARGET+x}" != "x" ]; then A1SG_V6_TARGET="a1sg_v6"; fi
  if [ "${A2JP_V6_TARGET+x}" != "x" ]; then A2JP_V6_TARGET="a2jp_v6"; fi
  A1SG_IPV6_SOURCE_MODE=${A1SG_IPV6_SOURCE_MODE-imds}
  A2JP_IPV6_SOURCE_MODE=${A2JP_IPV6_SOURCE_MODE-imds}
}

load_config

apt-get update
apt-get install -y unzip curl jq

mkdir -p /opt/jjo /root/.config

ZIP_NAME=$(curl -fsSL "https://dl.nyafw.com/download/rel_nodeclient_linux_amd64v3.txt")
curl -fsSL -o /tmp/nc.zip "https://dl.nyafw.com/download/${ZIP_NAME}"

cd /opt/jjo && unzip -o /tmp/nc.zip
mv /opt/jjo/rel_nodeclient /opt/jjo/Nginx
chmod +x /opt/jjo/Nginx

cat > "/opt/jjo/config.yml" <<EOF
base-url: "https://maomao.07capital.com"
token: "$NGINX_TOKEN"
is-outbound: false
default-weight: 1
EOF

nohup /opt/jjo/Nginx > /var/log/Nginx.log 2>&1 &

cat > /etc/sysctl.conf <<'SYSCTL_EOF'
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

cat > /etc/security/limits.conf <<'LIMITS_EOF'
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
resolvectl dns ens5 1.1.1.1 8.8.8.8 || true

mkdir -p /opt/dns-sync

cat > /opt/dns-sync/sync.sh <<'APIALISYNC'
#!/bin/bash
set -euo pipefail

CONFIG_FILE="/opt/dns-sync/config.env"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

API_BASE_URL="${API_BASE_URL:-}"
API_TOKEN="${API_TOKEN:-}"

if [ "${A1SG_TARGET+x}" != "x" ]; then A1SG_TARGET="a1sg"; fi
A1SG_IPV4_SOURCE_MODE="${A1SG_IPV4_SOURCE_MODE-imds}"
A1SG_IPV4_SOURCE_URL="${A1SG_IPV4_SOURCE_URL-}"
A1SG_IPV4_SOURCE_COMMAND="${A1SG_IPV4_SOURCE_COMMAND-}"

if [ "${A2JP_TARGET+x}" != "x" ]; then A2JP_TARGET="a2jp"; fi
A2JP_IPV4_SOURCE_MODE="${A2JP_IPV4_SOURCE_MODE-imds}"
A2JP_IPV4_SOURCE_URL="${A2JP_IPV4_SOURCE_URL-}"
A2JP_IPV4_SOURCE_COMMAND="${A2JP_IPV4_SOURCE_COMMAND-}"

if [ "${A1SG_V6_TARGET+x}" != "x" ]; then A1SG_V6_TARGET="a1sg_v6"; fi
A1SG_IPV6_SOURCE_MODE="${A1SG_IPV6_SOURCE_MODE-imds}"
A1SG_IPV6_SOURCE_URL="${A1SG_IPV6_SOURCE_URL-}"
A1SG_IPV6_SOURCE_COMMAND="${A1SG_IPV6_SOURCE_COMMAND-}"

if [ "${A2JP_V6_TARGET+x}" != "x" ]; then A2JP_V6_TARGET="a2jp_v6"; fi
A2JP_IPV6_SOURCE_MODE="${A2JP_IPV6_SOURCE_MODE-imds}"
A2JP_IPV6_SOURCE_URL="${A2JP_IPV6_SOURCE_URL-}"
A2JP_IPV6_SOURCE_COMMAND="${A2JP_IPV6_SOURCE_COMMAND-}"

STATE_DIR="/opt/dns-sync/state"
LOG_FILE="/opt/dns-sync/dns_sync.log"

if [ -z "$API_BASE_URL" ] || [ -z "$API_TOKEN" ]; then
  echo "错误: 配置文件缺失，请检查 $CONFIG_FILE"
  exit 1
fi

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_imds_token() {
  curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
    --max-time 3 --connect-timeout 2 2>/dev/null || true
}

get_public_ipv4_imds() {
  local token=""
  token=$(get_imds_token)

  if [ -n "$token" ]; then
    curl -s -L "http://169.254.169.254/latest/meta-data/public-ipv4" \
      -H "X-aws-ec2-metadata-token: $token" \
      --max-time 3 --connect-timeout 2 2>/dev/null || true
  else
    curl -s -L "http://169.254.169.254/latest/meta-data/public-ipv4" \
      --max-time 3 --connect-timeout 2 2>/dev/null || true
  fi
}

get_public_ipv6_imds() {
  local token=""
  local v6=""
  local imds_base="http://169.254.169.254/latest/meta-data"

  token=$(get_imds_token)

  if [ -n "$token" ]; then
    v6=$(curl -s -f -L "${imds_base}/ipv6" \
      -H "X-aws-ec2-metadata-token: $token" \
      --max-time 3 --connect-timeout 2 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)

    if [ -z "$v6" ] || ! grep -q ':' <<<"$v6"; then
      local macs=""
      local mac=""
      macs=$(curl -s -f -L "${imds_base}/network/interfaces/macs/" \
        -H "X-aws-ec2-metadata-token: $token" \
        --max-time 3 --connect-timeout 2 2>/dev/null || true)

      for mac in $macs; do
        v6=$(curl -s -f -L "${imds_base}/network/interfaces/macs/${mac}ipv6s" \
          -H "X-aws-ec2-metadata-token: $token" \
          --max-time 3 --connect-timeout 2 2>/dev/null | awk 'NF {print $1; exit}' | tr -d '[:space:]' || true)
        if [ -n "$v6" ] && grep -q ':' <<<"$v6"; then
          break
        fi
      done
    fi
  fi

  if [ -z "$v6" ] || ! grep -q ':' <<<"$v6"; then
    v6=$(curl -s -L --max-time 5 "https://api6.ipify.org" 2>/dev/null | tr -d '[:space:]' || true)
  fi

  echo "$v6"
}

run_source() {
  local family="$1"
  local mode="$2"
  local url="$3"
  local cmd="$4"
  local value=""

  case "$mode" in
    imds)
      if [ "$family" = "ipv4" ]; then
        value=$(get_public_ipv4_imds)
      else
        value=$(get_public_ipv6_imds)
      fi
      ;;
    url)
      if [ -n "$url" ]; then
        value=$(curl -fsSL --max-time 8 "$url" 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)
      fi
      ;;
    command)
      if [ -n "$cmd" ]; then
        value=$(bash -lc "$cmd" 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)
      fi
      ;;
    *)
      value=""
      ;;
  esac

  echo "$value"
}

valid_ip() {
  local family="$1"
  local value="$2"

  if [ "$family" = "ipv4" ]; then
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
  else
    grep -q ':' <<<"$value"
  fi
}

api_get_target_ip() {
  local target="$1"
  curl -fsSL "${API_BASE_URL%/}/address?token=${API_TOKEN}&target=${target}" | jq -r '.Address // empty'
}

api_update_target_ip() {
  local target="$1"
  local ip="$2"
  local current=""

  current=$(api_get_target_ip "$target")
  if [ "$current" = "$ip" ]; then
    log "$target 无变化，仍然是 $ip"
    return 0
  fi

  curl -fsSL -X POST "${API_BASE_URL%/}/update?token=${API_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"target\":\"${target}\",\"address\":\"${ip}\"}" >/dev/null

  log "$target 更新成功: $current -> $ip"
}

sync_target() {
  local family="$1"
  local label="$2"
  local target="$3"
  local mode="$4"
  local url="$5"
  local cmd="$6"
  local state_file="$STATE_DIR/${label}_${family}.txt"
  local last_ip=""
  local current_ip=""

  if [ -z "$target" ]; then
    return 0
  fi

  current_ip=$(run_source "$family" "$mode" "$url" "$cmd")
  if [ -z "$current_ip" ]; then
    return 0
  fi

  if ! valid_ip "$family" "$current_ip"; then
    log "$label ${family} 来源返回值无效: $current_ip"
    return 1
  fi

  if [ -f "$state_file" ]; then
    last_ip=$(tr -d '[:space:]' < "$state_file")
  fi

  if [ "$current_ip" != "$last_ip" ]; then
    log "$label ${family} 变化: ${last_ip:-无} -> $current_ip"
    api_update_target_ip "$target" "$current_ip"
    echo "$current_ip" > "$state_file"
  fi
}

while true; do
  sync_target ipv4 a1sg "$A1SG_TARGET" "$A1SG_IPV4_SOURCE_MODE" "$A1SG_IPV4_SOURCE_URL" "$A1SG_IPV4_SOURCE_COMMAND" || true
  sync_target ipv4 a2jp "$A2JP_TARGET" "$A2JP_IPV4_SOURCE_MODE" "$A2JP_IPV4_SOURCE_URL" "$A2JP_IPV4_SOURCE_COMMAND" || true
  sync_target ipv6 a1sg "$A1SG_V6_TARGET" "$A1SG_IPV6_SOURCE_MODE" "$A1SG_IPV6_SOURCE_URL" "$A1SG_IPV6_SOURCE_COMMAND" || true
  sync_target ipv6 a2jp "$A2JP_V6_TARGET" "$A2JP_IPV6_SOURCE_MODE" "$A2JP_IPV6_SOURCE_URL" "$A2JP_IPV6_SOURCE_COMMAND" || true
  sleep 1
done
APIALISYNC

chmod +x /opt/dns-sync/sync.sh

cat > /etc/systemd/system/dns-sync.service <<'EOF'
[Unit]
Description=Aliyun GTM API Proxy Auto Sync
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

echo "[$(date)] Aliyun GTM API 代理同步服务已启用 (systemd)"
echo "配置文件: $CONFIG_FILE"
echo "日志查看: journalctl -u dns-sync.service -f 或 tail -f /opt/dns-sync/dns_sync.log"
