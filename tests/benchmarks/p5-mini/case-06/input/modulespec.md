---
module: notification
last_modified_req: req-2026-04-22-09
last_modified_commit: 8b3f5d1
---

# Module: 消息通知

## 字段口径

### channel
- 渠道必填
- 取值：email / sms / wechat / legacy_inapp
- 默认 email

### template_id
- 模板 ID 必填
- 关联 template 模块

### recipient
- 接收方必填
- 格式按 channel 决定（email 地址 / 手机号 / wechat openid / user_id）

### priority
- 优先级可选
- 取值：normal / urgent
- 默认 normal

## 业务规则

- urgent 优先级通知必须立即发送，不进队列
- legacy_inapp 渠道仅保留兼容老客户端，新接入禁用
- 同一 recipient 5 分钟内同模板限 1 次
