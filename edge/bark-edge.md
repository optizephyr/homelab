# Bark 边缘备用

官方文档已列出边缘实现（个人低频推送场景）。

## 候选上游（部署时选一并 fork）

- Cloudflare：https://github.com/cwxiaos/bark-worker  
- CF + EdgeOne + ESA：https://github.com/sylingd/bark-worker-server  
- EdgeOne：https://github.com/AkinoKaede/bark-edgeone  

国内访问优先考虑 **EdgeOne** 路径；EdgeOne 常需 APNs 反代（见上游 wiki）。

## 本环境（自行填写）

- 选用上游：
- Fork URL：
- 部署域名：
- Bark App 填写的服务器地址：

## 与 VPS

- VPS 模块：Compose profile `bark`
- 边缘：本 fork（建议常开，供 FlareWatch / 宕机告警使用）
