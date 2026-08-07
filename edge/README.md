# 边缘备用（索引）

边缘项目**不要**把完整上游源码放进本仓库。  
各自 **fork 上游** 后，用 Cloudflare / EdgeOne 部署；这里只记录约定与链接。

## 定位

- VPS 为主路径
- 边缘为 **VPS 宕机备用**
- 监控备用建议 **热备**（一直跑），否则发现不了主机挂了
- 告警建议打到 **bark-edge**，不依赖短命 VPS

## 模块

| 文档 | 用途 | 上游（示例） |
|------|------|----------------|
| [flarewatch.md](flarewatch.md) | 边缘监控热备 | https://github.com/saminnet/flarewatch |
| [bark-edge.md](bark-edge.md) | 边缘 Bark | 见该文档（EdgeOne / CF） |
| [easytier-wss.md](easytier-wss.md) | EasyTier WSS 中继备用 | 见该文档 |

把你的 fork URL、部署域名填进各 md 的「本环境」小节。

## 开放

- 长期小机是否拆分
- 子域名与 DNS 具体划分
