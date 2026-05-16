## d5b6f88 subscription: add promo code support

```diff
--- a/src/types/subscription.ts
+++ b/src/types/subscription.ts
@@ -3,6 +3,8 @@ export interface Subscription {
   period: 'monthly' | 'yearly';
   price: number;
+  promo_code?: string;
+  promo_discount_bps?: number; // 0-10000
 }
```

```diff
--- a/src/services/priceCalculator.ts
+++ b/src/services/priceCalculator.ts
@@ -10,7 +10,11 @@ export function calculatePrice(plan, period, promoBps) {
   const base = BASE_PRICE[plan];
   const yearlyMultiplier = period === 'yearly' ? 0.8 : 1.0;
-  return base * yearlyMultiplier;
+  const promoMultiplier = promoBps ? (10000 - promoBps) / 10000 : 1.0;
+  // promo and yearly do not stack — take the better one
+  return base * Math.min(yearlyMultiplier, promoMultiplier);
 }
```

## context
- req-id: req-2026-05-14-12
- last_modified_commit before: 4a17d09
- last_modified_commit after: d5b6f88
