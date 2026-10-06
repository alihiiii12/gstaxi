# رفع MTN SMS OTP إلى السيرفر

## ملفات للرفع
- `app/Services/MtnSmsService.php` ← جديد
- `app/Services/PhoneOtpService.php` ← استبدال
- `config/services.php` ← استبدال

## أضف في `.env` على السيرفر

```env
OTP_CHANNEL=sms
OTP_BYPASS=false
EXPOSE_OTP_IN_API=false

MTN_SMS_URL=https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx
MTN_SMS_USER=asdasde314
MTN_SMS_PASS=asdasde131114
MTN_SMS_FROM=GSTaxi
MTN_SMS_VERIFY_SSL=false
```

## بعد الرفع

```bash
cd /var/www/gstaxi/api
php artisan config:clear
php artisan config:cache
```

## اختبار سريع (tinker)

```bash
php artisan tinker
```

```php
app(\App\Services\MtnSmsService::class)->sendOtp('09xxxxxxxx', '1234', 'register');
```

استبدل `09xxxxxxxx` برقم MTN حقيقي تملكه.

## ملاحظات
- `From=GSTaxi` يجب أن يكون مفعّلاً عند MTN (Sender ID).
- الرسائل العربية تُرمَّز UCS-2 hex مع `Lang=0`.
- UltraMsg لم يعد يُستخدم لـ OTP؛ يبقى متاحاً للبث إن وُجد.
