---
module: order
last_modified_req: req-2026-05-14-09
last_modified_commit: e6a0c11
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

### discount
- 折扣码可选
- 字符串，最长 20 字符
- 用于结算时减免

## 角色权限

### customer
- 可读自己的订单

### admin
- 可读 / 可写所有订单
