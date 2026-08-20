# easytier-relay

EasyTier 中转 / 公网节点（VPS）。边缘 WSS 备用见 [`edge/easytier-wss.md`](../../edge/easytier-wss.md)。

生产前对照当前 EasyTier 文档核对启动参数；compose 里的 `command` 默认注释掉了。

## 启用

```bash
# .env
PROFILES=caddy,easytier-relay,...
EASYTIER_NETWORK_NAME=<网络名>
EASYTIER_NETWORK_SECRET=<密钥>
```

如需显式传参，在 `compose.yml` 取消注释并改成实际 flags，例如：

```yaml
command:
  - -d
  - --network-name
  - ${EASYTIER_NETWORK_NAME}
  - --network-secret
  - ${EASYTIER_NETWORK_SECRET}
```

```bash
./scripts/up.sh
```

## 关键参数

| 变量 | 说明 |
|------|------|
| `EASYTIER_NETWORK_NAME` | EasyTier 虚拟网络名 |
| `EASYTIER_NETWORK_SECRET` | 网络密钥 |

| 资源 | 说明 |
|------|------|
| Profile | `easytier-relay` |
| 镜像 | `easytier/easytier:latest` |
| 容器名 | `easytier-relay` |
| 网络 | host（不进 `homelab`） |
| 数据卷 | `easytier-data` → `/var/lib/easytier` |

## 事后核对清单

1. `.env` 中网络名 / 密钥是否仍是各端实际使用的那套  
2. `command` 是否已按当时文档启用（仅环境变量可能不够）  
3. 防火墙放行的中转端口是否与 EasyTier 配置一致  
4. 客户端 / 边缘 WSS 备用是否仍指向本节点  
