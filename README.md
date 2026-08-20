# homelab

轻量自托管栈：Ubuntu + Docker Compose + Nginx。  
**仓库是可插拔服务目录；某次部署启用哪些业务，由该机 `.env` 里的 `PROFILES` 决定。**

仓库：https://github.com/optizephyr/homelab.git

## 原则

- VPS 为主；边缘（Bark / FlareWatch / EasyTier WSS）为宕机备用，源码在各自 fork，本库只留索引
- 密钥只在服务器 `.env`，不进 Git
- 不上 GitHub Actions / Infisical；换机用 `bootstrap.sh` + 拷贝 `.env`
- 暂不做数据备份
- 不使用 Tailscale / EasyTier **客户端** 作为每机基线（中转模块仍可选）

## 每台非边缘机器：必须有的

### 宿主机基线

| 项 | 说明 |
|----|------|
| SSH | 运维入口（不依赖 Termix） |
| Docker Engine + Compose 插件 | 运行整栈 |
| `.env` + `bootstrap.sh` / `scripts/up.sh` | 换机交付 |
| 基础防火墙 | 至少放行 22；对外 Web 再放行 80/443 |

### Compose 常驻

| Profile | 规则 |
|---------|------|
| `nginx` | **每台必须**（`PROFILES` 必须包含） |
| `beszel-agent` | **仅当启用 Beszel 体系时**每台必须（`.env` 设 `ENABLE_BESZEL=true`） |

除此之外没有「每台必须」的业务服务。

## 快速开始（VPS）

```bash
# 私有库需 Deploy Key 或 PAT
git clone https://github.com/optizephyr/homelab.git /opt/homelab
cd /opt/homelab
cp .env.example .env   # 填 PROFILES、DOMAIN 等
chmod 600 .env
./bootstrap.sh
```

## Compose profiles（VPS 模块）

久未部署时，按各模块 README 查参数与核对清单（密钥仍只在服务器 `.env`）。

| Profile | 说明 | 部署备忘 |
|---------|------|----------|
| `nginx` | **每台必须** — 反代 / HTTPS 入口 | [`nginx/README.md`](nginx/README.md) |
| `beszel-agent` | 启用 Beszel 时每台必须 | [`services/beszel/README.md`](services/beszel/README.md) |
| `beszel` | Beszel hub（少数机器） | 同上 |
| `uptime-kuma` | 主监控（按需） | [`services/uptime-kuma/README.md`](services/uptime-kuma/README.md) |
| `bark` | Bark 服务端 VPS（按需） | [`services/bark-server/README.md`](services/bark-server/README.md) |
| `qinglong` | 青龙面板定时任务（按需） | [`services/qinglong/README.md`](services/qinglong/README.md) |
| `termix` | 可选 | [`services/termix/README.md`](services/termix/README.md) |
| `tailscale-derp` | 自建 DERP，仅 VPS（按需） | [`services/tailscale-derp/README.md`](services/tailscale-derp/README.md) |
| `easytier-relay` | EasyTier 中转 VPS（按需） | [`services/easytier-relay/README.md`](services/easytier-relay/README.md) |
| `radicale` | CalDAV / CardDAV（按需） | [`services/radicale/README.md`](services/radicale/README.md) |

```bash
# 由 scripts/up.sh 按 PROFILES 展开，例如：
# PROFILES=nginx,beszel-agent,uptime-kuma
./bootstrap.sh
```

## 边缘备用

见 [`edge/README.md`](edge/README.md)。完整项目请 fork 上游，勿把边缘源码放进本库。

## 子域名（Nginx）

`DOMAIN` 下按服务访问（需 DNS 指向本机且对应 profile 已启用），详见 [`nginx/README.md`](nginx/README.md)：

`uptime` / `bark` / `beszel` / `qinglong` / `termix` / `radicale` + `.${DOMAIN}`

## 开放项

- 是否使用长期小机、如何拆分服务
- Nginx ↔ 边缘域名分工（TLS / Certbot）
- 具体 fork URL（填入 `edge/*.md`）
