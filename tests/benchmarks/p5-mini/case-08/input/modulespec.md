---
module: tenant
last_modified_req: req-2026-04-25-04
last_modified_commit: a09b21d
---

# Module: 租户管理

## 字段口径

### tenant_id
- 租户 ID 必填，UUID v4

### name
- 租户名称必填
- 最长 100 字符

### type
- 租户类型必填
- 取值：personal / business
- 默认 personal

### plan
- 套餐必填
- 取值：basic / pro / enterprise
- 默认 basic

## 角色权限

### customer
- 可读自己所在租户的资料
- 可写自己的 profile
- 可邀请新成员

### admin
- 可读 / 可写所有租户
- 可创建 / 删除租户
- 可强制重置租户密码
