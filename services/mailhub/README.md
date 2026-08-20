# mailhub

定时拉取 QQ 邮箱，筛选重要邮件，并分发到 CalDAV 日历 / 待办和 Bark。

上游：https://github.com/optizephyr/mailhub

## 启用

```bash
# .env
PROFILES=caddy,mailhub,radicale

MAILHUB_QQ_EMAIL=example@qq.com
MAILHUB_QQ_AUTH_CODE=QQ邮箱授权码

# 同机服务可直接使用容器地址；也可填写外部 HTTPS 地址
MAILHUB_CALDAV_URL=http://radicale:5232
MAILHUB_CALDAV_USERNAME=mailhub
MAILHUB_CALDAV_PASSWORD=change-me

# 可选：两项都填才启用
# MAILHUB_BARK_SERVER_URL=http://bark-server:8080
# MAILHUB_BARK_KEY=
```

先在 Radicale 创建与 `config.yaml` 中名称完全相同的日历和任务列表，再启动：

```bash
./scripts/up.sh --build
```

`mailhub` 没有 Web 入口，不需要 Caddy 子域名；加入 `homelab` 网络只是为了访问同机的 Radicale 和 Bark。

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `mailhub` | |
| 源码 | `optizephyr/mailhub` 的 `master` 分支 | 本地构建，无上游预构建镜像 |
| 调度间隔 | `MAILHUB_INTERVAL_SECONDS` | 默认 900 秒 |
| 时区 | `MAILHUB_TZ` | 默认 `Asia/Shanghai` |
| 行为配置 | `config.yaml` → `/app/config.yaml` | 扫描范围、collection 名、模型名 |
| 数据卷 | `mailhub-data` → `/app/data` | 游标、幂等状态与 JSONL 日志 |

QQ 邮箱地址和授权码是必填项，`bootstrap.sh` 会在启动前检查。CalDAV、LLM 和 Bark 均需填写完整参数组；只填一部分会被拒绝。

## 首次核对

先用一次性命令确认 collection 名称并干跑：

```bash
docker compose --profile mailhub run --rm mailhub mailhub list-calendars
docker compose --profile mailhub run --rm mailhub mailhub list-reminders
docker compose --profile mailhub run --rm mailhub mailhub sync --dry-run
```

确认输出后再由常驻容器每 15 分钟同步。不要让另一台机器使用相同 `source_id` 和邮箱同时写入。

查看运行状态与日志：

```bash
docker compose --profile mailhub logs -f mailhub
docker compose --profile mailhub exec mailhub \
  sh -c 'tail -n 20 /app/data/logs/mail_lifecycle.jsonl'
```

更新上游代码后重新构建：

```bash
./scripts/up.sh --build
```

## 事后核对清单

1. `PROFILES` 含 `mailhub`
2. QQ 邮箱已开启 IMAP/SMTP，填写的是授权码而不是登录密码
3. CalDAV 日历 / 任务列表显示名称与 `config.yaml` 完全一致
4. `mailhub-data` 卷只由一个 Mailhub 实例使用
5. 首次正式同步前已执行 `sync --dry-run`
