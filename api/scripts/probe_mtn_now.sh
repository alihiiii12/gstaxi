#!/bin/bash
cd /var/www/gstaxi/api
echo "=== connectivity ==="
curl -k -sS -m 20 -o /tmp/mtn_body.txt -w "http=%{http_code} time=%{time_total}\n" \
  "https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx" || echo "curl_exit=$?"
timeout 12 bash -c 'echo >/dev/tcp/188.160.0.43/7443' && echo port7443_open || echo port7443_closed
echo "=== configured ==="
php -r '
require "vendor/autoload.php";
$app=require "bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$s=app(App\Services\MtnSmsService::class);
echo $s->isConfigured()?"configured=yes\n":"configured=no\n";
'
echo "=== recent success/fail ==="
grep -E '\[mtn_sms\] (sent|send failed|exception)' storage/logs/laravel.log | tail -15
echo "=== done ==="
