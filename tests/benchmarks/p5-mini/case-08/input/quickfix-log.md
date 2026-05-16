## task-2026-05-14-24-T1 (close at 53fa7e0)

- 把 customer 角色拆成 customer_individual 与 customer_business 两个独立角色
- customer_individual 继承原 customer 全部权限
- customer_business 在 customer_individual 基础上加："可读所在租户的所有成员列表"、"可调整成员角色（限本租户内的非 admin）"
- 原"customer"角色保留为别名，文档中标注弃用，下次大版本删除
