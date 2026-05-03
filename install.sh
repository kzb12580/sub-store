#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Sub-Store 一键安装
#  默认 IP:端口 直接访问，域名/SSL 可选后续配置
# ═══════════════════════════════════════════════════════════════
set -e

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
p()  { echo -e "${B}[·]${N} $1"; }
ok() { echo -e "${G}[✓]${N} $1"; }
wr() { echo -e "${Y}[!]${N} $1"; }
die(){ echo -e "${R}[✗]${N} $1"; exit 1; }

trap 'echo ""; wr "安装中断"; exit 1' INT TERM

# ─── 参数 ───────────────────────────────────────────────────────
PORT=80
DOH_PATH="/dns-query"
SSH_PORT=307
DIR="/opt/sub-store"
REPO="kzb12580/sub-store"

while [[ $# -gt 0 ]]; do
  case $1 in
    --port)      PORT="$2";      shift 2 ;;
    --doh-path)  DOH_PATH="$2";  shift 2 ;;
    --ssh-port)  SSH_PORT="$2";  shift 2 ;;
    --dir)       DIR="$2";       shift 2 ;;
    -h|--help)
      echo "用法: bash install.sh [选项]"
      echo ""
      echo "选项:"
      echo "  --port PORT        服务端口（默认 80）"
      echo "  --doh-path PATH    DOH 路径（默认 /dns-query）"
      echo "  --ssh-port PORT    SSH 端口（默认 307）"
      echo "  --dir DIR          安装目录（默认 /opt/sub-store）"
      echo "  -h, --help         帮助"
      echo ""
      echo "安装后可运行以下命令绑定域名+HTTPS:"
      echo "  bash /opt/sub-store/scripts/setup-domain.sh your-domain.com"
      exit 0 ;;
    *) wr "未知参数: $1"; shift ;;
  esac
done

# ─── 获取服务器 IP ───────────────────────────────────────────────
get_ip() {
  local ip
  ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
       curl -4 -s --connect-timeout 5 ip.sb 2>/dev/null || \
       curl -4 -s --connect-timeout 5 api.ipify.org 2>/dev/null || \
       echo "")
  echo "$ip"
}

SERVER_IP=$(get_ip)

echo ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${C}║            Sub-Store 一键部署                        ║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  服务器 IP: ${C}${SERVER_IP:-未检测到}${N}"
echo -e "  服务端口:  ${C}$PORT${N}"
echo -e "  DOH 路径:  ${C}$DOH_PATH${N}"
echo ""
echo -n "确认安装？[Y/n] "
read -r CONFIRM </dev/tty 2>/dev/null || CONFIRM="y"
[[ "$CONFIRM" =~ ^[Nn]$ ]] && exit 0

# ─── 系统检测 ───────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "不支持的架构: $ARCH" ;;
esac
p "系统: $(uname -s) $ARCH"

# ─── 安装依赖 ───────────────────────────────────────────────────
p "安装依赖..."

apt_update_done=false
pkg_install() {
  if command -v apt-get &>/dev/null; then
    if [ "$apt_update_done" = false ]; then apt-get update -qq </dev/null 2>/dev/null; apt_update_done=true; fi
    apt-get install -y -qq "$@" </dev/null 2>/dev/null
  elif command -v dnf &>/dev/null; then dnf install -y -q "$@" </dev/null 2>/dev/null
  elif command -v yum &>/dev/null; then yum install -y -q "$@" </dev/null 2>/dev/null
  fi
}

command -v curl &>/dev/null || pkg_install curl
command -v git  &>/dev/null || pkg_install git
command -v jq   &>/dev/null || pkg_install jq

# Go
if ! command -v go &>/dev/null; then
  p "安装 Go..."
  GO_VER="1.22.4"
  curl -sSL "https://go.dev/dl/go${GO_VER}.linux-${ARCH}.tar.gz" </dev/null | tar -C /usr/local -xz
  export PATH="/usr/local/go/bin:$PATH"
  echo 'export PATH="/usr/local/go/bin:$PATH"' >> /etc/profile
  ok "Go $GO_VER"
else
  ok "Go $(go version | grep -oP 'go\K[0-9.]+')"
fi

# Docker
if ! command -v docker &>/dev/null; then
  p "安装 Docker..."
  curl -fsSL https://get.docker.com </dev/null | sh 2>/dev/null
  systemctl enable docker --quiet 2>/dev/null
  systemctl start docker 2>/dev/null
fi
ok "Docker $(docker --version | grep -oP 'version \K[0-9.]+')"

# ─── 端口冲突检测 ────────────────────────────────────────────────
for CHK_PORT in $PORT; do
  if ss -tlnp 2>/dev/null | grep -q ":$CHK_PORT "; then
    SVC=$(ss -tlnp 2>/dev/null | grep ":$CHK_PORT " | grep -oP 'users:\(\("\K[^"]+' | head -1)
    if [ -n "$SVC" ]; then
      wr "端口 $CHK_PORT 被 $SVC 占用"
      echo -n "  停止 $SVC？[Y/n] "
      read -r STOP_SVC </dev/tty 2>/dev/null || STOP_SVC="y"
      if [[ ! "$STOP_SVC" =~ ^[Nn]$ ]]; then
        systemctl stop "$SVC" 2>/dev/null || true
        ok "已停止 $SVC"
      else
        die "端口 $CHK_PORT 冲突，换端口: bash install.sh --port 8080"
      fi
    fi
  fi
done

# ─── 创建目录 ────────────────────────────────────────────────────
DATA="$DIR/data"
DOH_DIR="$DIR/doh"
SCRIPTS="$DIR/scripts"
mkdir -p "$DATA" "$DOH_DIR" "$SCRIPTS"

# ─── DOH (Docker) ───────────────────────────────────────────────
p "配置 DOH..."

cat > "$DOH_DIR/docker-compose.yml" << 'YMLEOF'
services:
  coredns:
    image: coredns/coredns:1.12.3
    container_name: doh-coredns
    restart: unless-stopped
    command: -conf /Corefile
    volumes:
      - ./Corefile:/Corefile:ro
    ports:
      - "127.0.0.1:8053:8053/udp"
      - "127.0.0.1:8053:8053/tcp"
  doh-server:
    image: satishweb/doh-server:latest
    container_name: doh-server
    restart: unless-stopped
    environment:
      UPSTREAM_DNS_SERVER: udp:127.0.0.1:8053
      DOH_HTTP_PREFIX: /dns-query
      DOH_SERVER_LISTEN: 127.0.0.1:8054
      DOH_SERVER_TIMEOUT: 10
      DOH_SERVER_TRIES: 3
      DOH_SERVER_VERBOSE: "false"
    network_mode: host
YMLEOF

cat > "$DOH_DIR/Corefile" << 'COREEOF'
.:8053 {
    errors
    log
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
    cache 300
}
COREEOF

cd "$DOH_DIR"
docker compose pull -q 2>/dev/null || docker-compose pull -q 2>/dev/null || true
docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null
ok "DOH 已启动"

# ─── Sub-Store ───────────────────────────────────────────────────
p "获取 Sub-Store..."

SRC_DIR="$DIR/src"
BUILD_OK=false

if [ -d "$SRC_DIR/.git" ]; then
  cd "$SRC_DIR" && git pull -q </dev/null 2>/dev/null || true
else
  git clone --depth 1 "https://github.com/$REPO.git" "$SRC_DIR" </dev/null 2>/dev/null
fi

if [ -f "$SRC_DIR/main.go" ]; then
  cd "$SRC_DIR"
  p "编译..."
  CGO_ENABLED=0 go build -ldflags="-s -w" -o "$DIR/sub-store" . 2>&1 && BUILD_OK=true
fi

if [ "$BUILD_OK" = false ]; then
  p "下载预编译版本..."
  URL="https://github.com/$REPO/releases/latest/download/sub-store-linux-$ARCH"
  curl -sSL -o "$DIR/sub-store" "$URL" </dev/null 2>/dev/null || die "获取失败"
fi

chmod +x "$DIR/sub-store"

# 配置
cat > "$DATA/config.json" << CFGEOF
{
  "data_dir": "$DATA",
  "log_level": "info",
  "doh_servers": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"],
  "doh_engine": "cloudflare"
}
CFGEOF

# Systemd
cat > /etc/systemd/system/sub-store.service << SVCEOF
[Unit]
Description=Sub-Store
After=network.target

[Service]
Type=simple
WorkingDirectory=$DIR
ExecStart=$DIR/sub-store -port $PORT -config $DATA/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable sub-store --quiet 2>/dev/null
systemctl restart sub-store
sleep 1

if systemctl is-active --quiet sub-store; then
  ok "Sub-Store 已启动"
else
  die "启动失败: journalctl -u sub-store -n 20"
fi

# ─── 写入环境信息 ────────────────────────────────────────────────
cat > "$DIR/.env" << EOF
SERVER_IP=$SERVER_IP
PORT=$PORT
DOH_PATH=$DOH_PATH
SSH_PORT=$SSH_PORT
INSTALL_DIR=$DIR
INSTALLED_AT=$(date -Iseconds)
EOF

# ─── 保存域名配置脚本 ────────────────────────────────────────────
cat > "$SCRIPTS/setup-domain.sh" << 'DOMAINEOF'
#!/bin/bash
# 绑定域名 + 申请 HTTPS 证书
# 用法: bash setup-domain.sh your-domain.com

set -e
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
p()  { echo -e "${B}[·]${N} $1"; }
ok() { echo -e "${G}[✓]${N} $1"; }
wr() { echo -e "${Y}[!]${N} $1"; }
die(){ echo -e "${R}[✗]${N} $1"; exit 1; }

DOMAIN="$1"
[ -z "$DOMAIN" ] && die "用法: bash setup-domain.sh your-domain.com"

DIR="/opt/sub-store"
ENV="$DIR/.env"
[ -f "$ENV" ] && source "$ENV"
PORT="${PORT:-80}"
DOH_PATH="${DOH_PATH:-/dns-query}"

echo ""
p "绑定域名: $DOMAIN"
p "后端端口: $PORT"
echo ""

# 安装 Caddy（如果没有）
if ! command -v caddy &>/dev/null; then
  p "安装 Caddy..."
  if command -v apt-get &>/dev/null; then
    apt-get update -qq </dev/null 2>/dev/null
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https </dev/null 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' </dev/null | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' </dev/null | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -qq </dev/null 2>/dev/null
    apt-get install -y -qq caddy </dev/null 2>/dev/null
  elif command -v dnf &>/dev/null; then
    dnf install -y -q 'dnf-command(copr)' 2>/dev/null
    dnf copr enable @caddy/caddy -y 2>/dev/null
    dnf install -y -q caddy 2>/dev/null
  else
    ARCH=$(uname -m); case "$ARCH" in x86_64|amd64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; esac
    curl -sSL "https://caddyserver.com/api/download?os=linux&arch=${ARCH}" </dev/null -o /usr/bin/caddy
    chmod +x /usr/bin/caddy
  fi
  ok "Caddy 已安装"
fi

# 停止 Sub-Store（释放端口）
p "重新配置服务..."
systemctl stop sub-store 2>/dev/null || true

# 把 Sub-Store 改为内部端口
INTERNAL_PORT=8888
sed -i "s/ExecStart=.*sub-store/ExecStart=$DIR\/sub-store/" /etc/systemd/system/sub-store.service
sed -i "s/-port [0-9]*/-port $INTERNAL_PORT/" /etc/systemd/system/sub-store.service
systemctl daemon-reload
systemctl restart sub-store
sleep 1
ok "Sub-Store 已切换到内部端口 $INTERNAL_PORT"

# 写 Caddyfile
mkdir -p /var/log/caddy /var/www/$DOMAIN
cat > /etc/caddy/Caddyfile << CADDEOF
$DOMAIN {
    encode gzip zstd

    log {
        output file /var/log/caddy/${DOMAIN}-access.log {
            roll_size 20MiB
            roll_keep 10
            roll_keep_for 336h
        }
        format json
    }

    @old_doh path /dns-query
    respond @old_doh 404

    handle $DOH_PATH* {
        uri replace $DOH_PATH /dns-query
        reverse_proxy 127.0.0.1:8054
    }

    handle /api/* {
        reverse_proxy 127.0.0.1:$INTERNAL_PORT
    }

    root * /var/www/$DOMAIN
    file_server
    try_files {path} /index.html
}
CADDEOF

# 默认伪装页面
if [ ! -f /var/www/$DOMAIN/index.html ]; then
  curl -sSL "https://raw.githubusercontent.com/kzb12580/sub-store/main/decoy/index.html" \
    -o /var/www/$DOMAIN/index.html 2>/dev/null || true
fi

# 防火墙放行 80/443
if command -v ufw &>/dev/null; then
  ufw status | grep -q "80/tcp"  || ufw allow 80/tcp  comment "HTTP" </dev/null 2>/dev/null
  ufw status | grep -q "443/tcp" || ufw allow 443/tcp comment "HTTPS" </dev/null 2>/dev/null
  ufw reload 2>/dev/null || true
fi

# 启动 Caddy
systemctl enable caddy --quiet 2>/dev/null
systemctl restart caddy
sleep 2

if systemctl is-active --quiet caddy; then
  ok "Caddy 已启动，SSL 证书自动申请中..."
else
  wr "Caddy 启动失败: journalctl -u caddy -n 10"
fi

# 更新 .env
sed -i "s/^PORT=.*/PORT=$INTERNAL_PORT/" "$DIR/.env" 2>/dev/null
echo "DOMAIN=$DOMAIN" >> "$DIR/.env"

echo ""
echo -e "${G}✅ 域名绑定完成！${N}"
echo ""
echo -e "  🌐 访问:     ${C}https://$DOMAIN${N}"
echo -e "  🔒 DOH:      ${C}https://$DOMAIN$DOH_PATH?name=google.com${N}"
echo -e "  📦 订阅:     ${C}https://$DOMAIN/api/sub/all/clash${N}"
echo ""
echo -e "  ${Y}请确保 $DOMAIN 的 A 记录已指向本机 IP${N}"
echo -e "  ${Y}Caddy 会自动申请 Let's Encrypt 证书${N}"
echo ""
DOMAINEOF
chmod +x "$SCRIPTS/setup-domain.sh"

# ─── 防火墙 ─────────────────────────────────────────────────────
p "配置防火墙..."
if command -v ufw &>/dev/null; then
  ufw default deny incoming </dev/null 2>/dev/null
  ufw default allow outgoing </dev/null 2>/dev/null
  ufw status | grep -q "$SSH_PORT/tcp" || ufw allow "$SSH_PORT/tcp" comment "SSH" </dev/null 2>/dev/null
  ufw status | grep -q "$PORT/tcp"     || ufw allow "$PORT/tcp" comment "Sub-Store" </dev/null 2>/dev/null
  if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable </dev/null 2>/dev/null || true
  fi
  ufw reload 2>/dev/null || true
  ok "防火墙就绪（开放 $SSH_PORT, $PORT）"
fi

# ─── 验证 ───────────────────────────────────────────────────────
echo ""
p "验证服务..."

if curl -sf "http://127.0.0.1:$PORT/api/system/info" >/dev/null 2>&1; then
  ok "Sub-Store API ✓"
else
  wr "Sub-Store API 未响应"
fi

sleep 2
if curl -sf "http://127.0.0.1:$PORT$DOH_PATH?name=google.com&type=A" 2>/dev/null | grep -q "Answer" 2>/dev/null; then
  ok "DOH 解析 ✓"
else
  wr "DOH 未就绪（可能需等几秒）"
fi

# ─── 完成 ───────────────────────────────────────────────────────
echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║                  ✅ 部署完成！                        ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
echo ""
if [ -n "$SERVER_IP" ]; then
  echo -e "  🌐 访问:     ${C}http://$SERVER_IP:$PORT${N}"
  echo -e "  🔒 DOH:      ${C}http://$SERVER_IP:$PORT$DOH_PATH?name=google.com${N}"
  echo -e "  📦 订阅:     ${C}http://$SERVER_IP:$PORT/api/sub/all/clash${N}"
else
  echo -e "  🌐 访问:     ${C}http://你的IP:$PORT${N}"
fi
echo ""
echo -e "  📋 管理命令:"
echo -e "     重启:       ${Y}systemctl restart sub-store${N}"
echo -e "     日志:       ${Y}journalctl -u sub-store -f${N}"
echo -e "     DOH 重启:   ${Y}cd $DOH_DIR && docker compose restart${N}"
echo ""
echo -e "  🔗 后续绑定域名+HTTPS:"
echo -e "     ${Y}bash $SCRIPTS/setup-domain.sh your-domain.com${N}"
echo ""
echo -e "  📁 安装目录: $DIR"
echo ""
