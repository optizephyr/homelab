# caddy

每台非边缘主机的 HTTPS / 反代入口。`PROFILES` 必须包含 `caddy`。

## 启用

```bash
# .env
PROFILES=caddy,...
DOMAIN=example.com
```

启动前，将以下子域名（或 `*.${DOMAIN}`）解析到本机，并放行 TCP 80/443 与 UDP 443：

- `uptime.${DOMAIN}`
- `bark.${DOMAIN}`
- `monitor.${DOMAIN}`
- `qinglong.${DOMAIN}`
- `terminal.${DOMAIN}`
- `caldav.${DOMAIN}`

```bash
./bootstrap.sh
```

Caddy 自动通过 ACME 申请并续期公开信任的证书，HTTP 自动跳转 HTTPS。证书与账户状态保存在 `caddy-data` 卷；不要删除该卷。未启用的业务 profile 不影响 Caddy 启动，但访问对应域名会返回 502。

## 路由

| 访问地址 | Profile | Upstream |
|----------|---------|----------|
| `https://uptime.${DOMAIN}` | `uptime-kuma` | `uptime-kuma:3001` |
| `https://bark.${DOMAIN}` | `bark` | `bark-server:8080` |
| `https://monitor.${DOMAIN}` | `beszel` | `beszel:8090` |
| `https://qinglong.${DOMAIN}` | `qinglong` | `qinglong:5700` |
| `https://terminal.${DOMAIN}` | `termix` | `termix:8080` |
| `https://caldav.${DOMAIN}` | `radicale` | `radicale:5232` |

`beszel-agent`、`tailscale-derp` 与 `easytier-relay` 不经过 Caddy。

## 运维

```bash
# 校验配置
docker compose --profile caddy exec caddy caddy validate --config /etc/caddy/Caddyfile

# 修改 Caddyfile 后平滑加载
docker compose --profile caddy exec caddy caddy reload --config /etc/caddy/Caddyfile

# 查看证书申请与代理日志
docker compose --profile caddy logs caddy
```

首次签发要求域名已经解析到本机，且公网可访问 80 或 443。若使用 Cloudflare 代理，SSL/TLS 模式应设为 `Full (strict)`。

## 从 Nginx 迁移

旧部署升级后，先把服务器 `.env` 中的 `nginx` profile 改为 `caddy`。旧容器仍会占用 80/443，需要在首次启动 Caddy 前移除：

```bash
docker rm -f homelab-nginx
./bootstrap.sh
```

业务数据卷不受入口容器替换影响。
