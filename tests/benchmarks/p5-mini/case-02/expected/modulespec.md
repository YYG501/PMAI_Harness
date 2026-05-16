---
module: payment
last_modified_req: req-2026-05-14-07
last_modified_commit: b2c9d44
---

# Module: 支付处理

## 字段口径

### total_amount
- 总金额必填
- 单位：分（整数）
- 范围：1 到 99999999

### fee
- 手续费可选
- 单位：元（小数 2 位）
- 范围：0 到 9999.99

### method
- 支付方式必填
- 取值：wechat / alipay / bank_card
- 默认 wechat

## 业务规则

- 总金额 < 10000 免手续费
- 总金额 >= 10000 手续费按 0.6% 收取
- 手续费最低 100，最高 5000
