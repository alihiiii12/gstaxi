# إصلاح CSRF token mismatch — لوحة الإدارة

نفّذ على السيرفر في `/var/www/syriataxi-api`

## 1) ملف `.env`

```env
APP_URL=http://72.62.2.152
SESSION_DOMAIN=
SANCTUM_STATEFUL_DOMAINS=localhost,localhost:5173,127.0.0.1
```

(لا تضف `72.62.2.152` داخل SANCTUM_STATEFUL_DOMAINS)

```bash
php artisan config:clear
php artisan config:cache
```

## 2) استثناء مسارات API من CSRF

**Laravel 11** — `bootstrap/app.php` داخل `withMiddleware`:

```php
$middleware->validateCsrfTokens(except: [
    'api/*',
]);
```

**Laravel 10** — `app/Http/Middleware/VerifyCsrfToken.php`:

```php
protected $except = [
    'api/*',
];
```

```bash
php artisan config:cache
```

## 3) CORS (للتطوير من localhost فقط)

`config/cors.php`:

```php
'paths' => ['api/*', 'sanctum/csrf-cookie'],
'allowed_origins' => ['http://localhost:5173', 'http://72.62.2.152'],
'supports_credentials' => true,
```
