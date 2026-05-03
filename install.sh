#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Sub-Store 一键安装 — DOH + 订阅转换 + 伪装网站 + 防扫描
#  用法: curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash
# ═══════════════════════════════════════════════════════════════
set -e

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
p()  { echo -e "${B}[·]${N} $1"; }
ok() { echo -e "${G}[✓]${N} $1"; }
wr() { echo -e "${Y}[!]${N} $1"; }
die(){ echo -e "${R}[✗]${N} $1"; exit 1; }

trap 'echo ""; wr "安装中断"; exit 1' INT TERM

# ─── 参数 ───────────────────────────────────────────────────────
DOMAIN="" PORT=8888 DOH_PATH="/dns-query" SSH_PORT=307
REPO="kzb12580/sub-store"
DIR="/opt/sub-store"

while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)    DOMAIN="$2";    shift 2 ;;
    --port)      PORT="$2";      shift 2 ;;
    --doh-path)  DOH_PATH="$2";  shift 2 ;;
    --ssh-port)  SSH_PORT="$2";  shift 2 ;;
    --dir)       DIR="$2";       shift 2 ;;
    -h|--help)
      echo "用法: bash install.sh [选项]"
      echo ""
      echo "选项:"
      echo "  --domain DOMAIN     域名（必填，如 sub.example.com）"
      echo "  --port PORT         Sub-Store 端口（默认 8888）"
      echo "  --doh-path PATH     DOH 路径（默认 /dns-query）"
      echo "  --ssh-port PORT     SSH 端口（默认 307）"
      echo "  --dir DIR           安装目录（默认 /opt/sub-store）"
      echo "  -h, --help          帮助"
      exit 0 ;;
    *) wr "未知参数: $1"; shift ;;
  esac
done

# ─── 交互输入 ───────────────────────────────────────────────────
echo -e ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${C}║          Sub-Store 一键部署 (DOH + 订阅 + 伪装)          ║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${N}"
echo ""

if [ -z "$DOMAIN" ]; then
  echo -n "请输入域名 (如 sub.940307.xyz): "
  read -r DOMAIN </dev/tty 2>/dev/null || read -r DOMAIN
fi
[ -z "$DOMAIN" ] && die "域名不能为空"

echo ""
p "域名: $DOMAIN"
p "Sub-Store 端口: $PORT"
p "DOH 路径: $DOH_PATH"
p "SSH 端口: $SSH_PORT"
p "安装目录: $DIR"
echo ""
echo -n "确认开始安装？[Y/n] "
read -r CONFIRM </dev/tty 2>/dev/null || CONFIRM="y"
[[ "$CONFIRM" =~ ^[Nn]$ ]] && exit 0

# 端口冲突检测
for CHK_PORT in 80 443; do
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
        die "端口 $CHK_PORT 冲突，无法继续"
      fi
    fi
  fi
done

echo ""
p "开始安装..."

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
    if [ "$apt_update_done" = false ]; then
      apt-get update -qq </dev/null 2>/dev/null
      apt_update_done=true
    fi
    apt-get install -y -qq "$@" </dev/null 2>/dev/null
  elif command -v dnf &>/dev/null; then
    dnf install -y -q "$@" </dev/null 2>/dev/null
  elif command -v yum &>/dev/null; then
    yum install -y -q "$@" </dev/null 2>/dev/null
  fi
}

command -v curl   &>/dev/null || pkg_install curl
command -v git    &>/dev/null || pkg_install git
command -v jq     &>/dev/null || pkg_install jq

# Go
HAS_GO=false
if command -v go &>/dev/null; then
  ok "Go $(go version | grep -oP 'go\K[0-9.]+')"
  HAS_GO=true
else
  p "安装 Go..."
  GO_VER="1.22.4"
  curl -sSL "https://go.dev/dl/go${GO_VER}.linux-${ARCH}.tar.gz" </dev/null | tar -C /usr/local -xz
  export PATH="/usr/local/go/bin:$PATH"
  echo 'export PATH="/usr/local/go/bin:$PATH"' >> /etc/profile
  ok "Go $GO_VER"
  HAS_GO=true
fi

# Docker
if ! command -v docker &>/dev/null; then
  p "安装 Docker..."
  curl -fsSL https://get.docker.com </dev/null | sh 2>/dev/null
  systemctl enable docker --quiet 2>/dev/null
  systemctl start docker 2>/dev/null
fi
ok "Docker $(docker --version | grep -oP 'version \K[0-9.]+')"

# Caddy
if ! command -v caddy &>/dev/null; then
  p "安装 Caddy..."
  if command -v apt-get &>/dev/null; then
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
    curl -sSL "https://caddyserver.com/api/download?os=linux&arch=${ARCH}" </dev/null -o /usr/bin/caddy
    chmod +x /usr/bin/caddy
  fi
fi
ok "Caddy $(caddy version 2>/dev/null | head -1)"

# UFW
if command -v ufw &>/dev/null; then
  ok "UFW 已安装"
else
  pkg_install ufw 2>/dev/null || true
fi

# ─── 创建目录结构 ────────────────────────────────────────────────
p "创建目录..."
DATA="$DIR/data"
DOH="$DIR/doh"
WEB="/var/www/$DOMAIN"
mkdir -p "$DATA" "$DOH" "$WEB"

# ─── 写入 Caddyfile ─────────────────────────────────────────────
p "配置 Caddy..."
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

    # 拦截旧 DOH 路径返回 404
    @old_doh path /dns-query
    respond @old_doh 404

    # DOH 路径（伪装）
    handle $DOH_PATH* {
        uri replace $DOH_PATH /dns-query
        reverse_proxy 127.0.0.1:8054
    }

    # Sub-Store API
    handle /api/* {
        reverse_proxy 127.0.0.1:$PORT
    }

    # 默认：伪装网站
    root * $WEB
    file_server
    try_files {path} /index.html
}
CADDEOF

mkdir -p /var/log/caddy
systemctl restart caddy 2>/dev/null || systemctl start caddy 2>/dev/null || true
ok "Caddy 配置完成"

# ─── 写入 DOH 配置 ───────────────────────────────────────────────
p "配置 DOH..."

cat > "$DOH/docker-compose.yml" << 'YMLEOF'
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

cat > "$DOH/Corefile" << 'COREEOF'
.:8053 {
    errors
    log
    forward . 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
    cache 300
}
COREEOF

ok "DOH 配置完成"

# ─── 写入伪装网站 ───────────────────────────────────────────────
p "生成伪装网站..."
cat > "$WEB/index.html" << 'HTMLEOF'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>绿洲行动 | 环境保护公益倡议</title>
<meta name="description" content="关注环境保护、低碳生活、垃圾分类与生态修复的公益倡议页面。">
<style>
:root{color-scheme:light;--g:#1f7a4d;--d:#123d2a;--s:#eef8f1;--t:#203028}
*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans SC",sans-serif;color:var(--t);background:#fbfdfb;line-height:1.7}
header{min-height:58vh;display:grid;place-items:center;padding:56px 20px;background:linear-gradient(135deg,#e9f8ee 0%,#f7fbf4 55%,#dff2e8 100%)}
.hero{max-width:880px;text-align:center}
.badge{display:inline-block;padding:6px 14px;border-radius:999px;background:#d9f0e2;color:var(--g);font-weight:700;font-size:14px}
h1{margin:22px 0 14px;font-size:clamp(34px,6vw,68px);line-height:1.08;color:var(--d);letter-spacing:-.04em}
.lead{max-width:720px;margin:0 auto;font-size:clamp(17px,2.4vw,22px);color:#3d5a49}
main{max-width:1040px;margin:0 auto;padding:48px 20px 64px}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px;margin-top:28px}
.card{background:#fff;border:1px solid #e4efe7;border-radius:22px;padding:24px;box-shadow:0 10px 30px rgba(31,122,77,.07)}
.card h2{margin:0 0 10px;color:var(--g);font-size:22px}
section{margin-top:44px}h2.section-title{font-size:30px;color:var(--d);margin:0 0 12px}
ul{padding-left:1.2em}
.callout{background:var(--s);border-left:5px solid var(--g);border-radius:18px;padding:22px 24px}
footer{text-align:center;padding:30px 20px;color:#6b7f72;border-top:1px solid #edf3ef}
@media(max-width:760px){.grid{grid-template-columns:1fr}header{min-height:auto}}
</style>
</head>
<body>
<header><div class="hero">
<span class="badge">🌍 公益倡议</span>
<h1>守护每一片<br>绿色家园</h1>
<p class="lead">我们倡导低碳生活、垃圾分类与生态修复，从身边小事做起，为子孙后代留下碧水蓝天。</p>
</div></header>
<main>
<section>
<h2 class="section-title">我们的行动方向</h2>
<div class="grid">
<div class="card"><h2>🌱 低碳生活</h2><p>推广绿色出行、节能减排，减少碳足迹，让生活更环保、更健康。</p></div>
<div class="card"><h2>♻️ 垃圾分类</h2><p>从源头做起，科学分类，让资源循环利用，减少填埋焚烧。</p></div>
<div class="card"><h2>🌳 生态修复</h2><p>植树造林、湿地保护、荒漠化治理，让大地重新焕发生机。</p></div>
</div>
</section>
<section>
<h2 class="section-title">每个人都能做到</h2>
<div class="callout">
<ul>
<li>出行优先选择公共交通、骑行或步行</li>
<li>减少一次性用品使用，自带购物袋和水杯</li>
<li>节约水电，随手关灯关水</li>
<li>参与社区环保志愿活动</li>
<li>支持可持续发展的产品和企业</li>
</ul>
</div>
</section>
<section>
<h2 class="section-title">关于绿洲行动</h2>
<p>绿洲行动是一个民间环保公益倡议，旨在汇聚社会力量，关注身边的环境问题。我们相信，每一个微小的行动，都能汇聚成改变世界的力量。</p>
</section>
</main>
<footer>
<p>© 2026 绿洲行动 — 环境保护，人人有责</p>
</footer>
</body>
</html>
HTMLEOF

ok "伪装网站已生成"

# ─── 克隆并编译 Sub-Store ────────────────────────────────────────
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
  p "编译 Sub-Store..."
  CGO_ENABLED=0 go build -ldflags="-s -w" -o "$DIR/sub-store" . 2>&1 && BUILD_OK=true
fi

if [ "$BUILD_OK" = false ]; then
  p "下载预编译版本..."
  URL="https://github.com/$REPO/releases/latest/download/sub-store-linux-$ARCH"
  curl -sSL -o "$DIR/sub-store" "$URL" </dev/null 2>/dev/null || \
  wget -q -O "$DIR/sub-store" "$URL" </dev/null 2>/dev/null || \
  die "获取失败，请安装 Go 后重试"
fi

chmod +x "$DIR/sub-store"
ok "Sub-Store 就绪"

# ─── 配置文件 ───────────────────────────────────────────────────
if [ ! -f "$DATA/config.json" ]; then
  cat > "$DATA/config.json" << CFGEOF
{
  "data_dir": "$DATA",
  "log_level": "info",
  "doh_servers": ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"],
  "doh_engine": "cloudflare"
}
CFGEOF
fi

# ─── Systemd 服务 ───────────────────────────────────────────────
p "创建 systemd 服务..."
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

# ─── 防火墙 ─────────────────────────────────────────────────────
p "配置防火墙..."
if command -v ufw &>/dev/null; then
  # 备份现有规则
  cp /etc/default/ufw /etc/default/ufw.bak.$(date +%s) 2>/dev/null || true

  ufw default deny incoming </dev/null 2>/dev/null
  ufw default allow outgoing </dev/null 2>/dev/null

  # SSH（如果当前规则里没有）
  ufw status | grep -q "$SSH_PORT/tcp" || ufw allow "$SSH_PORT/tcp" comment "SSH" </dev/null 2>/dev/null
  # HTTP + HTTPS
  ufw status | grep -q "80/tcp"     || ufw allow 80/tcp     comment "HTTP ACME" </dev/null 2>/dev/null
  ufw status | grep -q "443/tcp"    || ufw allow 443/tcp    comment "HTTPS" </dev/null 2>/dev/null

  # 启用（如果还没启用）
  if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable </dev/null 2>/dev/null || true
  fi
  ufw reload </dev/null 2>/dev/null || true
  ok "防火墙就绪（仅开放 $SSH_PORT, 80, 443）"
fi

# ─── 启动服务 ───────────────────────────────────────────────────
p "启动服务..."

# Docker
cd "$DOH"
docker compose pull -q 2>/dev/null || docker-compose pull -q 2>/dev/null || true
docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null
ok "DOH 服务已启动"

# Sub-Store
systemctl restart sub-store
sleep 1
if systemctl is-active --quiet sub-store; then
  ok "Sub-Store 已启动"
else
  die "Sub-Store 启动失败: journalctl -u sub-store -n 20"
fi

# Caddy
if systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null; then
  ok "Caddy 已重载"
else
  wr "Caddy 启动失败（可能端口冲突），请手动检查: journalctl -u caddy -n 10"
fi

# ─── 验证 ───────────────────────────────────────────────────────
echo ""
p "验证服务..."

# Sub-Store API
if curl -sf "http://localhost:$PORT/api/system/info" >/dev/null 2>&1; then
  ok "Sub-Store API ✓"
else
  wr "Sub-Store API 未响应"
fi

# DOH
sleep 2
DOH_TEST=$(curl -sf "http://localhost:8054/dns-query?name=google.com&type=A" 2>/dev/null)
if echo "$DOH_TEST" | grep -q "Answer" 2>/dev/null; then
  ok "DOH 解析 ✓"
else
  wr "DOH 测试未通过（可能需要等几秒）"
fi

# ─── 写入安装信息 ────────────────────────────────────────────────
cat > "$DIR/.env" << EOF
DOMAIN=$DOMAIN
PORT=$PORT
DOH_PATH=$DOH_PATH
SSH_PORT=$SSH_PORT
INSTALL_DIR=$DIR
INSTALLED_AT=$(date -Iseconds)
EOF

# ─── 完成 ───────────────────────────────────────────────────────
echo ""
echo -e "${G}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║                  ✅ 部署完成！                        ║${N}"
echo -e "${G}╚══════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "  🌐 伪装网站:    ${C}https://$DOMAIN${N}"
echo -e "  📦 Sub-Store:   ${C}https://$DOMAIN/api/system/info${N}"
echo -e "  🔒 DOH:         ${C}https://$DOMAIN$DOH_PATH?name=google.com${N}"
echo -e ""
echo -e "  📋 管理命令:"
echo -e "     Sub-Store:  ${Y}systemctl restart sub-store${N}"
echo -e "     DOH:        ${Y}cd $DOH && docker compose restart${N}"
echo -e "     Caddy:      ${Y}systemctl reload caddy${N}"
echo -e "     防火墙:     ${Y}ufw status${N}"
echo -e "     日志:       ${Y}journalctl -u sub-store -f${N}"
echo ""
echo -e "  📁 安装目录: $DIR"
echo -e "  📁 配置文件: $DIR/.env"
echo ""
echo -e "  ${Y}注意: 请确保 $DOMAIN 的 DNS A 记录已指向本机 IP${N}"
echo -e "  ${Y}Caddy 会自动申请 SSL 证书（首次需要 DNS 已生效）${N}"
echo ""
