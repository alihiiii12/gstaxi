# قائمة تحقق — قبل إرسال / بناء / رفع App Store

## تم إنجازه من المشروع/السيرفر
- [x] سياسة الخصوصية: https://gstaxi.online/privacy.html (200)
- [x] حذف الحساب: `DELETE /api/account` مفعّل على السيرفر
- [x] Info.plist: موقع + خلفية + إشعارات + كاميرا + iPad full screen
- [x] PrivacyInfo.xcprivacy موجود في Runner
- [x] رد 4.3(a) + ملاحظات المراجعة محدّثة (بناء 22)
- [x] رابط الخصوصية داخل التطبيق → privacy.html

## على جهاز الـ Mac (أنت)
- [ ] Xcode مثبت ومفتوح مرة واحدة
- [ ] `flutter doctor` بدون أخطاء iOS
- [ ] CocoaPods يعمل (`pod --version`)
- [ ] حساب Apple Developer مضاف في Xcode

## المشروع على الـ Mac
- [ ] `flutter pub get` نجح
- [ ] `cd ios && pod install` نجح
- [ ] فتح `Runner.xcworkspace`
- [ ] Signing: Team محدد + Bundle ID = com.syriataxi.syriataxi

## Firebase iOS (الناقص الوحيد في الكود)
- [ ] Firebase Console → Add app → iOS → Bundle ID `com.syriataxi.syriataxi`
- [ ] ضع `GoogleService-Info.plist` في `ios/Runner/`
- [ ] انسخ `API_KEY` و`GOOGLE_APP_ID` إلى `lib/firebase_options.dart` (قسم ios)
- [ ] Apple Developer → APNs Key → ارفعه في Firebase Cloud Messaging
- [ ] أعد البناء

## قبل الرفع
- [ ] تجربة على iPhone (موقع + دخول + طلب)
- [ ] `flutter build ipa --release` (الإصدار `1.0.16+22`)
- [ ] لقطات شاشة حديثة في App Store Connect
- [x] رابط سياسة الخصوصية في Connect: https://gstaxi.online/privacy.html
- [x] حسابات تجريبية موجودة
- [ ] الصق رد 4.3 من `APP_STORE_4_3_RESPONSE_AR.md`

## بعد الرفع
- [ ] TestFlight
- [ ] Submit for Review
