# DOH Server

一键部署 DNS-over-HTTPS + 服务器安全加固 + 伪装网站。通用脚本，任意 VPS 适用。

## 安装

**交互式（推荐）：**
```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/doh-server/main/manage.sh | bash
```

**IP 直连模式：**
```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/doh-server/main/manage.sh | bash -s -- --ip
```

**域名模式（自动 HTTPS）：**
```bash
curl -sSL https://raw.githubusercontent.com/kzb12580/doh-server/main/manage.sh | bash -s -- --domain sub.example.com
```

## 管理

安装后运行管理脚本：

```bash
bash /opt/doh-server/manage.sh
```

```
╔══════════════════════════════════════════════════════╗
║           DOH + 安全加固 管理脚本                     ║
╚══════════════════════════════════════════════════════╝

  1. 安装（IP 直连，无需域名）
  2. 安装（域名 + HTTPS）
  3. 查看状态
  4. 添加/更换域名
  5. 删除域名（回退到 IP 模式）
  6. 重启 DOH
  7. 查看防火墙
  8. 卸载
  0. 退出
```

## 部署内容

| 组件 | 说明 |
|------|------|
| **CoreDNS** | 上游 DNS 解析（Docker） |
| **DOH Server** | DNS-over-HTTPS 端点（Docker） |
| **Caddy** | 反向代理 + 自动 HTTPS + ECH（域名模式） |
| **UFW** | 防火墙，默认拒绝入站，仅开放必要端口 |
| **伪装网站** | 环保公益页面（域名模式） |

## DOH 使用

安装后在客户端配置 DOH 地址：

```
# IP 模式
http://你的IP:端口/dns-query

# 域名模式
https://你的域名/dns-query
```

## 管理命令

```bash
bash /opt/doh-server/manage.sh          # 打开管理菜单
cd /opt/doh-server/doh && docker compose restart  # 重启 DOH
systemctl reload caddy                  # 重载 Caddy
ufw status                              # 查看防火墙
```

## 卸载

```bash
bash /opt/doh-server/manage.sh
# 选择 8
```

## License

MIT
