# termix

可选 Web 终端 / 运维 UI。**不是**基线；SSH 足够时可不开。

## 启用

```bash
# .env — 必须换成实际上游镜像，占位镜像不能用
TERMIX_IMAGE=public.ecr.aws/termix/termix:<真实标签>
PROFILES=caddy,termix,...
```

```bash
./scripts/up.sh
```

## 关键参数

| 项 | 来源 | 说明 |
|----|------|------|
| Profile | `termix` | |
| 镜像 | `TERMIX_IMAGE` | 默认是 `...:placeholder`，部署前必改 |
| 容器名 | `termix` | |
| 网络 | `homelab` | |

容器内 `PORT=8080`；Caddy：`terminal.${CADDY_DOMAIN}` → `termix:8080`。
当前 compose **未**挂数据卷、**未**映射宿主机端口；首次启用前按上游文档补持久化目录（若需要）。

## 事后核对清单

1. `.env` 里 `TERMIX_IMAGE` 是否仍是可用标签（非 placeholder）  
2. `PROFILES` 是否含 `termix`  
3. DNS / Caddy：`terminal.${CADDY_DOMAIN}` → `termix:8080`
4. 若曾改过 compose（卷、端口），以本机实际 `compose.yml` 为准并回写本 README  
