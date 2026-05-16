## 53fa7e0 tenant: split customer role into individual / business

```diff
--- a/src/auth/roles.ts
+++ b/src/auth/roles.ts
@@ -1,6 +1,8 @@
 export const ROLES = [
-  'customer',
+  'customer_individual',
+  'customer_business',
   'admin',
+  'customer', // deprecated alias, removed next major
 ] as const;
```

```diff
--- a/src/auth/permissions.ts
+++ b/src/auth/permissions.ts
@@ -20,6 +20,15 @@ export const PERMS = {
   customer: {
     tenant: { read: 'self', write_profile: true, invite: true }
   },
+  customer_individual: {
+    tenant: { read: 'self', write_profile: true, invite: true }
+  },
+  customer_business: {
+    tenant: {
+      read: 'self', write_profile: true, invite: true,
+      list_members: true, change_member_role: 'non_admin_within_tenant',
+    }
+  },
```

## context
- req-id: req-2026-05-14-24
- last_modified_commit before: a09b21d
- last_modified_commit after: 53fa7e0
