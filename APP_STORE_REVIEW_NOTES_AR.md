# ملاحظات مراجعة App Store — انسخها إلى App Review Information

## حسابات تجريبية
استخدم الحسابات التجريبية الجاهزة لديكم (زبون + سائق باشتراك نشط).

## ملاحظات للمراجع
1. Build 22 addresses Guideline 4.3(a): differentiated booking UI (من/إلى, الآن/لاحقاً), GS slate/gold branding, blue map route (not purple template), custom destination pin. See Resolution Center reply.
2. Login crash on iPad fixed: deferred map/GPS after auth; NSMotionUsageDescription; UIRequiresFullScreen; portrait-only iPad.
3. App requires internet to `https://gstaxi.online/api`.
4. Background location is for drivers during active free-meter / trip tracking only.
5. Privacy policy: https://gstaxi.online/privacy.html
6. Account deletion: in-app (profile/drawer) → `DELETE /api/account`.
7. Driver subscription renewal is offline (admin); demo driver must be unblocked.

## قبل الرفع
- ابنِ IPA بـ `1.0.16+22`.
- بعد إضافة Firebase iOS + APNs أعد البناء إن أردت الإشعارات على iPhone.
- الصق رد 4.3 من `APP_STORE_4_3_RESPONSE_AR.md`.
- لقطات شاشة تطابق الواجهة الحالية.

## بعد القبول
- حدّث `AppUpdateGate.iosStoreUrl` برابط App Store الحقيقي.
