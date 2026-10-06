# إرسال رمز التحقق عبر واتساب (UltraMsg)

## الملفات

- `app/Services/UltraMsgWhatsAppService.php`
- `app/Services/PhoneOtpService.php` (محدّث)
- في `config/services.php` أضف:

```php
'ultramsg' => [
    'instance_id' => env('ULTRAMSG_INSTANCE_ID', '187935'),
    'token' => env('ULTRAMSG_TOKEN', ''),
],
```

## في `.env` على السيرفر

```env
ULTRAMSG_INSTANCE_ID=187935
ULTRAMSG_TOKEN=pmh64l8j2qh5ii0s
EXPOSE_OTP_IN_API=false
```

ثم:

```bash
php artisan config:clear
php artisan config:cache
```

الرمز يصل على واتساب فقط ولا يُعرض في التطبيق.
