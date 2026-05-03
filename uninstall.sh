#!/bin/bash
# Sub-Store 卸载脚本
set -e

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
p()  { echo -e "${B}[·]${N} $1"; }
ok() { echo -e "${G}[✓]${N} $1"; }

DIR="/opt/sub-store"
ENV="$DIR/.env"

if [ -f "$ENV" ]; then
  source "$ENV"
  echo -e "${Y}检测到安装信息:${N}"
  [ -n "$SERVER_IP" ] && echo "  IP:   $SERVER_IP"
  [ -n "$DOMAIN" ]    && echo "  域名: $DOMAIN"
  echo "  端口: $PORT"
  echo "  目录: ${INSTALL_DIR:-$DIR}"
  DIR="${INSTALL_DIR:-$DIR}"
fi

echo ""
echo -e "${R}⚠  即将删除:${N}"
echo "  - Sub-Store 服务 ($DIR)"
echo "  - DOH Docker 容器"
[ -n "$DOMAIN" ] && echo "  - Caddy 配置 + 伪装网站"
echo ""
echo -n "确认卸载？[y/N] "
read -r CONFIRM </dev/tty 2>/dev/null || CONFIRM="n"
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "取消" && exit 0

echo ""
p "停止服务..."
systemctl stop sub-store 2>/dev/null || true
systemctl disable sub-store 2>/dev/null || true
rm -f /etc/systemd/system/sub-store.service

p "停止 Docker..."
if [ -f "$DIR/doh/docker-compose.yml" ]; then
  cd "$DIR/doh"
  docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
fi
docker rm -f doh-coredns doh-server 2>/dev/null || true

if [ -n "$DOMAIN" ]; then
  p "清理 Caddy..."
  systemctl stop caddy 2>/dev/null || true
  rm -f /etc/caddy/Caddyfile
  rm -rf "/var/www/$DOMAIN" 2>/dev/null || true
  rm -rf /var/log/caddy 2>/dev/null || true
  # 还原默认 Caddyfile
  echo ':80 { respond "OK" }' > /etc/caddy/Caddyfile 2>/dev/null || true
  systemctl start caddy 2>/dev/null || true
fi

p "删除文件..."
rm -rf "$DIR"

p "重载 systemd..."
systemctl daemon-reload

echo ""
echo -e "${G}✅ 卸载完成${N}"
echo ""
