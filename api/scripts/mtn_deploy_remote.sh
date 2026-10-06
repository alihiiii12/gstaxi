#!/bin/bash
set -e
cd /var/www/gstaxi/api
if grep -q '^MTN_SMS_BIND_INTERFACE=' .env; then
  sed -i 's/^MTN_SMS_BIND_INTERFACE=.*/MTN_SMS_BIND_INTERFACE=wlp131s0/' .env
else
  printf '\nMTN_SMS_BIND_INTERFACE=wlp131s0\n' >> .env
fi
grep '^MTN_SMS_BIND_INTERFACE=' .env
php artisan config:clear
php artisan config:cache
php -r '
require "vendor/autoload.php";
$app=require "bootstrap/app.php";
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
echo "bind=".config("services.mtn_sms.bind_interface")."\n";
$ch=curl_init("https://api.ipify.org");
curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_INTERFACE=>config("services.mtn_sms.bind_interface"),CURLOPT_TIMEOUT=>12]);
echo "exit_ip=".curl_exec($ch)." err=".curl_error($ch)."\n";
'
echo "=== send test via bound interface ==="
php scripts/test_mtn_sms.php 0938828814
echo "=== last log ==="
grep -E "\[mtn_sms\]" storage/logs/laravel.log | tail -8
