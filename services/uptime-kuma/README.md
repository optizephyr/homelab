# uptime-kuma

主站监控面板。仅经 Nginx 对外；容器不映射宿主机端口。

## 启用

```bash
# .env
PROFILES=nginx,uptime-kuma,...
DOMAIN=example.com
```

```bash
./scripts/up.sh
```

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `uptime-kuma` | |
| 镜像 | `louislam/uptime-kuma:1` | |
| 容器名 | `uptime-kuma` | Nginx `proxy_pass` 用此名 |
| 网络 | `homelab` | |
| 监听 | 容器内 `3001` | 默认不映射到宿主机 |
| 数据卷 | `uptime-kuma-data` → `/app/data` | 监控配置与历史 |

本模块**无**额外 `.env` 变量；账号密码在首次打开 Web UI 时设置（存在数据卷里）。

## Nginx

`uptime.${DOMAIN}` → `uptime-kuma:3001`（WebSocket 头已在共用 snippet 中）。

## 事后核对清单

1. `PROFILES` 含 `uptime-kuma`  
2. DNS / Nginx：`uptime.${DOMAIN}` → `uptime-kuma:3001`  
3. 卷 `uptime-kuma-data` 是否在本机（换机需迁移卷或接受重装）  
4. 告警 webhook 是否仍指向当前 Bark / 边缘地址  
