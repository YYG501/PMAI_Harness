---
module: subscription
last_modified_req: req-2026-05-14-12
last_modified_commit: d5b6f88
---

# Module: 订阅管理

## 字段口径

### plan
- 套餐必填
- 取值：basic / pro / enterprise
- 默认 basic

### period
- 计费周期必填
- 取值：monthly / yearly
- 默认 monthly

### price
- 套餐价格必填
- 单位：分（整数）
- 根据 plan + period 自动计算

### promo_code
- 促销码可选
- 字符串

### promo_discount_bps
- 促销折扣可选（基点，整数）
- 范围：0 到 10000
- 与 promo_code 一起出现

## 业务规则

- yearly 周期享受 8 折优惠
- enterprise 套餐需销售审核后才能开通
- 升级套餐立即生效，降级套餐在下一周期生效
- promo_code 与 yearly 8 折优惠不叠加，按更优的算
