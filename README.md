# Sub-Store

轻量级订阅转换 + DNS over HTTPS 解析服务

## 功能

- 📦 **订阅管理** — 添加/更新/删除/刷新订阅源
- 🔄 **协议解析** — VMess / VLESS / Trojan / SS / Hysteria2 / TUIC
- 🌐 **DOH 解析** — Cloudflare / Google DNS over HTTPS，5分钟缓存
- ⚡ **订阅转换** — 输出 Clash YAML / Sing-box JSON 配置
- 📊 **节点统计** — 按协议类型统计
- 🖥️ **轻量 Web UI** — 暗色主题单页管理面板

## 快速开始

```bash
# 下载预编译版本（待发布）
# 或从源码编译
go build -o sub-store .
./sub-store -port 8888
```

打开 http://localhost:8888 使用 Web 面板

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/subscriptions | 列出所有订阅 |
| POST | /api/subscriptions | 添加订阅 {name, url} |
| PUT | /api/subscriptions/:id | 更新订阅 |
| DELETE | /api/subscriptions/:id | 删除订阅 |
| POST | /api/subscriptions/:id/refresh | 刷新订阅 |
| GET | /api/nodes | 列出所有节点 |
| GET | /api/nodes/stats | 节点统计 |
| GET | /api/sub/:id/clash | 输出 Clash 配置 |
| GET | /api/sub/:id/singbox | 输出 Sing-box 配置 |
| GET | /api/sub/all/clash | 全量 Clash 配置 |
| GET | /api/sub/all/singbox | 全量 Sing-box 配置 |
| POST | /api/doh/resolve | DOH 解析 {domain} |
| GET | /api/doh/test | 测试 DOH 连通性 |

## 订阅输出

复制订阅链接到 Clash/Sing-box 客户端：

```
Clash:    http://你的IP:8888/api/sub/订阅ID/clash
Sing-box: http://你的IP:8888/api/sub/订阅ID/singbox
全量:     http://your-ip:8888/api/sub/all/clash
```

## 技术栈

- **后端**: Go + Gin
- **前端**: 原生 HTML/CSS/JS（embed 进二进制）
- **存储**: JSON 文件
- **依赖**: gin, uuid, yaml.v3

## 内存占用

约 20-30MB，适合 1 核 1G VPS
