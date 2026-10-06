<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * إرسال رسائل واتساب عبر UltraMsg.
 */
class UltraMsgWhatsAppService
{
    public function isConfigured(): bool
    {
        $instance = trim((string) config('services.ultramsg.instance_id', ''));
        $token = trim((string) config('services.ultramsg.token', ''));

        return $instance !== '' && $token !== '';
    }

    /**
     * @return bool نجحت الاستجابة من UltraMsg
     */
    public function sendText(string $phoneE164, string $body): bool
    {
        return $this->postForm('messages/chat', [
            'to' => $this->normalizeRecipient($phoneE164),
            'body' => $body,
        ], $phoneE164);
    }

    /**
     * صورة عبر رابط عام (HTTPS يُفضَّل).
     */
    public function sendImage(string $phoneE164, string $imageUrl, ?string $caption = null): bool
    {
        $payload = [
            'to' => $this->normalizeRecipient($phoneE164),
            'image' => $imageUrl,
        ];
        if ($caption !== null && trim($caption) !== '') {
            $payload['caption'] = $caption;
        }

        return $this->postForm('messages/image', $payload, $phoneE164);
    }

    /**
     * مستند/ملف عبر رابط عام.
     */
    public function sendDocument(
        string $phoneE164,
        string $documentUrl,
        ?string $filename = null,
        ?string $caption = null,
    ): bool {
        $payload = [
            'to' => $this->normalizeRecipient($phoneE164),
            'document' => $documentUrl,
        ];
        if ($filename !== null && trim($filename) !== '') {
            $payload['filename'] = trim($filename);
        } else {
            $path = (string) (parse_url($documentUrl, PHP_URL_PATH) ?: '');
            $payload['filename'] = basename($path) ?: 'file.bin';
        }
        // UltraMsg يعتبر caption مطلوباً في التوثيق
        $payload['caption'] = ($caption !== null && trim($caption) !== '')
            ? trim($caption)
            : ' ';

        return $this->postForm('messages/document', $payload, $phoneE164);
    }

    public function sendOtp(string $phoneE164, string $code, string $purpose): bool
    {
        $purposeLabel = match ($purpose) {
            PhoneOtpService::PURPOSE_RESET_PASSWORD => 'استعادة كلمة المرور',
            default => 'تأكيد الحساب',
        };

        $body = "GS Taxi\n"
            ."رمز التحقق ({$purposeLabel}): {$code}\n"
            .'صالح لمدة 10 دقائق. لا تشاركه مع أحد.';

        return $this->sendText($phoneE164, $body);
    }

    /**
     * @param  array<string, mixed>  $fields
     */
    private function postForm(string $path, array $fields, string $rawPhone): bool
    {
        if (! $this->isConfigured()) {
            Log::warning('[ultramsg] missing instance_id or token');

            return false;
        }

        $to = (string) ($fields['to'] ?? '');
        if ($to === '') {
            Log::warning('[ultramsg] invalid recipient', ['phone' => $rawPhone]);

            return false;
        }

        $instance = trim((string) config('services.ultramsg.instance_id'));
        $token = trim((string) config('services.ultramsg.token'));
        $url = 'https://api.ultramsg.com/instance'.$instance.'/'.$path;

        $fields['token'] = $token;

        try {
            $res = Http::asForm()
                ->timeout(45)
                ->post($url, $fields);

            if (! $res->successful()) {
                Log::error('[ultramsg] send failed', [
                    'path' => $path,
                    'status' => $res->status(),
                    'body' => $res->body(),
                    'to' => $to,
                ]);

                return false;
            }

            Log::info('[ultramsg] sent', [
                'path' => $path,
                'to' => $to,
                'response' => $res->json() ?? $res->body(),
            ]);

            return true;
        } catch (\Throwable $e) {
            Log::error('[ultramsg] exception', [
                'path' => $path,
                'message' => $e->getMessage(),
                'to' => $to,
            ]);

            return false;
        }
    }

    private function normalizeRecipient(string $phoneE164): string
    {
        $digits = preg_replace('/\D+/', '', $phoneE164) ?? '';
        if ($digits === '') {
            return '';
        }

        // UltraMsg يقبل +9639… أو 9639…
        if (str_starts_with($digits, '963')) {
            return '+'.$digits;
        }

        return '+'.$digits;
    }
}
