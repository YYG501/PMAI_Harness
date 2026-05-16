---
module: order
last_modified_req: req-2026-04-28-05
last_modified_commit: 9f3b7c2
---

# Module: 订单管理

## 字段口径

### order_id
- 订单号必填，全局唯一
- 格式：YYYYMMDD + 6 位流水号

### customer_id
- 客户 ID 必填
- 关联 customer 模块

### amount
- 订单金额必填
- 单位：分（整数）

### status
- 订单状态必填
- 取值：pending / paid / shipped / completed / cancelled
- 默认 pending

## 角色权限

### customer
- 可读自己的订单

### admin
- 可读 / 可写所有订单
