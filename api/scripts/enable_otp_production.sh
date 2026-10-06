#!/bin/bash
# تفعيل OTP للإنتاج: MTN عبر Ghafir ثم واتساب إن فشل، بدون bypass.
set -euo pipefail
cd /var/www/gstaxi/api

python3 - <<'PY'
from pathlib import Path
p = Path('.env')
text = p.read_text(encoding='utf-8', errors='replace')
lines = text.splitlines()
wanted = {
    'OTP_CHANNEL': 'sms',
    'OTP_BYPASS': 'false',
    'EXPOSE_OTP_IN_API': 'false',
    'MTN_SMS_BIND_INTERFACE': 'wlp131s0',
    'MTN_SMS_CONNECT_TIMEOUT': '5',
    'MTN_SMS_TIMEOUT': '12',
    'MTN_SMS_RETRIES': '1',
}
seen = set()
out = []
for line in lines:
    if not line or line.lstrip().startswith('#') or '=' not in line:
        out.append(line)
        continue
    key = line.split('=', 1)[0].strip()
    if key in wanted:
        if key in seen:
            continue  # drop duplicates
        out.append(f'{key}={wanted[key]}')
        seen.add(key)
    else:
        out.append(line)
for key, val in wanted.items():
    if key not in seen:
        out.append(f'{key}={val}')
p.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
print('env updated:', ', '.join(f'{k}={v}' for k,v in wanted.items()))
PY

php artisan config:clear
php artisan config:cache

php -r '
require "vendor/autoload.php";
$app=require "bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$otp=app(App\Services\PhoneOtpService::class);
$mtn=app(App\Services\MtnSmsService::class);
$wa=app(App\Services\UltraMsgWhatsAppService::class);
echo "bypass=".($otp->bypassEnabled()?"yes":"no")."\n";
echo "channel=".$otp->deliveryChannel()."\n";
echo "mtn_configured=".($mtn->isConfigured()?"yes":"no")."\n";
echo "mtn_bind=".config("services.mtn_sms.bind_interface")."\n";
echo "wa_configured=".($wa->isConfigured()?"yes":"no")."\n";
echo "connect_timeout=".config("services.mtn_sms.connect_timeout")."\n";
'

sudo -n /usr/bin/systemctl reload php8.3-fpm
echo "php-fpm reloaded"

# تثبيت مراقب IP إن أمكن
mkdir -p /home/gstaxi_1z/bin
cp -f /var/www/gstaxi/api/scripts/watch_ste_ip.sh /home/gstaxi_1z/bin/watch_ste_ip.sh 2>/dev/null || true
chmod +x /home/gstaxi_1z/bin/watch_ste_ip.sh /var/www/gstaxi/api/scripts/watch_ste_ip.sh 2>/dev/null || true
bash /home/gstaxi_1z/bin/watch_ste_ip.sh || bash /var/www/gstaxi/api/scripts/watch_ste_ip.sh || true

# cron كل ساعة لمراقبة تغيّر IP
CRON_LINE='15 * * * * /home/gstaxi_1z/bin/watch_ste_ip.sh >> /var/www/gstaxi/api/storage/logs/ste_ip_watch.cron.log 2>&1'
(crontab -l 2>/dev/null | grep -v watch_ste_ip.sh; echo "$CRON_LINE") | crontab -
echo "cron installed for STE IP watch"
crontab -l | grep watch_ste_ip || true

echo DONE
