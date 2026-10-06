# GS Taxi — دليل البناء والرفع على iOS (Mac)

## معلومات المشروع
- اسم التطبيق: **GS Taxi**
- Bundle ID: `com.syriataxi.syriataxi`
- الإصدار الحالي في pubspec: انظر `pubspec.yaml` (مثل 1.0.9+10)
- API الإنتاج: `https://gstaxi.online/api`
- الحد الأدنى لـ iOS: **15.0**
- Firebase Android جاهز — **iOS يحتاج إعدادك**

---

## 1) ماذا تثبّت على الـ Mac؟
1. Xcode من App Store + افتحه مرة ووافق على الترخيص
2. أدوات سطر الأوامر:
   ```bash
   xcode-select --install
   ```
3. Flutter (stable):
   ```bash
   flutter doctor
   ```
4. CocoaPods:
   ```bash
   sudo gem install cocoapods
   ```
5. حساب **Apple Developer** مدفوع (99$/سنة) مربوط في Xcode → Settings → Accounts

---

## 2) فك الضغط وتشغيل المشروع
```bash
unzip syriataxi-flutter-ios-source.zip
cd syriataxi-flutter-ios-source
flutter pub get
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
```
⚠️ افتح دائمًا `Runner.xcworkspace` وليس `.xcodeproj`

---

## 3) Firebase لـ iOS (إلزامي للإشعارات)
1. ادخل [Firebase Console](https://console.firebase.google.com) → مشروع `syriataxi-f46d3` (أو نفس مشروع أندرويد)
2. Add app → **iOS**
3. Bundle ID: `com.syriataxi.syriataxi`
4. حمّل `GoogleService-Info.plist`
5. ضعه في: `ios/Runner/GoogleService-Info.plist`
6. في Xcode تأكد أنه داخل Target Runner (Copy Bundle Resources)
7. عدّل `lib/firebase_options.dart` قسم `ios` بالقيم من الملف:
   - `API_KEY` → apiKey
   - `GOOGLE_APP_ID` → appId
   - باقي الحقول موجودة مسبقًا (projectId / messagingSenderId)
8. في Apple Developer + Firebase: فعّل **APNs** (مفتاح Push أو شهادة) واربطه بـ Firebase Cloud Messaging

قالب الملف موجود: `ios_mac_guide/GoogleService-Info.plist.example`

---

## 4) التوقيع (Signing) في Xcode
1. افتح `ios/Runner.xcworkspace`
2. Runner → Signing & Capabilities
3. Team = حساب Apple Developer عندك
4. Bundle Identifier = `com.syriataxi.syriataxi`
5. أضف Capability إن لزم:
   - Push Notifications
   - Background Modes → Location updates + Remote notifications
   (غالبًا موجودة عبر Info.plist)

---

## 5) البناء للاختبار على جهاز
```bash
flutter devices
flutter run --release
```
أو من Xcode: اختر iPhone → Run

---

## 6) بناء IPA للرفع
```bash
flutter build ipa --release
```
الملف الناتج تقريبًا:
`build/ios/ipa/*.ipa`

أو من Xcode: Product → Archive → Distribute App → App Store Connect

---

## 7) الرفع على App Store Connect
1. أنشئ التطبيق في [App Store Connect](https://appstoreconnect.apple.com)
   - Name: GS Taxi
   - Bundle ID: com.syriataxi.syriataxi
2. ارفع الـ IPA عبر Xcode / Transporter
3. عبّئ المتجر:
   - وصف عربي/إنجليزي
   - لقطات شاشة iPhone
   - سياسة الخصوصية URL: `https://gstaxi.online/privacy.html`
   - فئة: Travel / Navigation
4. App Privacy (Nutrition Labels): موقع، صور/كاميرا، معرفات الجهاز للإشعارات
5. ملاحظات للمراجع (Review Notes):
   - حساب تجريبي زبون/سائق
   - لماذا الموقع Always للسائق (عداد حر / تتبع رحلة)
6. Submit for Review

---

## 8) ميزات مهمة موجودة في الكود
- حذف الحساب من داخل التطبيق (مطلوب Apple)
- شرح صلاحيات الموقع/الكاميرا/الصور في Info.plist
- Privacy Manifest: `ios/Runner/PrivacyInfo.xcprivacy`

---

## مشاكل شائعة
| المشكلة | الحل |
|---------|------|
| pod install فشل | `cd ios && pod repo update && pod install` |
| Signing error | اختر Team صحيح وفعّل Automatically manage signing |
| Firebase not configured | املأ ios في firebase_options.dart + ضع plist |
| Archive رمادي | ابنِ بـ Any iOS Device / Generic iOS Device |
