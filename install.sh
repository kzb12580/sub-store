#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

PORT=${1:-8888}
INSTALL_DIR="/opt/sub-store"
DATA_DIR="$INSTALL_DIR/data"
REPO="kzb12580/sub-store"

echo -e "${BLUE}══════════════════════════════════════${NC}"
echo -e "${BLUE}  Sub-Store 一键安装${NC}"
echo -e "${BLUE}══════════════════════════════════════${NC}"
echo ""

# 停止旧服务
systemctl stop sub-store 2>/dev/null || true

# 安装 git
if ! command -v git &>/dev/null; then
  info "安装 git..."
  apt-get update -qq </dev/null && apt-get install -y -qq git </dev/null || \
  yum install -y -q git </dev/null 2>/dev/null || true
fi

# 检查 Go
HAS_GO=false
if command -v go &>/dev/null; then
  info "Go $(go version | grep -oP 'go\K[0-9.]+') 已安装"
  HAS_GO=true
else
  info "未安装 Go，将下载预编译版本"
fi

mkdir -p "$INSTALL_DIR" "$DATA_DIR"

# 获取源码
BUILD_OK=false
if [ -f "./main.go" ] && [ -f "./go.mod" ]; then
  info "从当前目录编译..."
  CGO_ENABLED=0 go build -ldflags="-s -w" -o "$INSTALL_DIR/sub-store" . && BUILD_OK=true
elif [ -d "$INSTALL_DIR/src/.git" ]; then
  info "更新源码..."
  cd "$INSTALL_DIR/src" && git pull -q </dev/null 2>/dev/null
  info "编译..."
  CGO_ENABLED=0 go build -ldflags="-s -w" -o "$INSTALL_DIR/sub-store" . && BUILD_OK=true
else
  info "克隆仓库..."
  git clone --depth 1 "https://github.com/$REPO.git" "$INSTALL_DIR/src" </dev/null 2>/dev/null
  if [ "$HAS_GO" = true ]; then
    cd "$INSTALL_DIR/src"
    info "编译..."
    CGO_ENABLED=0 go build -ldflags="-s -w" -o "$INSTALL_DIR/sub-store" . && BUILD_OK=true
  fi
fi

# 编译失败则下载预编译
if [ "$BUILD_OK" = false ] || [ ! -f "$INSTALL_DIR/sub-store" ]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
  esac
  info "下载预编译版本 ($ARCH)..."
  URL="https://github.com/$REPO/releases/latest/download/sub-store-linux-$ARCH"
  curl -sSL -o "$INSTALL_DIR/sub-store" "$URL" </dev/null || \
  wget -q -O "$INSTALL_DIR/sub-store" "$URL" </dev/null || \
  err "下载失败，请安装 Go 后重试"
fi

chmod +x "$INSTALL_DIR/sub-store"
ok "二进制就绪"

# 复制前端
if [ -d "$INSTALL_DIR/src/frontend/dist" ]; then
  mkdir -p "$INSTALL_DIR/frontend/dist"
  cp -f "$INSTALL_DIR/src/frontend/dist/index.html" "$INSTALL_DIR/frontend/dist/" 2>/dev/null
fi

# 配置
if [ ! -f "$DATA_DIR/config.json" ]; then
  cat > "$DATA_DIR/config.json" << 'EOF'
{
  "data_dir": "data",
  "log_level": "info",
  "doh_servers": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"],
  "doh_engine": "cloudflare"
}
EOF
  ok "配置已生成"
fi

# Systemd
cat > /etc/systemd/system/sub-store.service << EOF
[Unit]
Description=Sub-Store
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/sub-store -port $PORT -config $DATA_DIR/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sub-store --quiet 2>/dev/null
systemctl restart sub-store
sleep 1

if systemctl is-active --quiet sub-store; then
  ok "服务已启动"
else
  err "启动失败: journalctl -u sub-store -n 20"
fi

echo ""
echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "  访问: ${BLUE}http://localhost:$PORT${NC}"
echo -e "  日志: ${YELLOW}journalctl -u sub-store -f${NC}"
echo -e "  重启: ${YELLOW}systemctl restart sub-store${NC}"
echo ""
