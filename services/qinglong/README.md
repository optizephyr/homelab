# qinglong

青龙面板：定时任务（Python / JS / Shell / TS）。仅经 Caddy 对外。

上游：https://github.com/whyour/qinglong  
安装说明：https://qinglong.online/guide/getting-started/installation-guide/docker-compose

## 启用

```bash
# .env
PROFILES=caddy,qinglong,...
# 子路径部署时设置（须以 / 开头并以 / 结尾）；独立子域名用默认 /
# QINGLONG_BASE_URL=/
```

```bash
./scripts/up.sh
```

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `qinglong` | |
| 镜像 | `whyour/qinglong:latest` | alpine；依赖不够可改 debian 标签 |
| 容器名 | `qinglong` | |
| 网络 | `homelab` | |
| 监听 | 容器内 `5700` | 默认不映射宿主机 |
| 环境变量 | `QlBaseUrl` ← `QINGLONG_BASE_URL` | 部署路径，默认 `/` |
| 数据卷 | `qinglong-data` → `/ql/data` | 脚本、依赖、配置 |

## Caddy

`qinglong.${DOMAIN}` → `qinglong:5700`；独立子域名时保持 `QINGLONG_BASE_URL=/`。

走路径前缀时，`QINGLONG_BASE_URL` 必须与 Caddy 路由一致（例如都是 `/ql/`）。

## 事后核对清单

1. `PROFILES` 含 `qinglong`  
2. DNS / Caddy：`qinglong.${DOMAIN}`；`QINGLONG_BASE_URL` 与访问路径一致
3. 卷 `qinglong-data` 是否在本机  
4. 面板内定时任务依赖的外网 / Token / 仓库地址是否仍有效  
