# bark-server

Bark iOS 推送服务端（VPS 侧）。边缘备用见 [`edge/bark-edge.md`](../../edge/bark-edge.md)。

## 启用

```bash
# .env
PROFILES=caddy,bark,...
# 可选文档字段（边缘 URL，不进 compose）
# BARK_EDGE_URL=https://bark.example.com
```

```bash
./scripts/up.sh
```

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `bark` | 注意：目录是 `bark-server`，profile 名是 `bark` |
| 镜像 | `finab/bark-server:latest` | |
| 容器名 | `bark-server` | |
| 网络 | `homelab` | |
| 数据卷 | `bark-data` → `/data` | device key 等 |

当前 compose **未**声明额外环境变量；设备注册与推送密钥以面板 / 上游文档为准。

## Caddy

`bark.${DOMAIN}` → `bark-server:8080`（见 `caddy/Caddyfile`）。确认端口：

```bash
docker compose --profile bark exec bark-server sh -c 'ss -lntp || netstat -lntp'
```

## 事后核对清单

1. `PROFILES` 含 `bark`（不是 `bark-server`）  
2. DNS / Caddy：`bark.${DOMAIN}` → `bark-server:8080`
3. 手机 Bark App 的 Server URL 指向 `https://bark.${DOMAIN}`  
4. Uptime Kuma / 其它告警的 webhook 是否仍用本地址或 `BARK_EDGE_URL`  
