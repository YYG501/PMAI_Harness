## 71d4e8b invoice: finance role cannot delete

```diff
--- a/src/auth/permissions.ts
+++ b/src/auth/permissions.ts
@@ -8,7 +8,7 @@ export const PERMS = {
   finance: {
     invoice: {
       read: 'all',
       issue: true,
       cancel: true,
-      delete: true,
+      delete: false,
     }
   },
```

## context
- req-id: req-2026-05-14-21
- last_modified_commit before: 6c83eaf
- last_modified_commit after: 71d4e8b
