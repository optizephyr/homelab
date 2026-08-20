# tailscale-derp

自建 Tailscale DERP（仅 VPS；不能跑在 Workers / 边缘函数上）。  
`network_mode: host`；证书与 STUN 按上游文档配置。

文档：https://tailscale.com/docs/reference/derp-servers/custom-derp-servers

## 启用

```bash
# .env
PROFILES=nginx,tailscale-derp,...   # nginx 仍是基线；DERP 本身用 host 网络
DERP_DOMAIN=derp.example.com
DERP_VERIFY_CLIENTS=false
# 可选换镜像
# DERPER_IMAGE=ghcr.io/fredliang44/derper:latest
```

```bash
./scripts/up.sh
```

## 关键参数

| 变量 | 默认 | 说明 |
|------|------|------|
| `DERP_DOMAIN` | 空 | DERP 对外域名（证书 / 客户端配置） |
| `DERP_VERIFY_CLIENTS` | `false` | 是否校验 Tailscale 客户端 |
| `DERPER_IMAGE` | `ghcr.io/fredliang44/derper:latest` | derper 镜像 |

| 资源 | 说明 |
|------|------|
| Profile | `tailscale-derp` |
| 容器名 | `tailscale-derp` |
| 网络 | host（不进 `homelab`） |
| 卷 | `derper-certs` → `/app/certs`；`derper-data` → `/var/lib/derper` |

## 防火墙 / Tailscale

按 derper 文档放行 HTTP(S) 与 STUN/UDP 端口；在 Tailscale ACL / DERP map 里登记 `DERP_DOMAIN`。

Nginx 基线可并存，但 **DERP 流量通常不经过** `homelab-nginx`（host 网络直出）。

## 事后核对清单

1. `DERP_DOMAIN`、DNS、证书是否仍匹配  
2. `DERP_VERIFY_CLIENTS` 与当时安全策略是否一致  
3. Tailscale 控制台 / 自建 DERP map 是否仍指向本机  
4. 宿主机防火墙 UDP/TCP 是否仍开放  
