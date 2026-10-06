<?php

namespace App\Services;

use App\Models\User;
use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * إرسال FCM HTTP v1 — يجب أن يصل الإشعار في الخلفية (لوحة النظام).
 */
class FcmPushService
{
    private static ?string $cachedAccessToken = null;

    private static ?int $cachedAccessTokenExpiry = null;

    /**
     * يجب أن تطابق AndroidManifest + MainActivity + android_notification_channels.dart.
     * التطبيقات القديمة لا تملك هذه القنوات فيستخدم Android القناة الافتراضية في الـ Manifest.
     */
    public const ANDROID_CHANNEL_ID = 'syriataxi_notify_v3';

    public const ANDROID_RIDE_OFFERS_CHANNEL_ID = 'syriataxi_ride_offers_v3';

    private const RIDE_OFFER_KINDS = ['immediate_request', 'scheduled_request'];

    public function sendToUser(?User $user, string $title, string $body, array $data = []): bool
    {
        if (! $user || empty($user->fcm_token)) {
            return false;
        }

        $ok = $this->sendToToken((string) $user->fcm_token, $title, $body, $data);
        if (! $ok) {
            // لا نمسح التوكن هنا إلا من استجابة UNREGISTERED داخل sendRaw.
        }

        return $ok;
    }

    public function sendToUserId(int $userId, string $title, string $body, array $data = []): bool
    {
        $user = User::query()->find($userId);

        return $this->sendToUser($user, $title, $body, $data);
    }

    /**
     * إرسال مباشرة لرمز FCM (طلبات فورية / اشتراكات).
     */
    public function sendToToken(?string $deviceToken, string $title, string $body, array $data = []): bool
    {
        if ($deviceToken === null || $deviceToken === '') {
            return false;
        }

        $path = config('services.firebase.credentials');
        if (! $path || ! is_readable($path)) {
            Log::warning('[fcm] credentials file missing or unreadable', [
                'path' => $path,
            ]);

            return false;
        }

        $projectId = $this->projectIdFromCredentials($path);
        if (! $projectId) {
            Log::warning('[fcm] missing project_id');

            return false;
        }

        $access = $this->accessToken($path);
        if (! $access) {
            return false;
        }

        $stringData = $this->stringifyData(array_merge($data, [
            'title' => $title,
            'body' => $body,
        ]));

        $kind = (string) ($data['kind'] ?? $data['type'] ?? '');
        $isRideOffer = in_array($kind, self::RIDE_OFFER_KINDS, true);

        // notification + data + channel_id = يظهر في شريط الإشعارات والتطبيق مغلق/بالخلفية.
        $payload = [
            'message' => [
                'token' => $deviceToken,
                'notification' => [
                    'title' => $title,
                    'body' => $body,
                ],
                'data' => $stringData,
                'android' => [
                    'priority' => 'HIGH',
                    'notification' => [
                        'channel_id' => $isRideOffer
                            ? self::ANDROID_RIDE_OFFERS_CHANNEL_ID
                            : self::ANDROID_CHANNEL_ID,
                        'sound' => $isRideOffer ? 'gs_ringtone' : 'gs_notify',
                        'default_vibrate_timings' => true,
                        'notification_priority' => 'PRIORITY_MAX',
                    ],
                ],
                'apns' => [
                    'payload' => [
                        'aps' => [
                            'sound' => 'default',
                            'content-available' => 1,
                        ],
                    ],
                ],
            ],
        ];

        $url = 'https://fcm.googleapis.com/v1/projects/'.$projectId.'/messages:send';

        try {
            // asJson()->post وليس postJson (غير موجودة في بعض إصدارات Laravel).
            $response = Http::withToken($access)
                ->timeout(15)
                ->acceptJson()
                ->asJson()
                ->post($url, $payload);
        } catch (\Throwable $e) {
            Log::warning('[fcm] http error', ['e' => $e->getMessage()]);

            return false;
        }

        if ($response->successful()) {
            return true;
        }

        $bodyJson = $response->json();
        Log::warning('[fcm] send failed', [
            'status' => $response->status(),
            'body' => $response->body(),
        ]);

        return false;
    }

    private function stringifyData(array $data): array
    {
        $out = [];
        foreach ($data as $k => $v) {
            if ($v === null) {
                continue;
            }
            $key = (string) $k;
            if (is_array($v) || is_object($v)) {
                $out[$key] = json_encode($v, JSON_UNESCAPED_UNICODE) ?: '{}';
            } else {
                $out[$key] = (string) $v;
            }
        }

        return $out;
    }

    private function accessToken(string $credentialsPath): ?string
    {
        $now = time();
        if (self::$cachedAccessToken && self::$cachedAccessTokenExpiry && $now < self::$cachedAccessTokenExpiry - 60) {
            return self::$cachedAccessToken;
        }

        $json = json_decode((string) file_get_contents($credentialsPath), true);
        if (! is_array($json)) {
            return null;
        }

        try {
            $creds = new ServiceAccountCredentials(
                'https://www.googleapis.com/auth/firebase.messaging',
                $json
            );
            $t = $creds->fetchAuthToken();
        } catch (\Throwable $e) {
            Log::warning('[fcm] oauth failed', ['e' => $e->getMessage()]);

            return null;
        }

        $access = $t['access_token'] ?? null;
        if (! is_string($access) || $access === '') {
            return null;
        }

        self::$cachedAccessToken = $access;
        $expiresIn = (int) ($t['expires_in'] ?? 3600);
        self::$cachedAccessTokenExpiry = $now + max(120, $expiresIn);

        return $access;
    }

    private function projectIdFromCredentials(string $credentialsPath): ?string
    {
        $override = config('services.firebase.project_id');
        if (is_string($override) && $override !== '') {
            return $override;
        }

        $json = json_decode((string) file_get_contents($credentialsPath), true);

        return is_array($json) && isset($json['project_id']) ? (string) $json['project_id'] : null;
    }

    private function maybeClearInvalidToken(User $user, ?array $bodyJson): void
    {
        $code = data_get($bodyJson, 'error.details.0.errorCode')
            ?? data_get($bodyJson, 'error.status');

        if ($code === 'UNREGISTERED' || $code === 'NOT_FOUND') {
            User::query()->whereKey($user->id)->update(['fcm_token' => null]);
        }
    }
}
