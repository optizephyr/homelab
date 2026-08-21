# mailhub

定时拉取 QQ 邮箱，筛选重要邮件，并分发到 CalDAV 日历 / 待办和 Bark。

上游：https://github.com/optizephyr/mailhub

## 启用

```bash
# .env
PROFILES=caddy,mailhub,radicale

MAILHUB_IMAGE=registry.cn-hangzhou.aliyuncs.com/<namespace>/mailhub:<tag>
MAILHUB_QQ_EMAIL=example@qq.com
MAILHUB_QQ_AUTH_CODE=QQ邮箱授权码

# 同机服务可直接使用容器地址；也可填写外部 HTTPS 地址
MAILHUB_CALDAV_URL=http://radicale:5232
MAILHUB_CALDAV_USERNAME=mailhub
MAILHUB_CALDAV_PASSWORD=change-me
# 创建 config.yaml 指定的日历和任务列表后再设为 true
MAILHUB_CALDAV_SETUP_CONFIRMED=true

# 可选：两项都填才启用
# MAILHUB_BARK_SERVER_URL=http://bark-server:8080
# MAILHUB_BARK_KEY=
```

先在 Radicale 创建与 `config.yaml` 中名称完全相同的日历和任务列表。私有 ACR 先在宿主机 `docker login`，再启动（不要在这台机器上从 GitHub 构建）：

```bash
./scripts/up.sh
```

`mailhub` 没有 Web 入口，不需要 Caddy 子域名；加入 `homelab` 网络只是为了访问同机的 Radicale 和 Bark。

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `mailhub` | |
| 镜像 | `MAILHUB_IMAGE` | 阿里云预构建镜像；必填 |
| 调度间隔 | `MAILHUB_INTERVAL_SECONDS` | 默认 900 秒 |
| 时区 | `MAILHUB_TZ` | 默认 `Asia/Shanghai` |
| 行为配置 | `config.yaml` → `/app/config.yaml` | 扫描范围、collection 名、模型名 |
| 数据卷 | `mailhub-data` → `/app/data` | 游标、幂等状态与 JSONL 日志 |

`MAILHUB_IMAGE`、QQ 邮箱地址和授权码是必填项，`bootstrap.sh` 会在启动前检查。CalDAV、LLM 和 Bark 均需填写完整参数组；只填一部分会被拒绝。

## 首次核对

先用一次性命令确认 collection 名称并干跑：

```bash
docker compose --profile mailhub run --rm mailhub mailhub list-calendars
docker compose --profile mailhub run --rm mailhub mailhub list-reminders
docker compose --profile mailhub run --rm mailhub mailhub sync --dry-run
```

确认输出后在 `.env` 设置 `MAILHUB_DRY_RUN_CONFIRMED=true`，再执行
`./scripts/up.sh` 启动常驻容器。脚本会先启动 Radicale / Bark 等核心服务，
缺少上述人工确认时暂停，不会提前启动 Mailhub。不要让另一台机器使用相同
`source_id` 和邮箱同时写入。

查看运行状态与日志：

```bash
docker compose --profile mailhub logs -f mailhub
docker compose --profile mailhub exec mailhub \
  sh -c 'tail -n 20 /app/data/logs/mail_lifecycle.jsonl'
```

更新镜像：改 `.env` 里的 `MAILHUB_IMAGE` 标签（或保持 `latest`），再拉一次：

```bash
./scripts/up.sh --pull always
```

## 事后核对清单

1. `PROFILES` 含 `mailhub`，且 `MAILHUB_IMAGE` 已指向阿里云镜像
2. QQ 邮箱已开启 IMAP/SMTP，填写的是授权码而不是登录密码
3. CalDAV 日历 / 任务列表显示名称与 `config.yaml` 完全一致
4. `mailhub-data` 卷只由一个 Mailhub 实例使用
5. 首次正式同步前已执行 `sync --dry-run`
6. `.env` 中相应的 `MAILHUB_CALDAV_SETUP_CONFIRMED` /
   `MAILHUB_DRY_RUN_CONFIRMED` 已设为 `true`
