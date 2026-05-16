## b2c9d44 payment: switch total_amount to integer cents

```diff
--- a/src/types/payment.ts
+++ b/src/types/payment.ts
@@ -1,6 +1,6 @@
 export interface Payment {
-  total_amount: number; // yuan, 2 decimals
+  total_amount: number; // cents, integer
   fee?: number;
   method: 'wechat' | 'alipay' | 'bank_card';
 }
```

```diff
--- a/src/services/feeCalculator.ts
+++ b/src/services/feeCalculator.ts
@@ -2,9 +2,9 @@ export function calculateFee(totalAmount: number): number {
-  if (totalAmount < 100) return 0;
-  const fee = totalAmount * 0.006;
-  return Math.max(1, Math.min(50, fee));
+  if (totalAmount < 10000) return 0;
+  const fee = Math.round(totalAmount * 0.006);
+  return Math.max(100, Math.min(5000, fee));
 }
```

## context
- req-id: req-2026-05-14-07
- last_modified_commit before: 5e8a01b
- last_modified_commit after: b2c9d44
