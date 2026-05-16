## f1c4b03 user: remove legacy_flag field

```diff
--- a/src/types/user.ts
+++ b/src/types/user.ts
@@ -2,6 +2,5 @@ export interface User {
   user_id: string;
   email: string;
   nickname?: string;
-  legacy_flag?: boolean;
   role: 'customer' | 'admin';
 }
```

## context
- req-id: req-2026-05-14-15
- last_modified_commit before: 1d7e2af
- last_modified_commit after: f1c4b03
