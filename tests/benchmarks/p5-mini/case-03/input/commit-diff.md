## e6a0c11 order: add optional discount code

```diff
--- a/src/types/order.ts
+++ b/src/types/order.ts
@@ -3,6 +3,7 @@ export interface Order {
   customer_id: string;
   amount: number;
   status: OrderStatus;
+  discount?: string; // 折扣码，max 20 chars
 }
```

## context
- req-id: req-2026-05-14-09
- last_modified_commit before: 9f3b7c2
- last_modified_commit after: e6a0c11
