<?php

/**
 * اختبار اتصال/إرسال MTN SMS على السيرفر.
 * الاستخدام:
 *   php artisan tinker < لا — شغّل مباشرة:
 *   php scripts/test_mtn_sms.php [رقم_هاتف]
 */

require __DIR__.'/../vendor/autoload.php';
$app = require __DIR__.'/../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Services\MtnSmsService;
use Illuminate\Support\Facades\Http;

$svc = app(MtnSmsService::class);

echo "configured=" . ($svc->isConfigured() ? 'yes' : 'no') . PHP_EOL;
echo "url=" . config('services.mtn_sms.url') . PHP_EOL;
echo "from=" . config('services.mtn_sms.from') . PHP_EOL;
echo "user_set=" . (trim((string) config('services.mtn_sms.username')) !== '' ? 'yes' : 'no') . PHP_EOL;
echo "pass_set=" . (trim((string) config('services.mtn_sms.password')) !== '' ? 'yes' : 'no') . PHP_EOL;
echo "timeout=" . config('services.mtn_sms.timeout') . PHP_EOL;
echo "connect_timeout=" . config('services.mtn_sms.connect_timeout') . PHP_EOL;

$url = rtrim((string) config(
    'services.mtn_sms.url',
    'https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx'
), '?');

$host = parse_url($url, PHP_URL_HOST) ?: 'services.mtnsyr.com';
$port = parse_url($url, PHP_URL_PORT) ?: 7443;

echo "dns_check host={$host} ..." . PHP_EOL;
$ips = @gethostbynamel($host);
echo 'dns=' . ($ips ? implode(',', $ips) : 'FAIL') . PHP_EOL;

echo "tcp_check {$host}:{$port} ..." . PHP_EOL;
$errno = 0;
$errstr = '';
$fp = @fsockopen('ssl://'.$host, (int) $port, $errno, $errstr, 12);
if ($fp) {
    echo "tcp=OK" . PHP_EOL;
    fclose($fp);
} else {
    // جرّب بدون فرض ssl wrapper على المنفذ
    $fp2 = @fsockopen($host, (int) $port, $errno, $errstr, 12);
    if ($fp2) {
        echo "tcp=OK(plain)" . PHP_EOL;
        fclose($fp2);
    } else {
        echo "tcp=FAIL errno={$errno} err={$errstr}" . PHP_EOL;
    }
}

$phone = $argv[1] ?? '';
if ($phone === '') {
    // رقم اختبار من .env إن وُجد
    $phone = (string) env('MTN_SMS_TEST_PHONE', '');
}

if ($phone === '') {
    echo "no_phone — مرّر رقماً: php scripts/test_mtn_sms.php 09xxxxxxxx" . PHP_EOL;
    echo "connectivity_only=done" . PHP_EOL;
    exit(0);
}

$gsm = $svc->toGsm($phone);
echo "gsm={$gsm}" . PHP_EOL;
$msg = 'اختبار GS Taxi — '.date('Y-m-d H:i:s');
echo "sending..." . PHP_EOL;
$ok = $svc->send($phone, $msg, MtnSmsService::LANG_AR);
echo 'send=' . ($ok ? 'OK' : 'FAIL') . PHP_EOL;
exit($ok ? 0 : 1);
