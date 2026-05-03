#!/bin/bash
# Sub-Store 一键安装脚本
# 用法: curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash -s -- --domain sub.example.com
# 或:   bash install.sh --domain sub.example.com

set -e

# ===== 颜色 =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 关键：防止 curl|bash 时 stdin 被吃掉
exec < /dev/tty 2>/dev/null || true

# ===== 参数 =====
DOMAIN=""
PORT=8888
SKIP_NGINX=false
SKIP_SSL=false
INSTALL_DIR="/opt/sub-store"
DATA_DIR="/opt/sub-store/data"
GITHUB_REPO="kzb12580/sub-store"

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)     DOMAIN="$2"; shift 2 ;;
    --port)       PORT="$2"; shift 2 ;;
    --skip-nginx) SKIP_NGINX=true; shift ;;
    --skip-ssl)   SKIP_SSL=true; shift ;;
    --dir)        INSTALL_DIR="$2"; DATA_DIR="$2/data"; shift 2 ;;
    -h|--help)
      echo "Sub-Store 安装脚本"
      echo ""
      echo "用法: bash install.sh [选项]"
      echo ""
      echo "选项:"
      echo "  --domain DOMAIN    域名（如 sub.940307.xyz）"
      echo "  --port PORT        服务端口（默认 8888）"
      echo "  --dir DIR          安装目录（默认 /opt/sub-store）"
      echo "  --skip-nginx       跳过 Nginx 配置"
      echo "  --skip-ssl         跳过 SSL 证书申请"
      echo "  -h, --help         显示帮助"
      exit 0
      ;;
    *) warn "未知参数: $1"; shift ;;
  esac
done

# ===== 系统检测 =====
info "检测系统环境..."
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "不支持的架构: $ARCH" ;;
esac

if [ "$OS" != "Linux" ]; then
  err "仅支持 Linux 系统"
fi

info "系统: $OS $ARCH"

# ===== 工具函数 =====
check_cmd() {
  command -v "$1" &>/dev/null
}

install_pkg() {
  local pkg="$1"
  if check_cmd apt-get; then
    apt-get update -qq 2>/dev/null && apt-get install -y -qq "$pkg" </dev/null 2>/dev/null
  elif check_cmd dnf; then
    dnf install -y -q "$pkg" </dev/null 2>/dev/null
  elif check_cmd yum; then
    yum install -y -q "$pkg" </dev/null 2>/dev/null
  fi
}

# ===== 检查已有安装 =====
if systemctl is-active --quiet sub-store 2>/dev/null; then
  warn "Sub-Store 服务已在运行"
  echo -n "是否重新安装？[y/N] "
  read -r REPLY </dev/tty 2>/dev/null || REPLY="y"
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "取消安装"
    exit 0
  fi
  systemctl stop sub-store 2>/dev/null || true
fi

# ===== 依赖检查 =====
HAS_GO=false
if check_cmd go; then
  GO_VER=$(go version 2>/dev/null | grep -oP 'go\K[0-9.]+' || echo "0")
  info "已安装 Go $GO_VER"
  HAS_GO=true
else
  info "未检测到 Go，将下载预编译版本"
fi

if ! check_cmd git; then
  info "安装 git..."
  install_pkg git
fi

# ===== 获取代码 =====
info "获取 Sub-Store..."

mkdir -p "$INSTALL_DIR" "$DATA_DIR"

NEED_BUILD=false

# 方式1：从当前目录构建（开发用）
if [ -f "./main.go" ] && [ -f "./go.mod" ] && [ -f "./frontend/dist/index.html" ]; then
  info "从当前目录构建..."
  SRC_DIR="$(pwd)"
  NEED_BUILD=true

# 方式2：已有源码，更新
elif [ -d "$INSTALL_DIR/src/.git" ]; then
  info "更新现有源码..."
  cd "$INSTALL_DIR/src"
  git pull --quiet 2>/dev/null || warn "更新失败，使用现有代码"
  SRC_DIR="$INSTALL_DIR/src"
  NEED_BUILD=true

# 方式3：克隆仓库
else
  info "克隆仓库..."
  if git clone --quiet --depth 1 "https://github.com/${GITHUB_REPO}.git" "$INSTALL_DIR/src" </dev/null 2>/dev/null; then
    SRC_DIR="$INSTALL_DIR/src"
    NEED_BUILD=true
  else
    warn "Git clone 失败，将尝试下载预编译版本"
  fi
fi

# ===== 编译或下载 =====
if [ "$NEED_BUILD" = true ] && [ "$HAS_GO" = true ]; then
  info "编译 Sub-Store..."
  cd "$SRC_DIR"
  CGO_ENABLED=0 go build -ldflags="-s -w" -o "$INSTALL_DIR/sub-store" . 2>&1
  if [ $? -ne 0 ]; then
    err "编译失败"
  fi
  ok "编译完成"
fi

# 如果编译产物不存在，尝试下载预编译版本
if [ ! -f "$INSTALL_DIR/sub-store" ] || [ ! -x "$INSTALL_DIR/sub-store" ]; then
  info "下载预编译版本..."
  
  # 尝试从 GitHub Release 下载
  RELEASE_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
  DOWNLOAD_URL="${RELEASE_BASE}/sub-store-linux-${ARCH}"
  
  if check_cmd curl; then
    curl -sSL -o "$INSTALL_DIR/sub-store" "$DOWNLOAD_URL" </dev/null 2>/dev/null
  elif check_cmd wget; then
    wget -q -O "$INSTALL_DIR/sub-store" "$DOWNLOAD_URL" </dev/null 2>/dev/null
  else
    err "需要 curl 或 wget 来下载"
  fi
  
  if [ ! -s "$INSTALL_DIR/sub-store" ]; then
    rm -f "$INSTALL_DIR/sub-store"
    err "下载失败，请确保：\n  1. 网络连通 GitHub\n  2. 已安装 Go 可从源码编译\n  3. 或手动下载: $DOWNLOAD_URL"
  fi
  
  chmod +x "$INSTALL_DIR/sub-store"
  ok "下载完成"
fi

chmod +x "$INSTALL_DIR/sub-store"

# 复制前端文件（如果有）
if [ -d "$SRC_DIR/frontend/dist" ]; then
  mkdir -p "$INSTALL_DIR/frontend/dist"
  cp -f "$SRC_DIR/frontend/dist/index.html" "$INSTALL_DIR/frontend/dist/" 2>/dev/null || true
fi

# ===== 配置文件 =====
if [ ! -f "$DATA_DIR/config.json" ]; then
  info "生成配置文件..."
  cat > "$DATA_DIR/config.json" << 'CONF'
{
  "data_dir": "data",
  "log_level": "info",
  "doh_servers": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"],
  "doh_engine": "cloudflare"
}
CONF
  ok "配置已生成"
fi

# ===== Systemd 服务 =====
info "创建 systemd 服务..."

cat > /etc/systemd/system/sub-store.service << EOF
[Unit]
Description=Sub-Store Subscription Manager
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/sub-store -port ${PORT} -config ${DATA_DIR}/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sub-store --quiet 2>/dev/null
systemctl restart sub-store
sleep 1

if systemctl is-active --quiet sub-store; then
  ok "服务已启动 (端口: $PORT)"
else
  err "服务启动失败，运行 journalctl -u sub-store -n 20 查看日志"
fi

# ===== Nginx =====
if [ "$SKIP_NGINX" = false ] && [ -n "$DOMAIN" ]; then
  # 安装 Nginx
  if ! check_cmd nginx; then
    info "安装 Nginx..."
    install_pkg nginx
  fi

  if check_cmd nginx; then
    info "配置 Nginx 反向代理..."

    # 检测 nginx 配置目录
    NGINX_CONF_DIR="/etc/nginx"
    if [ -d "$NGINX_CONF_DIR/sites-available" ]; then
      # Debian/Ubuntu 风格
      cat > "$NGINX_CONF_DIR/sites-available/sub-store" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
    }
}
EOF
      ln -sf "$NGINX_CONF_DIR/sites-available/sub-store" "$NGINX_CONF_DIR/sites-enabled/sub-store"
      rm -f "$NGINX_CONF_DIR/sites-enabled/default" 2>/dev/null
    elif [ -d "$NGINX_CONF_DIR/conf.d" ]; then
      # CentOS/RHEL 风格
      cat > "$NGINX_CONF_DIR/conf.d/sub-store.conf" << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
    }
}
EOF
    fi

    if nginx -t 2>&1; then
      systemctl reload nginx 2>/dev/null || systemctl restart nginx
      ok "Nginx 配置完成"
    else
      warn "Nginx 配置测试失败"
    fi

    # ===== SSL 证书 =====
    if [ "$SKIP_SSL" = false ]; then
      info "申请 SSL 证书..."
      if ! check_cmd certbot; then
        if check_cmd apt-get; then
          apt-get update -qq 2>/dev/null && apt-get install -y -qq certbot python3-certbot-nginx </dev/null 2>/dev/null
        elif check_cmd dnf; then
          dnf install -y -q certbot python3-certbot-nginx </dev/null 2>/dev/null
        elif check_cmd yum; then
          yum install -y -q certbot python3-certbot-nginx </dev/null 2>/dev/null
        fi
      fi

      if check_cmd certbot; then
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect </dev/null 2>&1 || {
          warn "SSL 证书申请失败"
          warn "请确保 ${DOMAIN} 的 DNS A 记录已指向本机 IP"
          warn "然后手动运行: certbot --nginx -d ${DOMAIN}"
        }
        # 自动续期
        systemctl enable certbot.timer 2>/dev/null || true
        systemctl start certbot.timer 2>/dev/null || true
        ok "SSL 配置完成"
      else
        warn "certbot 安装失败，请手动安装并申请证书"
      fi
    fi
  else
    warn "Nginx 安装失败，跳过反向代理配置"
  fi
fi

# ===== 完成 =====
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Sub-Store 安装完成！${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📡 本地访问: ${BLUE}http://localhost:${PORT}${NC}"
if [ -n "$DOMAIN" ]; then
  if [ "$SKIP_SSL" = false ]; then
    echo -e "  🌐 域名访问: ${BLUE}https://${DOMAIN}${NC}"
  else
    echo -e "  🌐 域名访问: ${BLUE}http://${DOMAIN}${NC}"
  fi
fi
echo ""
echo -e "  📋 管理命令:"
echo -e "     启动: ${YELLOW}systemctl start sub-store${NC}"
echo -e "     停止: ${YELLOW}systemctl stop sub-store${NC}"
echo -e "     重启: ${YELLOW}systemctl restart sub-store${NC}"
echo -e "     日志: ${YELLOW}journalctl -u sub-store -f${NC}"
echo -e "     状态: ${YELLOW}systemctl status sub-store${NC}"
echo ""
echo -e "  📁 安装目录: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "  📁 数据目录: ${YELLOW}${DATA_DIR}${NC}"
echo ""
