---
module: amount
last_modified_req: req-2026-05-14-03
last_modified_commit: a7f3b21
---

# Module: 金额管理

## 字段口径

### amount
- 金额字段必填，且必须 > 0
- 单位：分（整数）
- 范围：0 到 99999999

### currency
- 币种字段必填
- 取值：CNY / USD / EUR
- 默认 CNY

## 角色权限

### admin
- 可读 / 可写 / 可审核

### operator
- 可读 / 可写
- 不能审核
