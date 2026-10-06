# Firebase iOS — خطوات سريعة (الناقص الوحيد للكود)

مشروع Firebase (أندرويد جاهز): **syriataxi-f46d3**  
Bundle ID: **com.syriataxi.syriataxi**  
Sender ID: **758178660470**  
Storage: **syriataxi-f46d3.firebasestorage.app**

## ماذا تفعل أنت (5 دقائق)
1. افتح [Firebase Console](https://console.firebase.google.com/) → مشروع `syriataxi-f46d3`
2. Project settings → **Add app** → **iOS**
3. Bundle ID: `com.syriataxi.syriataxi` → Register
4. Download **GoogleService-Info.plist**
5. ضع الملف في: `ios/Runner/GoogleService-Info.plist`
6. من الملف انسخ إلى `lib/firebase_options.dart` قسم `ios`:
   - `API_KEY` → `apiKey`
   - `GOOGLE_APP_ID` → `appId`
7. Apple Developer → Keys → إنشاء **APNs Key** → Firebase → Cloud Messaging → Upload
8. على الـ Mac:
   ```bash
   flutter clean && flutter pub get && cd ios && pod install && cd .. && flutter build ipa --release
   ```

## بعد لصق القيم
أرسل لي محتوى `GoogleService-Info.plist` (أو القيم فقط) لأعبّئ `firebase_options.dart` تلقائياً إن رغبت.

## ملاحظة
بدون هذه الخطوة يعمل التطبيق على iOS **بدون إشعارات دفع** (لا ينهار)، والاستطلاع الاحتياطي يكفي للرحلات.
