# termix

可选 Web 终端 / 运维 UI。**不是**基线；SSH 足够时可不开。

## 启用

```bash
# .env
PROFILES=caddy,termix,...
```

```bash
./scripts/up.sh
```

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `termix` | |
| 镜像 | `ghcr.io/lukegus/termix:latest` | 官方文档；Docker Hub 镜像为 `bugattiguy527/termix:latest` |
| 容器名 | `termix` | |
| 网络 | `homelab` | |
| 数据卷 | `data/termix` → `/app/data` | |

容器内 `PORT=8080`；Caddy：`terminal.${CADDY_DOMAIN}` → `termix:8080`。

## 事后核对清单

1. `PROFILES` 是否含 `termix`
2. DNS / Caddy：`terminal.${CADDY_DOMAIN}` → `termix:8080`
