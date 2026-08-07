# FlareWatch（uptime-edge）

选定方案：用 **FlareWatch** 作为边缘监控备用（非 Uptime Kuma）。

## 做法

1. Fork：https://github.com/saminnet/flarewatch  
2. 在 fork 里配置 monitors / webhook（告警指向 bark-edge）  
3. 按上游文档部署到 Cloudflare Workers  

本库不存放 FlareWatch 源码。

## 本环境（自行填写）

- Fork URL：
- 部署域名 / Worker URL：
- Webhook → Bark：
- 建议热备探测目标（示例）：主站 HTTPS、关键入口  

## 与 VPS

- 主监控：Compose profile `uptime-kuma`
- 备用：本 FlareWatch（常开热备）
