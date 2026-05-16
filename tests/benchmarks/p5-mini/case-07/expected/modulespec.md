---
module: invoice
last_modified_req: req-2026-05-14-21
last_modified_commit: 71d4e8b
---

# Module: 发票管理

## 字段口径

### invoice_id
- 发票 ID 必填
- 格式：INV-YYYYMMDD-NNNNNN

### order_id
- 关联订单 ID 必填

### amount
- 发票金额必填
- 单位：分（整数）

### status
- 状态必填
- 取值：draft / issued / cancelled
- 默认 draft

## 角色权限

### customer
- 可读自己的发票
- 可申请开票

### finance
- 可读所有发票
- 可开票 / 作废

### admin
- 全部权限
- 可读 / 可写 / 可作废 / 可删除
