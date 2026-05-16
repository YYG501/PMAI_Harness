## a7f3b21 amount: enforce positive value

```diff
--- a/src/validators/amount.ts
+++ b/src/validators/amount.ts
@@ -3,7 +3,7 @@ export function validateAmount(value: number) {
   if (value === undefined || value === null) {
     throw new Error("amount required");
   }
-  if (value < 0) {
+  if (value <= 0) {
     throw new Error("amount must be > 0");
   }
 }
```

## context
- req-id: req-2026-05-14-03
- last_modified_commit before: 2c4d18a
- last_modified_commit after: a7f3b21
