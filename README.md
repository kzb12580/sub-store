# Sub-Store

一键部署 DOH + 订阅转换 + 伪装网站 + 防扫描。

## 快速安装

```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash
```

脚本会交互式询问域名，也可以直接指定：

```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash -s -- --domain sub.example.com
```

## 部署内容

| 组件 | 说明 |
|------|------|
| **Caddy** | 反向代理 + 自动 HTTPS + ECH |
| **CoreDNS** | 上游 DNS 解析 |
| **DOH Server** | DNS-over-HTTPS 端点 |
| **Sub-Store** | 订阅转换 + Web 管理面板 |
| **UFW** | 防火墙，仅开放 SSH/80/443 |
| **伪装网站** | 默认显示"绿洲行动"环保页面 |

## 安装后访问

- `https://your-domain` — 伪装网站（外人看到的）
- `https://your-domain/dns-query?name=google.com` — DOH
- `https://your-domain/api/system/info` — Sub-Store API

## 订阅链接

```
https://your-domain/api/sub/all/clash
https://your-domain/api/sub/all/singbox
https://your-domain/api/sub/{id}/clash
https://your-domain/api/sub/{id}/singbox
```

## 管理命令

```bash
# Sub-Store
systemctl restart sub-store
systemctl status sub-store
journalctl -u sub-store -f

# DOH
cd /opt/sub-store/doh && docker compose restart

# Caddy
systemctl reload caddy

# 防火墙
ufw status
```

## 卸载

```bash
bash <(curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/uninstall.sh)
```

或本地：

```bash
bash uninstall.sh
```

## 安装脚本参数

```
--domain DOMAIN     域名（必填）
--port PORT         Sub-Store 端口（默认 8888）
--doh-path PATH     DOH 路径（默认 /dns-query）
--ssh-port PORT     SSH 端口（默认 307）
--dir DIR           安装目录（默认 /opt/sub-store）
```

## 目录结构

```
/opt/sub-store/
├── sub-store              # 二进制
├── data/                  # 订阅数据
│   ├── config.json
│   ├── subscriptions.json
│   └── nodes/
├── doh/                   # DOH 配置
│   ├── docker-compose.yml
│   └── Corefile
└── .env                   # 安装参数

/var/www/{domain}/         # 伪装网站
/etc/caddy/Caddyfile       # Caddy 配置
```

## License

MIT
