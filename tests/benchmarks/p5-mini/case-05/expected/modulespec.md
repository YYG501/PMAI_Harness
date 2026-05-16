---
module: user
last_modified_req: req-2026-05-14-15
last_modified_commit: f1c4b03
---

# Module: 用户管理

## 字段口径

### user_id
- 用户 ID 必填，UUID v4
- 全局唯一

### email
- 邮箱必填
- 唯一索引

### nickname
- 昵称可选
- 最长 50 字符

### role
- 角色必填
- 取值：customer / admin
- 默认 customer

## 角色权限

### customer
- 可读写自己的资料

### admin
- 可读所有用户
- 可写非 admin 用户
