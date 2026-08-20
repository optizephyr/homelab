# nginx

每台非边缘主机的 HTTPS / 反代入口。**`PROFILES` 必须包含 `nginx`。**

## 启用

```bash
# .env
PROFILES=nginx,...
DOMAIN=example.com
```

```bash
./bootstrap.sh
# 或
./scripts/up.sh
```

`DOMAIN` 会注入容器；`templates/*.template` 经官方镜像 `envsubst` 生成 `conf.d`。

## 子域名（`<service>.${DOMAIN}`）

仅反代挂在 `homelab` 网络上的 HTTP 服务：

| 访问 | Profile | Upstream |
|------|---------|----------|
| `uptime.${DOMAIN}` | `uptime-kuma` | `uptime-kuma:3001` |
| `bark.${DOMAIN}` | `bark` | `bark-server:8080` |
| `beszel.${DOMAIN}` | `beszel` | `beszel:8090` |
| `qinglong.${DOMAIN}` | `qinglong` | `qinglong:5700` |
| `termix.${DOMAIN}` | `termix` | `termix:8080` |
| `radicale.${DOMAIN}` | `radicale` | `radicale:5232` |

DNS 需为上述子域名（或 `*.${DOMAIN}`）指向本机。未启用的 profile 不会阻止 nginx 启动；访问对应子域名时 upstream 不可达会 502。

**不经本反代：** `beszel-agent`、`tailscale-derp`、`easytier-relay`（host 网络 / 非此 HTTP 入口）。

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `nginx` | Compose profile |
| `DOMAIN` | `.env` | 公网根域名；写入 `server_name` |
| 镜像 | `nginx:1.27-alpine` | |
| 容器名 | `homelab-nginx` | |
| 网络 | `homelab` | 与其它业务容器互通 |
| 端口 | `80`、`443` | 宿主机映射 |

## 配置文件

| 路径 | 作用 |
|------|------|
| `nginx/nginx.conf` | 主配置 |
| `nginx/templates/*.template` | 站点模板（`${DOMAIN}` 会被替换） |
| `nginx/snippets/proxy_params.conf` | 共用反代头 |

业务容器**不要**单独对外暴露端口。

启用宿主机 Certbot 时，在 `compose.yml` 取消注释类似：

```yaml
- /etc/letsencrypt:/etc/letsencrypt:ro
```

并在对应 `server` 中增加 `listen 443 ssl` 与证书路径。

## 数据

无持久化数据卷；改模板后：

```bash
docker compose --profile nginx up -d --force-recreate nginx
# 或进入容器 reload（需已生成 conf）：
docker compose --profile nginx exec nginx nginx -s reload
```

## 事后核对清单

1. `.env` 的 `PROFILES` 含 `nginx`，`DOMAIN` 正确  
2. DNS 子域名已指向本机，且本机已启用对应 profile  
3. 防火墙放行 80/443（若对外）  
4. 证书路径是否已挂进容器  
