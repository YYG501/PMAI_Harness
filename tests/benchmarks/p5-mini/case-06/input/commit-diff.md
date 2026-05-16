## 3e9a26c notification: drop legacy_inapp channel

```diff
--- a/src/types/notification.ts
+++ b/src/types/notification.ts
@@ -1,5 +1,5 @@
 export interface Notification {
-  channel: 'email' | 'sms' | 'wechat' | 'legacy_inapp';
+  channel: 'email' | 'sms' | 'wechat';
   template_id: string;
   recipient: string;
   priority?: 'normal' | 'urgent';
 }
```

```diff
--- a/src/services/dispatcher.ts
+++ b/src/services/dispatcher.ts
@@ -10,9 +10,6 @@ export async function dispatch(n: Notification) {
     case 'wechat':
       return sendWechat(n);
-    case 'legacy_inapp':
-      return sendLegacyInapp(n);
     default:
       throw new Error('unknown channel');
   }
 }
```

## context
- req-id: req-2026-05-14-18
- last_modified_commit before: 8b3f5d1
- last_modified_commit after: 3e9a26c
