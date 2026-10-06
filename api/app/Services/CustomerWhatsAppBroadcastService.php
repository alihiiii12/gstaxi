<?php

namespace App\Services;

use App\Models\User;
use App\Models\AppSetting;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * بث إعلانات واتساب لكل زبائن التطبيق عبر UltraMsg.
 */
class CustomerWhatsAppBroadcastService
{
    public function __construct(
        private UltraMsgWhatsAppService $whatsApp,
        private PhoneOtpService $otp,
    ) {}

    /**
     * @param  list<int>|null  $customerIds
     */
    public function countRecipients(bool $onlyVerified = true, ?array $customerIds = null): int
    {
        return count($this->uniqueRecipientNumbers($onlyVerified, $customerIds));
    }

    public const BATCH_SIZE = 50;

    /**
     * إحصائيات الدفعات: من أُرسل لهم سابقاً لا يُعاد تضمينهم.
     *
     * @param  list<int>|null  $customerIds
     * @return array{total:int, already_sent:int, remaining:int, next_batch:int, batch_size:int}
     */
    public function batchStats(bool $onlyVerified = true, ?array $customerIds = null, int $batchSize = self::BATCH_SIZE): array
    {
        $batchSize = max(1, min(500, $batchSize));
        $all = $this->uniqueRecipientNumbers($onlyVerified, $customerIds);
        $sentMap = $this->campaignSentMap();
        $already = 0;
        $remainingList = [];
        foreach ($all as $n) {
            if (isset($sentMap[$n])) {
                $already++;
            } else {
                $remainingList[] = $n;
            }
        }
        $remaining = count($remainingList);

        return [
            'total' => count($all),
            'already_sent' => $already,
            'remaining' => $remaining,
            'next_batch' => min($batchSize, $remaining),
            'batch_size' => $batchSize,
        ];
    }

    public function resetCampaignSent(): void
    {
        try {
            AppSetting::setValue('wa_broadcast_batch_sent', '[]');
        } catch (\Throwable $e) {
            Log::warning('[wa-broadcast] reset campaign failed: '.$e->getMessage());
        }
        Cache::forget('wa_broadcast:batch_sent');
    }

    /**
     * @return array<string, true>
     */
    public function campaignSentMap(): array
    {
        $cached = Cache::get('wa_broadcast:batch_sent');
        if (is_array($cached)) {
            $map = [];
            foreach ($cached as $n) {
                if (is_string($n) && $n !== '') {
                    $map[$n] = true;
                }
            }

            return $map;
        }

        $raw = AppSetting::getString('wa_broadcast_batch_sent', '[]');
        try {
            $decoded = json_decode($raw, true);
        } catch (\Throwable) {
            $decoded = null;
        }
        $list = is_array($decoded) ? $decoded : [];
        $map = [];
        foreach ($list as $n) {
            if (is_string($n) && $n !== '') {
                $map[$n] = true;
            }
        }
        Cache::put('wa_broadcast:batch_sent', array_keys($map), now()->addDays(90));

        return $map;
    }

    /**
     * @param  list<string>  $numbers
     */
    public function markCampaignSent(array $numbers): void
    {
        $map = $this->campaignSentMap();
        foreach ($numbers as $n) {
            $n = trim((string) $n);
            if ($n !== '') {
                $map[$n] = true;
            }
        }
        $list = array_keys($map);
        try {
            AppSetting::setValue('wa_broadcast_batch_sent', json_encode($list, JSON_UNESCAPED_UNICODE));
        } catch (\Throwable $e) {
            Log::warning('[wa-broadcast] persist batch sent failed: '.$e->getMessage());
        }
        Cache::put('wa_broadcast:batch_sent', $list, now()->addDays(90));
    }

    /**
     * @param  list<int>|null  $customerIds
     * @return list<string>
     */
    public function uniqueRecipientNumbers(bool $onlyVerified = true, ?array $customerIds = null): array
    {
        $q = User::query()
            ->where('roll', 'Customer')
            ->whereNotNull('number')
            ->where('number', '!=', '');

        if ($customerIds !== null) {
            $ids = array_values(array_unique(array_filter(array_map('intval', $customerIds))));
            if ($ids === []) {
                return [];
            }
            $q->whereIn('id', $ids);
        }

        if ($onlyVerified) {
            $q->whereNotNull('phone_verified_at');
        }

        if (Schema::hasColumn('users', 'banned')) {
            $q->where(function ($w) {
                $w->whereNull('banned')->orWhere('banned', false)->orWhere('banned', 0);
            });
        }

        $seen = [];
        $q->orderBy('id')->select(['id', 'number'])->chunkById(200, function ($rows) use (&$seen) {
            foreach ($rows as $u) {
                $n = $this->otp->normalizeNumber((string) $u->number);
                if ($n === '' || isset($seen[$n])) {
                    continue;
                }
                if (! preg_match('/^09\d{8}$/', $n)) {
                    continue;
                }
                $seen[$n] = true;
            }
        });

        return array_keys($seen);
    }

    /**
     * @param  array{message:?string, media_url:?string, media_type:?string, media_filename:?string, only_verified:bool, customer_ids:?list<int>, batch_mode?:bool, batch_size?:int}  $payload
     */
    public function runBroadcast(string $broadcastId, array $payload): void
    {
        $message = trim((string) ($payload['message'] ?? ''));
        $mediaUrl = isset($payload['media_url']) ? trim((string) $payload['media_url']) : '';
        $mediaType = isset($payload['media_type']) ? trim((string) $payload['media_type']) : '';
        $mediaFilename = isset($payload['media_filename']) ? trim((string) $payload['media_filename']) : '';
        $onlyVerified = (bool) ($payload['only_verified'] ?? true);
        $customerIds = $payload['customer_ids'] ?? null;
        if (is_array($customerIds) && $customerIds === []) {
            $customerIds = null;
        }

        $batchMode = (bool) ($payload['batch_mode'] ?? false);
        $batchSize = (int) ($payload['batch_size'] ?? self::BATCH_SIZE);
        if ($batchSize < 1) {
            $batchSize = self::BATCH_SIZE;
        }
        $batchSize = min(500, $batchSize);

        $numbers = $this->uniqueRecipientNumbers(
            $onlyVerified,
            is_array($customerIds) ? $customerIds : null,
        );

        if ($batchMode) {
            $sentMap = $this->campaignSentMap();
            $numbers = array_values(array_filter(
                $numbers,
                static fn (string $n): bool => ! isset($sentMap[$n]),
            ));
            $numbers = array_slice($numbers, 0, $batchSize);
        }

        $total = count($numbers);
        $sent = 0;
        $failed = 0;
        $attempted = [];

        $this->writeStatus($broadcastId, [
            'status' => 'running',
            'total' => $total,
            'sent' => 0,
            'failed' => 0,
            'batch_mode' => $batchMode,
            'batch_size' => $batchMode ? $batchSize : null,
            'started_at' => now()->toIso8601String(),
        ]);
        $this->clearCancelFlag($broadcastId);
        Cache::put('wa_broadcast:active_id', $broadcastId, now()->addHours(12));

        if (! $this->whatsApp->isConfigured()) {
            Log::error('[wa-broadcast] ultramsg not configured', ['id' => $broadcastId]);
            $this->writeStatus($broadcastId, [
                'status' => 'failed',
                'total' => $total,
                'sent' => 0,
                'failed' => $total,
                'error' => 'UltraMsg غير مُعدّ على السيرفر',
                'finished_at' => now()->toIso8601String(),
            ]);
            $this->clearActiveIf($broadcastId);

            return;
        }

        if ($total < 1) {
            $this->writeStatus($broadcastId, [
                'status' => 'failed',
                'total' => 0,
                'sent' => 0,
                'failed' => 0,
                'error' => $batchMode
                    ? 'لا يوجد مستلمون متبقّون في الدفعة — أعد التعيين أو لا مزيد'
                    : 'لا يوجد مستلمون',
                'finished_at' => now()->toIso8601String(),
            ]);
            $this->clearActiveIf($broadcastId);

            return;
        }

        // UltraMsg للمستندات: حد ~30MB، وملفات .apk غالباً تُرفض → نرسل رابطاً نصياً.
        $sendMediaAsLink = $mediaUrl !== ''
            && ($mediaType === 'document' || $mediaType === '')
            && $this->mustSendMediaAsTextLink($mediaUrl);

        if ($sendMediaAsLink) {
            Log::info('[wa-broadcast] media will be sent as text link (too large or apk)', [
                'id' => $broadcastId,
                'url' => $mediaUrl,
            ]);
        }

        $cancelled = false;
        foreach ($numbers as $local) {
            if ($this->isCancelRequested($broadcastId)) {
                $cancelled = true;
                break;
            }

            $attempted[] = $local;
            $e164 = $this->otp->toE164Syria($local);
            $ok = false;
            try {
                if ($mediaUrl !== '' && $mediaType === 'image') {
                    $ok = $this->whatsApp->sendImage($e164, $mediaUrl, $message !== '' ? $message : null);
                } elseif ($mediaUrl !== '' && $sendMediaAsLink) {
                    $ok = $this->whatsApp->sendText(
                        $e164,
                        $this->buildMediaLinkMessage($message, $mediaUrl),
                    );
                } elseif ($mediaUrl !== '' && ($mediaType === 'document' || $mediaType === '')) {
                    $ok = $this->whatsApp->sendDocument(
                        $e164,
                        $mediaUrl,
                        $mediaFilename !== '' ? $mediaFilename : basename(parse_url($mediaUrl, PHP_URL_PATH) ?: 'file.bin'),
                        $message !== '' ? $message : ' ',
                    );
                } elseif ($message !== '') {
                    $ok = $this->whatsApp->sendText($e164, $message);
                }
            } catch (\Throwable $e) {
                Log::error('[wa-broadcast] send exception', [
                    'id' => $broadcastId,
                    'to' => $local,
                    'error' => $e->getMessage(),
                ]);
                $ok = false;
            }

            if ($ok) {
                $sent++;
            } else {
                $failed++;
            }

            if (($sent + $failed) % 5 === 0 || ($sent + $failed) === 1) {
                $this->writeStatus($broadcastId, [
                    'status' => 'running',
                    'total' => $total,
                    'sent' => $sent,
                    'failed' => $failed,
                ]);
            }

            usleep(400_000);
        }

        // لا نعيد الإرسال لمن حاولنا إرسالهم في هذه الدفعة (نجاح أو فشل)
        if ($attempted !== []) {
            $this->markCampaignSent($attempted);
        }

        $batchAfter = $batchMode
            ? $this->batchStats($onlyVerified, is_array($customerIds) ? $customerIds : null, $batchSize)
            : null;

        if ($cancelled) {
            $this->writeStatus($broadcastId, [
                'status' => 'cancelled',
                'total' => $total,
                'sent' => $sent,
                'failed' => $failed,
                'error' => 'تم إلغاء الإرسال من لوحة التحكم',
                'batch_stats' => $batchAfter,
                'finished_at' => now()->toIso8601String(),
            ]);
            $this->persistLastBroadcast([
                'broadcast_id' => $broadcastId,
                'message' => $message,
                'total' => $total,
                'sent' => $sent,
                'failed' => $failed,
                'status' => 'cancelled',
                'batch_mode' => $batchMode,
                'has_media' => $mediaUrl !== '',
                'media_type' => $mediaType,
                'media_url' => $mediaUrl !== '' ? $mediaUrl : null,
                'finished_at' => now()->toIso8601String(),
            ]);
            $this->clearCancelFlag($broadcastId);
            $this->clearActiveIf($broadcastId);
            Log::info('[wa-broadcast] cancelled', [
                'id' => $broadcastId,
                'sent' => $sent,
                'failed' => $failed,
                'total' => $total,
            ]);

            return;
        }

        $this->writeStatus($broadcastId, [
            'status' => 'done',
            'total' => $total,
            'sent' => $sent,
            'failed' => $failed,
            'batch_stats' => $batchAfter,
            'finished_at' => now()->toIso8601String(),
        ]);

        $this->persistLastBroadcast([
            'broadcast_id' => $broadcastId,
            'message' => $message,
            'total' => $total,
            'sent' => $sent,
            'failed' => $failed,
            'status' => 'done',
            'batch_mode' => $batchMode,
            'has_media' => $mediaUrl !== '',
            'media_type' => $mediaType,
            'media_url' => $mediaUrl !== '' ? $mediaUrl : null,
            'finished_at' => now()->toIso8601String(),
        ]);

        $this->clearCancelFlag($broadcastId);
        $this->clearActiveIf($broadcastId);

        Log::info('[wa-broadcast] finished', [
            'id' => $broadcastId,
            'total' => $total,
            'sent' => $sent,
            'failed' => $failed,
            'batch_mode' => $batchMode,
        ]);
    }

    public function requestCancel(string $broadcastId): bool
    {
        $st = $this->readStatus($broadcastId);
        if ($st === null) {
            return false;
        }
        $status = (string) ($st['status'] ?? '');
        if (! in_array($status, ['queued', 'running'], true)) {
            return false;
        }
        Cache::put($this->cancelKey($broadcastId), 1, now()->addHours(6));
        $this->writeStatus($broadcastId, [
            'status' => 'cancelling',
            'cancel_requested' => true,
        ]);

        return true;
    }

    public function isCancelRequested(string $broadcastId): bool
    {
        return (bool) Cache::get($this->cancelKey($broadcastId));
    }

    public function clearCancelFlag(string $broadcastId): void
    {
        Cache::forget($this->cancelKey($broadcastId));
    }

    public function activeBroadcastId(): ?string
    {
        $id = Cache::get('wa_broadcast:active_id');

        return is_string($id) && $id !== '' ? $id : null;
    }

    public function clearActiveIf(string $broadcastId): void
    {
        if ($this->activeBroadcastId() === $broadcastId) {
            Cache::forget('wa_broadcast:active_id');
        }
    }

    private function cancelKey(string $broadcastId): string
    {
        return 'wa_broadcast:cancel:'.$broadcastId;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function persistLastBroadcast(array $data): void
    {
        try {
            AppSetting::setValue('wa_broadcast_last', json_encode($data, JSON_UNESCAPED_UNICODE));
        } catch (\Throwable $e) {
            Log::warning('[wa-broadcast] persist last failed: '.$e->getMessage());
        }
        Cache::put('wa_broadcast:last', $data, now()->addDays(90));
    }

    /**
     * @return array<string, mixed>|null
     */
    public function lastBroadcast(): ?array
    {
        $cached = Cache::get('wa_broadcast:last');
        if (is_array($cached)) {
            return $cached;
        }
        $raw = AppSetting::getString('wa_broadcast_last', '');
        if ($raw === '') {
            return null;
        }
        try {
            $decoded = json_decode($raw, true);

            return is_array($decoded) ? $decoded : null;
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function writeStatus(string $broadcastId, array $data): void
    {
        $prev = Cache::get($this->cacheKey($broadcastId), []);
        if (! is_array($prev)) {
            $prev = [];
        }
        $merged = array_merge($prev, $data, ['id' => $broadcastId]);
        Cache::put(
            $this->cacheKey($broadcastId),
            $merged,
            now()->addHours(24),
        );
        // أثناء الإرسال خزّن معاينة الرسالة إن وُجدت في prev
        if (($merged['status'] ?? '') === 'done') {
            // handled in runBroadcast
        }
    }

    /**
     * @return array<string, mixed>|null
     */
    public function readStatus(string $broadcastId): ?array
    {
        $data = Cache::get($this->cacheKey($broadcastId));

        return is_array($data) ? $data : null;
    }

    private function cacheKey(string $broadcastId): string
    {
        return 'wa_broadcast:'.$broadcastId;
    }

    /**
     * UltraMsg document max ~30MB؛ WhatsApp يرفض .apk كمرفق غالباً.
     */
    private function mustSendMediaAsTextLink(string $mediaUrl): bool
    {
        $path = (string) (parse_url($mediaUrl, PHP_URL_PATH) ?: '');
        if (preg_match('/\.apk$/i', $path)) {
            return true;
        }

        $bytes = $this->probeRemoteFileSize($mediaUrl);
        // هامش تحت حد UltraMsg (30MB)
        if ($bytes !== null && $bytes > 28 * 1024 * 1024) {
            return true;
        }

        return false;
    }

    private function probeRemoteFileSize(string $url): ?int
    {
        try {
            $res = \Illuminate\Support\Facades\Http::timeout(12)->withHeaders([
                'Accept' => '*/*',
            ])->head($url);
            if ($res->successful()) {
                $len = $res->header('Content-Length');
                if (is_numeric($len)) {
                    return (int) $len;
                }
            }
        } catch (\Throwable) {
        }

        return null;
    }

    private function buildMediaLinkMessage(string $message, string $mediaUrl): string
    {
        $message = trim($message);
        if ($message === '') {
            return "حمّل التحديث من الرابط:\n{$mediaUrl}";
        }
        if (str_contains($message, $mediaUrl)) {
            return $message;
        }

        return $message."\n\n{$mediaUrl}";
    }
}
