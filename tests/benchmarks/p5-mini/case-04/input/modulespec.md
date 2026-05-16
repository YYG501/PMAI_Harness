---
module: subscription
last_modified_req: req-2026-04-30-08
last_modified_commit: 4a17d09
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

## 业务规则

- yearly 周期享受 8 折优惠
- enterprise 套餐需销售审核后才能开通
- 升级套餐立即生效，降级套餐在下一周期生效
