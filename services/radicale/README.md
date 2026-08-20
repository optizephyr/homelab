# radicale

CalDAV（日历 / 待办）与 CardDAV（通讯录）服务端。仅经 Nginx 对外。

上游：https://radicale.org/master.html  
镜像：https://github.com/Kozea/Radicale（`ghcr.io/kozea/radicale:stable`）

默认认证为 htpasswd；**3.5.0 起未配置则拒绝所有登录**。账号文件不进 Git。

## 启用

```bash
# .env
PROFILES=nginx,radicale,...
DOMAIN=example.com
```

首次启动前在本机生成 `services/radicale/config/users`（`bootstrap.sh` 在缺文件时会 `touch`，但仍需写入哈希）：

```bash
# bcrypt（推荐）。把 USER / PASS 换成自己的。
docker run --rm httpd:2-alpine htpasswd -Bbn USER PASS \
  > services/radicale/config/users
chmod 600 services/radicale/config/users
```

追加用户时去掉 `-c` 语义（上面是重定向覆盖）；追加：

```bash
docker run --rm httpd:2-alpine htpasswd -Bbn USER2 PASS2 \
  >> services/radicale/config/users
```

然后：

```bash
./scripts/up.sh
```

改 `users` 后一般不必重建容器；Radicale 会按文件 mtime 重读（`autodetect`）。

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `radicale` | |
| 镜像 | `ghcr.io/kozea/radicale:stable` | 官方稳定标签 |
| 容器名 | `radicale` | Nginx `proxy_pass` 用此名 |
| 网络 | `homelab` | |
| 监听 | 容器内 `5232` | 默认不映射宿主机 |
| 配置 | `config/config` → `/etc/radicale/config` | 已进 Git |
| 账号 | `config/users` → `/etc/radicale/users` | **不进 Git** |
| 数据卷 | `radicale-data` → `/var/lib/radicale` | 日历与通讯录 |

本模块**无**额外 `.env` 变量；用户名密码只在服务器上的 `users` 文件。

## Nginx

`radicale.${DOMAIN}` → `radicale:5232`。挂在子域名根路径，**不要**设 `X-Script-Name`。

`client_max_body_size` 提到 100m，与 Radicale `max_content_length` 对齐（通讯录大头像）。`/.well-known/caldav` 与 `carddav` 重定向到 `/`，方便 Apple 客户端发现。

客户端（DAVx⁵、Thunderbird、Apple 日历等）填写：

- 服务器：`https://radicale.${DOMAIN}`
- 用户名 / 密码：`users` 里的条目

部分客户端要填集合 URL：`https://radicale.${DOMAIN}/USERNAME/`。可先用 Web UI 建日历 / 通讯录。

macOS 日历在明文 HTTP 上可能不带账号；对外应走 HTTPS。

## 事后核对清单

1. `PROFILES` 含 `radicale`  
2. `services/radicale/config/users` 已有 bcrypt/htpasswd 行，权限不要对其他人可读  
3. DNS / Nginx：`radicale.${DOMAIN}` → `radicale:5232`  
4. 卷 `radicale-data` 是否在本机（换机需迁卷）  
5. 客户端用 HTTPS 与正确用户名（路径 `/USERNAME/`）  
