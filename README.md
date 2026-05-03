# Sub-Store

DOH + 订阅转换 + 伪装网站，一键部署。

## 安装

```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash
```

默认端口 80，IP 直接访问。指定端口：

```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/install.sh | bash -s -- --port 8080
```

## 安装后

直接用 IP 访问：

- `http://你的IP` — Sub-Store Web 面板
- `http://你的IP/dns-query?name=google.com` — DOH
- `http://你的IP/api/sub/all/clash` — 订阅链接

## 绑定域名（可选）

```bash
bash /opt/sub-store/scripts/setup-domain.sh your-domain.com
```

自动完成：安装 Caddy → 申请 SSL → 配置反向代理 → 伪装网站

绑定后：

- `https://your-domain` — 伪装网站
- `https://your-domain/dns-query?name=google.com` — DOH (HTTPS)
- `https://your-domain/api/sub/all/clash` — 订阅链接

## 管理

```bash
systemctl restart sub-store      # 重启
journalctl -u sub-store -f       # 日志
cd /opt/sub-store/doh && docker compose restart  # DOH
```

## 卸载

```bash
bash <(curl -sSL https://raw.githubusercontent.com/kzb12580/sub-store/main/uninstall.sh)
```

## 参数

```
--port PORT        服务端口（默认 80）
--doh-path PATH    DOH 路径（默认 /dns-query）
--ssh-port PORT    SSH 端口（默认 307）
--dir DIR          安装目录（默认 /opt/sub-store）
```

## License

MIT
