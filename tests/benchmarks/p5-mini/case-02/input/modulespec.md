---
module: payment
last_modified_req: req-2026-05-09-11
last_modified_commit: 5e8a01b
---

# Module: 支付处理

## 字段口径

### total_amount
- 总金额必填
- 单位：元（小数 2 位）
- 范围：0.01 到 999999.99

### fee
- 手续费可选
- 单位：元（小数 2 位）
- 范围：0 到 9999.99

### method
- 支付方式必填
- 取值：wechat / alipay / bank_card
- 默认 wechat

## 业务规则

- 总金额 < 100 元免手续费
- 总金额 >= 100 元手续费按 0.6% 收取
- 手续费最低 1 元，最高 50 元
