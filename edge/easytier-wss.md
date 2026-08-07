# EasyTier WSS 边缘备用

第三方 **Cloudflare Workers + Durable Objects** WebSocket 中继，不是官方 easytier-core 原样上边缘。

## 候选上游（部署时选一并 fork）

- https://github.com/fordes123/easytier-edge  
- https://github.com/Kaiyuan/EasyTier-wss-cf  
- https://github.com/IceSoulHanxi/easytier-ws-relay  

## 本环境（自行填写）

- 选用上游：
- Fork URL：
- `wss://` 地址：

## 与 VPS

- VPS 模块：Compose profile `easytier-relay`
- 边缘：本 fork（中转备用）
- Tailscale DERP **无**边缘版，仅 VPS profile `tailscale-derp`
