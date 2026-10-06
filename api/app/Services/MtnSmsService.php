<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * إرسال SMS عبر بوابة MTN سوريا (ConcatenatedSender).
 *
 * مثل Postman: POST + ترويسات Content-Type/User-Agent، والمعاملات في الـ query.
 *
 * https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx
 * ?User=...&Pass=...&From=GSTaxi&Gsm=9639xxxxxxxx&Msg=...&Lang=0
 */
class MtnSmsService
{
    public const LANG_AR = 0;

    public const LANG_EN = 1;

    public function isConfigured(): bool
    {
        return trim((string) config('services.mtn_sms.username', '')) !== ''
            && trim((string) config('services.mtn_sms.password', '')) !== ''
            && trim((string) config('services.mtn_sms.from', '')) !== '';
    }

    /**
     * تحويل الرقم إلى صيغة MTN: 9639xxxxxxxx (بدون +).
     */
    public function toGsm(string $phone): string
    {
        $digits = preg_replace('/\D+/', '', $phone) ?? '';
        if ($digits === '') {
            return '';
        }

        if (str_starts_with($digits, '00963')) {
            $digits = substr($digits, 2);
        }

        if (str_starts_with($digits, '0') && strlen($digits) === 10) {
            $digits = '963'.substr($digits, 1);
        }

        if (! str_starts_with($digits, '963') && strlen($digits) === 9) {
            $digits = '963'.$digits;
        }

        return $digits;
    }

    /**
     * ترميز الرسالة لـ Lang=0 (عربي): UCS-2BE كـ hex كبير.
     * للإنجليزية (Lang=1) تُرسل النص كما هو.
     */
    public function encodeMessage(string $text, int $lang = self::LANG_AR): string
    {
        if ($lang === self::LANG_EN) {
            return $text;
        }

        $ucs2 = mb_convert_encoding($text, 'UCS-2BE', 'UTF-8');

        return strtoupper(bin2hex($ucs2));
    }

    /**
     * @param  list<string>|string  $phones  أرقام محلية أو E.164
     */
    public function send(string|array $phones, string $message, int $lang = self::LANG_AR): bool
    {
        if (! $this->isConfigured()) {
            Log::warning('[mtn_sms] missing username/password/from');

            return false;
        }

        $list = is_array($phones) ? $phones : [$phones];
        $gsmParts = [];
        foreach ($list as $p) {
            $g = $this->toGsm((string) $p);
            if ($g !== '') {
                $gsmParts[] = $g;
            }
        }
        $gsmParts = array_values(array_unique($gsmParts));
        if ($gsmParts === []) {
            Log::warning('[mtn_sms] no valid recipients');

            return false;
        }

        $url = rtrim((string) config(
            'services.mtn_sms.url',
            'https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx'
        ), '?');

        $query = [
            'User' => (string) config('services.mtn_sms.username'),
            'Pass' => (string) config('services.mtn_sms.password'),
            'From' => (string) config('services.mtn_sms.from', 'GSTaxi'),
            'Gsm' => implode(';', $gsmParts),
            'Msg' => $this->encodeMessage($message, $lang),
            'Lang' => $lang,
        ];

        // ASP.NET غالباً يقرأ المعاملات من الـ query حتى مع POST (كما في Postman).
        $requestUrl = $url.'?'.http_build_query($query);

        try {
            $attempts = max(1, (int) config('services.mtn_sms.retries', 3));
            $connectTimeout = max(5, (int) config('services.mtn_sms.connect_timeout', 20));
            $timeout = max($connectTimeout + 5, (int) config('services.mtn_sms.timeout', 55));
            $lastBody = '';
            $lastStatus = 0;
            $lastError = null;

            $bindIface = trim((string) config('services.mtn_sms.bind_interface', ''));

            for ($i = 1; $i <= $attempts; $i++) {
                try {
                    $options = [
                        'verify' => (bool) config('services.mtn_sms.verify_ssl', false),
                    ];
                    // SO_BINDTODEVICE عبر اسم الواجهة → خروج Ghafir/STE (ليس Starlink).
                    if ($bindIface !== '' && defined('CURLOPT_INTERFACE')) {
                        $options['curl'] = [
                            CURLOPT_INTERFACE => $bindIface,
                        ];
                    }

                    $http = Http::timeout($timeout)
                        ->connectTimeout($connectTimeout)
                        ->withHeaders([
                            'Content-Type' => 'text/xml',
                            'User-Agent' => 'PostmanRuntime/7.43.3',
                            'Accept' => '*/*',
                        ])
                        ->withOptions($options);

                    // POST فارغ الجسم + text/xml — مطابق لتجربة Postman.
                    $res = $http->withBody('', 'text/xml')->post($requestUrl);
                    $lastStatus = $res->status();
                    $lastBody = trim((string) $res->body());
                    $ok = $res->successful() && $this->responseLooksSuccessful($lastBody);

                    if ($ok) {
                        Log::info('[mtn_sms] sent', [
                            'method' => 'POST',
                            'gsm' => $query['Gsm'],
                            'response' => $lastBody,
                            'attempt' => $i,
                            'bind_interface' => $bindIface !== '' ? $bindIface : null,
                        ]);

                        return true;
                    }

                    Log::warning('[mtn_sms] send attempt failed', [
                        'method' => 'POST',
                        'attempt' => $i,
                        'status' => $lastStatus,
                        'body' => $lastBody,
                        'gsm' => $query['Gsm'],
                        'bind_interface' => $bindIface !== '' ? $bindIface : null,
                    ]);
                } catch (\Throwable $e) {
                    $lastError = $e->getMessage();
                    // لا تسجّل الرابط كاملاً (يحتوي User/Pass).
                    $safeError = preg_replace('/([?&](?:User|Pass)=)[^&]*/i', '$1***', $lastError) ?? $lastError;
                    Log::warning('[mtn_sms] attempt exception', [
                        'method' => 'POST',
                        'attempt' => $i,
                        'message' => $safeError,
                        'gsm' => $query['Gsm'],
                        'bind_interface' => $bindIface !== '' ? $bindIface : null,
                    ]);
                }

                if ($i < $attempts) {
                    usleep(350000 * $i);
                }
            }

            $safeError = $lastError
                ? (preg_replace('/([?&](?:User|Pass)=)[^&]*/i', '$1***', $lastError) ?? $lastError)
                : null;
            Log::error('[mtn_sms] send failed', [
                'method' => 'POST',
                'status' => $lastStatus,
                'body' => $lastBody,
                'error' => $safeError,
                'gsm' => $query['Gsm'],
                'attempts' => $attempts,
            ]);

            return false;
        } catch (\Throwable $e) {
            $safeError = preg_replace('/([?&](?:User|Pass)=)[^&]*/i', '$1***', $e->getMessage()) ?? $e->getMessage();
            Log::error('[mtn_sms] exception', [
                'method' => 'POST',
                'message' => $safeError,
                'gsm' => $query['Gsm'] ?? null,
            ]);

            return false;
        }
    }

    public function sendOtp(string $phone, string $code, string $purpose): bool
    {
        $purposeLabel = match ($purpose) {
            PhoneOtpService::PURPOSE_RESET_PASSWORD => 'استعادة كلمة المرور',
            default => 'تأكيد الحساب',
        };

        $body = 'GS Taxi'
            ."\nرمز التحقق ({$purposeLabel}): {$code}"
            ."\nصالح 10 دقائق. لا تشاركه مع احد.";

        return $this->send($phone, $body, self::LANG_AR);
    }

    /**
     * بوابة MTN غالباً ترجع نصاً قصيراً عند النجاح (أو فارغاً مع HTTP 200).
     */
    private function responseLooksSuccessful(string $body): bool
    {
        $lower = mb_strtolower($body);
        foreach (['error', 'fail', 'invalid', 'denied', 'unauthorized', 'wrong'] as $bad) {
            if ($body !== '' && str_contains($lower, $bad)) {
                return false;
            }
        }

        return true;
    }
}
