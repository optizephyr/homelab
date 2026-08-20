# beszel

轻量主机监控：hub（少数机器）+ agent（启用 Beszel 体系时**每台**都要跑）。

## 启用

### Hub 机

```bash
# .env
PROFILES=nginx,beszel,beszel-agent,...
ENABLE_BESZEL=true
# agent 连本机 hub 时：
BESZEL_HUB_URL=https://beszel.example.com
BESZEL_TOKEN=<在 hub UI 创建 agent 后得到>
```

### 仅 agent 的机

```bash
PROFILES=nginx,beszel-agent
ENABLE_BESZEL=true
BESZEL_HUB_URL=https://beszel.example.com
BESZEL_TOKEN=<token>
```

`ENABLE_BESZEL=true` 时，`bootstrap.sh` 会强制要求 `PROFILES` 含 `beszel-agent`。

## 关键参数

| 项 | Profile | 说明 |
|----|---------|------|
| Hub | `beszel` | Web UI；挂 `homelab` 网络，经 Nginx 反代 |
| Agent | `beszel-agent` | `network_mode: host`；读 Docker sock |

| 变量 | 用在 | 说明 |
|------|------|------|
| `ENABLE_BESZEL` | bootstrap | `true` 时校验 agent profile |
| `BESZEL_HUB_URL` | agent | Hub 公网/可达 URL |
| `BESZEL_TOKEN` | agent | Hub 签发的 agent token |

| 资源 | 说明 |
|------|------|
| 镜像 hub | `henrygd/beszel:latest` |
| 镜像 agent | `henrygd/beszel-agent:latest` |
| 容器名 | `beszel` / `beszel-agent` |
| 数据卷 | `beszel-data` → `/beszel_data`（仅 hub） |
| Agent 挂载 | `/var/run/docker.sock`（只读） |

## Nginx（仅 hub）

`beszel.${DOMAIN}` → `beszel:8090`。agent **不走** Nginx。`BESZEL_HUB_URL` 应设为 `https://beszel.${DOMAIN}`（或当前实际对外 URL）。

## 事后核对清单

1. 本机角色：只 hub、只 agent、还是两者都有  
2. `ENABLE_BESZEL` 与 `PROFILES` 是否一致  
3. `BESZEL_HUB_URL` / `BESZEL_TOKEN` 是否仍有效（换 hub 或重建卷后要重发 token）  
4. Hub 机 Nginx 与 DNS 是否仍指向该容器  
