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
  echo "  域名: $DOMAIN"
  echo "  端口: $PORT"
  echo "  DOH:  $DOH_PATH"
  echo "  目录: $INSTALL_DIR"
  DIR="${INSTALL_DIR:-$DIR}"
fi

echo ""
echo -e "${R}⚠  即将删除以下内容:${N}"
echo "  - Sub-Store 服务和文件 ($DIR)"
echo "  - DOH Docker 容器和镜像"
echo "  - Caddy 站点配置 (/etc/caddy/Caddyfile)"
echo "  - 伪装网站 (/var/www/$DOMAIN)"
echo "  - systemd 服务 (sub-store.service)"
echo ""
echo -n "确认卸载？[y/N] "
read -r CONFIRM </dev/tty 2>/dev/null || CONFIRM="n"
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "取消" && exit 0

echo ""
p "停止服务..."
systemctl stop sub-store 2>/dev/null || true
systemctl disable sub-store 2>/dev/null || true
systemctl stop caddy 2>/dev/null || true

p "删除 Docker 容器..."
if [ -f "$DIR/doh/docker-compose.yml" ]; then
  cd "$DIR/doh"
  docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
fi
docker rm -f doh-coredns doh-server 2>/dev/null || true

p "删除文件..."
rm -rf "$DIR"
rm -rf "/var/www/$DOMAIN" 2>/dev/null || true
rm -f /etc/systemd/system/sub-store.service

p "重置 Caddy..."
cat > /etc/caddy/Caddyfile << 'EOF'
# Caddy 默认配置
:80 {
    respond "OK"
}
EOF
systemctl start caddy 2>/dev/null || true

p "重载 systemd..."
systemctl daemon-reload

# 可选：清理 UFW 规则
echo ""
echo -n "是否清理 UFW 防火墙规则（80/443）？[y/N] "
read -r UFW_CONFIRM </dev/tty 2>/dev/null || UFW_CONFIRM="n"
if [[ "$UFW_CONFIRM" =~ ^[Yy]$ ]] && command -v ufw &>/dev/null; then
  # 找到并删除 80 和 443 规则
  ufw status numbered | grep -E "(80|443)" | tac | while read -r line; do
    NUM=$(echo "$line" | grep -oP '^\[\K[0-9]+')
    if [ -n "$NUM" ]; then
      echo "y" | ufw delete "$NUM" </dev/null 2>/dev/null || true
    fi
  done
  ufw reload 2>/dev/null || true
  ok "UFW 规则已清理"
fi

echo ""
echo -e "${G}✅ 卸载完成${N}"
echo ""
echo "Caddy 保留运行（可能被其他服务使用）。"
echo "如需完全卸载 Caddy: apt remove caddy"
echo ""
