# رد على رفض Guideline 4.3(a) — انسخه إلى Resolution Center / App Review Notes

## English reply (paste to Apple)

Hello App Review team,

GS Taxi is an original ride-hailing product operated for our company in Syria (backend: gstaxi.online). It is **not** a repackaged template app.

In this build (1.0.16 / 22) we further differentiated the product experience under our GS Taxi identity:

- Removed/renamed former template-associated UI module to `gst_booking_ui`.
- Replaced the common full-screen yellow/amber auth and drawer look with GS Taxi dark slate + antique gold branding.
- Booking sheet uses Arabic من/إلى badges, الآن/لاحقاً modes, glass/navy search overlay with recent destinations, and gold primary CTA — not the common A/B taxi-template layout.
- Map route color is GS blue (not the common purple navigation style); custom navy-gold destination pin.
- Driver trip sheet is docked with Start → trip info → live free-meter; map tools collapsed into a menu.
- Faster splash and API timeouts improve responsiveness without changing business logic.
- The app connects exclusively to our production API (subscriptions, free meter, OTP, dispatch).
- Local competitor APK extracts / reference frame dumps were removed from the project tree.

Unique product capabilities (not a generic clone skin):
1. Driver free-meter billing with company tariff rules (including opening fare) stored on our server.
2. Driver subscription gating managed by our admin panel.
3. Unified driver poll-snapshot dispatch with push-first trip events designed for our operations load.
4. Customer/driver flows integrated with our own privacy policy and account deletion at https://gstaxi.online/privacy.html

We own and maintain this codebase and backend. Please re-review with the demo accounts provided in App Review Information. Updated screenshots in App Store Connect match this build’s UI.

Thank you.

## عربي (مرجع داخلي)
أبل رفضت بسبب تشابه مع قوالب/تطبيقات أخرى (4.3a). في البناء 22 أزلنا مظهر القالب، ميّزنا شيت الحجز والبحث والعداد والمسار الأزرق، سرّعنا السبلاش ومهلات API، وحذفنا مجلدات الاستخراج المرجعية. حدّث لقطات الشاشة قبل الرفع، وانشر privacy.html على السيرفر.
