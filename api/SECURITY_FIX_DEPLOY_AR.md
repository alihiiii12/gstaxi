# رفع إصلاحات الأمن (تقرير GSTP-SEC-2026-001) — المرحلة أ/ب جزئياً

## ملفات للرفع إلى `/var/www/syriataxi-api/`

| ملف |
|-----|
| `app/Http/Controllers/UserController.php` |
| `app/Http/Requests/CreateUserRequest.php` |
| `app/Http/Middleware/SecurityHeaders.php` |
| `app/Services/PhoneOtpService.php` |
| `app/Services/UltraMsgWhatsAppService.php` |
| `routes/api.php` |
| `bootstrap/app.php` |
| `config/cors.php` |
| `config/services.php` (مع مفتاح ultramsg) |

## تعديلات `.env` على السيرفر

```env
APP_DEBUG=false
APP_URL=https://gstaxi.online

EXPOSE_OTP_IN_API=false
ULTRAMSG_INSTANCE_ID=187935
ULTRAMSG_TOKEN=pmh64l8j2qh5ii0s

FRONTEND_URL=https://gstaxi.online
```

ثم:

```bash
php artisan config:clear
php artisan config:cache
php artisan route:clear
php artisan route:cache
```

## Nginx (HTTPS + إخفاء Server + Headers) — مثال

```nginx
server_tokens off;

server {
    listen 80;
    server_name gstaxi.online www.gstaxi.online;
    return 301 https://$host$request_uri;
}

# في كتلة HTTPS أضف:
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options SAMEORIGIN always;
add_header Referrer-Policy strict-origin-when-cross-origin always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

فعّل شهادة SSL (certbot) إن لم تكن مفعّلة.

## ما أُصلح في الكود

- **VUL-01:** منع تغيير `roll` عبر `/user/update`
- **VUL-02:** عدم إرجاع OTP في API + واتساب
- **VUL-04:** throttle على login/OTP
- **VUL-05:** يجب `APP_DEBUG=false` يدوياً في `.env`
- **VUL-07:** خصومات خلف `auth:sanctum`
- **VUL-09/10:** CORS مقيد + SecurityHeaders
- **VUL-03/11/12/14:** في تطبيق Flutter (APK جديد)

## Google API Key (VUL-06) — يدوي في Console

قيّد المفتاح بـ package `com.syriataxi.syriatax` + SHA-1/256 لإصدار الـ release.
