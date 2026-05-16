## task-2026-05-14-12-T1 (close at d5b6f88)

- 新增 promo_code 字段：促销码，可选，字符串
- 新增 promo_discount_bps 字段：促销折扣（基点，整数），可选，0-10000；与 promo_code 一起出现
- 业务规则补一条：promo_code 与 yearly 8 折优惠**不叠加**，按更优的算
