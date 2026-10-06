# قائمة الرفع الكاملة — إصلاح ثغرات GSTP-SEC-2026-001

ارفع إلى: `/var/www/syriataxi-api/`  
المصدر المحلي المفضّل: `C:\xampp\htdocs\SyriaTaxi-main\`  
أو المرآة: `C:\Users\hp\StudioProjects\syriataxi\api\`

---

## 1) ملفات PHP / Laravel (استبدال كامل لكل ملف)

```
app/Http/Controllers/UserController.php
app/Http/Requests/CreateUserRequest.php
app/Http/Requests/CustomerRegisterRequest.php
app/Http/Middleware/SecurityHeaders.php          ← جديد
app/Http/Middleware/EnsureBackofficeStaff.php    ← جديد
app/Services/PhoneOtpService.php
app/Services/UltraMsgWhatsAppService.php         ← جديد
routes/api.php
bootstrap/app.php
config/cors.php                                  ← جديد أو استبدال
config/services.php                              ← يجب أن يحتوي ultramsg
```

### محتوى `ultramsg` داخل `config/services.php`

```php
'ultramsg' => [
    'instance_id' => env('ULTRAMSG_INSTANCE_ID', '187935'),
    'token' => env('ULTRAMSG_TOKEN', ''),
],
```

---

## 2) تعديلات `.env` على السيرفر (أضف/عدّل)

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://gstaxi.online

EXPOSE_OTP_IN_API=false
ULTRAMSG_INSTANCE_ID=187935
ULTRAMSG_TOKEN=pmh64l8j2qh5ii0s
FRONTEND_URL=https://gstaxi.online
```

---

## 3) أوامر بعد الرفع

```bash
cd /var/www/syriataxi-api
php artisan config:clear
php artisan config:cache
php artisan route:clear
php artisan route:cache
php artisan cache:clear
```

---

## 4) Nginx (يدوي على السيرفر)

- فعّل شهادة SSL لـ `gstaxi.online` (إن لم تكن مفعّلة).
- أعد توجيه HTTP → HTTPS.
- أضف من الملف: `api/deploy/nginx-security-snippet.conf`
  - أهم سطر: `server_tokens off;`
  - ترويسات HSTS / X-Frame-Options / nosniff …

ثم:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 5) Google Cloud / Firebase (يدوي — VUL-06)

في Google Cloud Console للمفتاح `AIzaSy...`:

1. Application restrictions → Android apps  
2. Package: `com.syriataxi.syriatax`  
3. أضف SHA-1 و SHA-256 لتوقيع الـ **release**  
4. عطّل APIs غير المستخدمة  
5. راجع Firebase App Check / Storage Rules إن وُجدت

---

## 6) تطبيق الموبايل (ليس رفع سيرفر — APK)

بعد HTTPS على السيرفر ابنِ APK جديد يتضمن:

- `https://gstaxi.online/api`
- `usesCleartextTraffic=false`
- تخزين توكن آمن
- حذف لوحة الأدمن
- إخفاء OTP من الشاشة

```bash
flutter build apk --release
```

المسار: `build/app/outputs/flutter-apk/app-release.apk`

---

## 7) حالة الثغرات بعد الإصلاح

| ID | الثغرة | المعالجة |
|----|--------|----------|
| VUL-01 | تصعيد Admin عبر roll | مغلق في `UserController::update` |
| VUL-02 | تسريب OTP | لا يُرجع في API + واتساب |
| VUL-03 | HTTP | HTTPS في التطبيق + Nginx |
| VUL-04 | Rate limit | throttle على auth/OTP |
| VUL-05 | APP_DEBUG | `false` في `.env` |
| VUL-06 | مفاتيح Google | تقييد يدوي في Console |
| VUL-07 | بيانات بدون مصادقة | خصومات/مواقع/شكاوى محمية |
| VUL-08 | User enumeration | رسالة تسجيل موحّدة |
| VUL-09 | CORS مفتوح | `config/cors.php` مقيد |
| VUL-10 | Security headers | Middleware + Nginx |
| VUL-11 | توكن غير آمن | flutter_secure_storage |
| VUL-12 | لوحة أدمن في التطبيق | محذوفة |
| VUL-13 | مسارات تطوير | Release build |
| VUL-14 | طباعة توكن | أُزيلت |
| VUL-15 | كشف nginx / Pinning | `server_tokens off`؛ Pinning بعد تثبيت SSL وأخذ fingerprint |

---

## 8) اختبار سريع بعد الرفع

1. `POST /api/user/update` مع `"roll":"Admin"` → الدور لا يتغير  
2. `POST /api/register-customer` → لا يظهر `verification_code` في الرد  
3. محاولات login متكررة → 429 بعد الحد  
4. خطأ API → بدون Stack Trace  
5. `https://gstaxi.online/api/...` يعمل  
6. حساب Customer لا يفتح `/api/admin/*`
