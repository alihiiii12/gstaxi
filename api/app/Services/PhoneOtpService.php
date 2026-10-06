<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Str;

class PhoneOtpService
{
    public const PURPOSE_REGISTER = 'register';

    public const PURPOSE_RESET_PASSWORD = 'reset_password';

    public const COUNTRY_ISO = 'SY';

    public const DIAL_CODE = '+963';

    private const OTP_TTL_SECONDS = 600;

    private const RESET_TOKEN_TTL_SECONDS = 900;

    /**
     * تنسيق محلي سوري: 09xxxxxxxx (10 أرقام).
     */
    public function normalizeNumber(string $raw): string
    {
        $n = preg_replace('/\D+/', '', $raw) ?? '';
        if (str_starts_with($n, '963')) {
            $n = '0'.substr($n, 3);
        }
        if (str_starts_with($n, '00963')) {
            $n = '0'.substr($n, 5);
        }
        if (strlen($n) === 9 && ! str_starts_with($n, '0')) {
            $n = '0'.$n;
        }

        return $n;
    }

    public function toE164Syria(string $raw): string
    {
        $local = $this->normalizeNumber($raw);
        if (str_starts_with($local, '0')) {
            return self::DIAL_CODE.substr($local, 1);
        }

        return self::DIAL_CODE.$local;
    }

    public function formatLocalSyria(string $raw): string
    {
        return $this->normalizeNumber($raw);
    }

    /**
     * قناة الإرسال الفعلية: sms | whatsapp | bypass
     */
    public function deliveryChannel(): string
    {
        if ($this->bypassEnabled()) {
            return 'bypass';
        }

        $configured = strtolower(trim((string) config('services.otp.channel', 'sms')));

        if ($configured === 'whatsapp') {
            return 'whatsapp';
        }

        if ($configured === 'auto') {
            $mtn = app(MtnSmsService::class);
            if ($mtn->isConfigured()) {
                return 'sms';
            }
            $wa = app(UltraMsgWhatsAppService::class);
            if ($wa->isConfigured()) {
                return 'whatsapp';
            }

            return 'sms';
        }

        return 'sms';
    }

    /**
     * بيانات الهاتف في رد الـ API — بدون كشف الرمز للتطبيق.
     *
     * @return array<string, mixed>
     */
    public function buildOtpApiPayload(string $number, string $code): array
    {
        $local = $this->normalizeNumber($number);
        $channel = $this->deliveryChannel();

        $payload = [
            'number' => $local,
            'country' => self::COUNTRY_ISO,
            'country_name' => 'سوريا',
            'dial_code' => self::DIAL_CODE,
            'phone_e164' => $this->toE164Syria($local),
            'phone_display' => $local,
            'channel' => $channel === 'bypass' ? 'sms' : $channel,
        ];

        // لا تُرجع الرمز للتطبيق إلا بطلب صريح + رمز حقيقي.
        if ($this->shouldExposeOtpInApi() && $code !== '' && $code !== '0000') {
            $payload['verification_code'] = $code;
            $payload['debug_otp_code'] = $code;
        }

        return $payload;
    }

    public function shouldExposeOtpInApi(): bool
    {
        return (bool) config('services.otp.expose_in_api', false);
    }

    /**
     * تجاوز الإرسال: الحساب يُفعَّل فوراً، وأي رمز من 4 أرقام يُقبل.
     * عطّله في الإنتاج بعد ربط MTN: OTP_BYPASS=false
     */
    public function bypassEnabled(): bool
    {
        $fromEnv = env('OTP_BYPASS', null);
        if ($fromEnv !== null && $fromEnv !== '') {
            return filter_var($fromEnv, FILTER_VALIDATE_BOOLEAN);
        }

        return (bool) config('services.otp.bypass', false);
    }

    public function fallbackCode(): string
    {
        $code = preg_replace('/\D+/', '', (string) config('services.otp.fallback_code', '0000')) ?? '0000';

        return strlen($code) === 4 ? $code : '0000';
    }

    /** @return string الرمز المُنشأ */
    public function send(string $number, string $purpose): string
    {
        $number = $this->normalizeNumber($number);
        $code = $this->bypassEnabled()
            ? $this->fallbackCode()
            : (string) random_int(1000, 9999);
        $key = $this->otpKey($number, $purpose);
        try {
            Redis::setex($key, self::OTP_TTL_SECONDS, $code);
        } catch (\Throwable $e) {
            cache()->put($key, $code, self::OTP_TTL_SECONDS);
        }

        $e164 = $this->toE164Syria($number);
        $channel = $this->deliveryChannel();

        Log::info('Phone OTP (Syria)', [
            'country' => self::COUNTRY_ISO,
            'dial_code' => self::DIAL_CODE,
            'phone_e164' => $e164,
            'number' => $number,
            'purpose' => $purpose,
            'channel' => $channel,
        ]);

        if ($channel === 'bypass') {
            return $code;
        }

        if ($channel === 'sms') {
            $mtn = app(MtnSmsService::class);
            $sent = $mtn->sendOtp($number, $code, $purpose);
            if ($sent) {
                return $code;
            }

            // بوابة MTN:7443 غالباً تنقطع عبر Starlink — احتياطي واتساب فوراً.
            $wa = app(UltraMsgWhatsAppService::class);
            if ($wa->isConfigured() && $wa->sendOtp($e164, $code, $purpose)) {
                Log::warning('Phone OTP MTN failed — delivered via WhatsApp fallback', [
                    'phone_e164' => $e164,
                    'purpose' => $purpose,
                ]);

                return $code;
            }

            Log::error('Phone OTP MTN SMS delivery failed', [
                'phone_e164' => $e164,
                'purpose' => $purpose,
            ]);
            $this->forget($key);
            throw new \RuntimeException('OTP_DELIVERY_FAILED');
        }

        if ($channel === 'auto') {
            $mtn = app(MtnSmsService::class);
            if ($mtn->isConfigured() && $mtn->sendOtp($number, $code, $purpose)) {
                return $code;
            }
            $wa = app(UltraMsgWhatsAppService::class);
            if ($wa->isConfigured() && $wa->sendOtp($e164, $code, $purpose)) {
                Log::info('Phone OTP delivered via WhatsApp (auto)', [
                    'phone_e164' => $e164,
                    'purpose' => $purpose,
                ]);

                return $code;
            }
            Log::error('Phone OTP auto delivery failed', [
                'phone_e164' => $e164,
                'purpose' => $purpose,
            ]);
            $this->forget($key);
            throw new \RuntimeException('OTP_DELIVERY_FAILED');
        }

        $wa = app(UltraMsgWhatsAppService::class);
        $sent = $wa->sendOtp($e164, $code, $purpose);
        if (! $sent) {
            Log::error('Phone OTP WhatsApp delivery failed', [
                'phone_e164' => $e164,
                'purpose' => $purpose,
            ]);
            $this->forget($key);
            throw new \RuntimeException('OTP_DELIVERY_FAILED');
        }

        return $code;
    }

    public function verify(string $number, string $purpose, string $code): bool
    {
        $entered = trim($code);
        if ($this->bypassEnabled() && preg_match('/^\d{4}$/', $entered) === 1) {
            return true;
        }

        $number = $this->normalizeNumber($number);
        $key = $this->otpKey($number, $purpose);
        $expected = $this->read($key);
        if ($expected === null || $entered !== (string) $expected) {
            return false;
        }
        $this->forget($key);

        return true;
    }

    public function issueResetToken(string $number): string
    {
        $number = $this->normalizeNumber($number);
        $token = Str::random(48);
        $key = $this->resetKey($number);
        try {
            Redis::setex($key, self::RESET_TOKEN_TTL_SECONDS, $token);
        } catch (\Throwable $e) {
            cache()->put($key, $token, self::RESET_TOKEN_TTL_SECONDS);
        }

        return $token;
    }

    public function verifyResetToken(string $number, string $token): bool
    {
        $number = $this->normalizeNumber($number);
        $key = $this->resetKey($number);
        $expected = $this->read($key);
        if ($expected === null || ! hash_equals((string) $expected, $token)) {
            return false;
        }
        $this->forget($key);

        return true;
    }

    private function otpKey(string $number, string $purpose): string
    {
        return "otp:{$purpose}:{$number}";
    }

    private function resetKey(string $number): string
    {
        return "pwd_reset:{$number}";
    }

    private function read(string $key): ?string
    {
        try {
            $v = Redis::get($key);

            return $v !== null && $v !== false ? (string) $v : null;
        } catch (\Throwable $e) {
            $v = cache()->get($key);

            return $v !== null ? (string) $v : null;
        }
    }

    private function forget(string $key): void
    {
        try {
            Redis::del($key);
        } catch (\Throwable $e) {
            cache()->forget($key);
        }
    }
}
