# Firebase FCM — Syria Taxi

## Flutter (أندرويد)

- `android/app/google-services.json` — من Firebase Console
- `lib/firebase_options.dart` — قيم المشروع `syriataxi-f46d3`
- Gradle: plugin `com.google.gms.google-services`

بعد التحديث: `flutter clean` ثم `flutter run`.

## Laravel (إرسال من الخادم)

1. ضع ملف حساب الخدمة في:
   `storage/firebase/service-account.json`
2. في `.env`:
   ```
   FIREBASE_PROJECT_ID=syriataxi-f46d3
   ```
3. الخدمة: `App\Services\FcmPushService`
4. التطبيق يسجّل الرمز: `POST /api/user/fcm-token` (بعد تسجيل الدخول)

**لا ترفع ملف service-account إلى Git** (مضاف في `.gitignore`).
