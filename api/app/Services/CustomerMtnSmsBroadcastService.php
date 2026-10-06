<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * بث SMS عبر MTN — زبائن و/أو سائقون (الكل / محددون / دفعات).
 */
class CustomerMtnSmsBroadcastService
{
    public const BATCH_SIZE = 50;

    public const AUDIENCE_CUSTOMERS = 'customers';

    public const AUDIENCE_DRIVERS = 'drivers';

    public const AUDIENCE_ALL = 'all';

    public function __construct(
        private PhoneOtpService $otp,
        private MtnSmsService $mtn,
    ) {
    }

    public static function normalizeAudience(?string $raw): string
    {
        $a = strtolower(trim((string) $raw));
        if (in_array($a, [self::AUDIENCE_DRIVERS, self::AUDIENCE_ALL], true)) {
            return $a;
        }

        return self::AUDIENCE_CUSTOMERS;
    }

    /**
     * @param  list<int>|null  $userIds
     * @return list<string>
     */
    public function uniqueRecipientNumbers(
        bool $onlyVerified = true,
        ?array $userIds = null,
        string $audience = self::AUDIENCE_CUSTOMERS,
    ): array {
        $audience = self::normalizeAudience($audience);
        $rolls = match ($audience) {
            self::AUDIENCE_DRIVERS => ['Driver'],
            self::AUDIENCE_ALL => ['Customer', 'Driver'],
            default => ['Customer'],
        };

        $q = User::query()
            ->whereIn('roll', $rolls)
            ->whereNotNull('number')
            ->where('number', '!=', '');

        if ($userIds !== null) {
            $ids = array_values(array_unique(array_filter(array_map('intval', $userIds))));
            if ($ids === []) {
                return [];
            }
            $q->whereIn('id', $ids);
        }

        if ($onlyVerified && Schema::hasColumn('users', 'phone_verified_at')) {
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

    public function batchStats(
        bool $onlyVerified = true,
        ?array $userIds = null,
        int $batchSize = self::BATCH_SIZE,
        string $audience = self::AUDIENCE_CUSTOMERS,
    ): array {
        $numbers = $this->uniqueRecipientNumbers($onlyVerified, $userIds, $audience);
        $total = count($numbers);
        $sentMap = $this->campaignSentMap($audience);
        $already = 0;
        $remainingList = [];
        foreach ($numbers as $n) {
            if (isset($sentMap[$n])) {
                $already++;
            } else {
                $remainingList[] = $n;
            }
        }
        $batchSize = max(1, min(500, $batchSize));

        return [
            'total' => $total,
            'already_sent' => $already,
            'remaining' => count($remainingList),
            'next_batch' => min($batchSize, count($remainingList)),
            'batch_size' => $batchSize,
            'audience' => self::normalizeAudience($audience),
        ];
    }

    public function resetCampaignSent(?string $audience = null): void
    {
        $audience = self::normalizeAudience($audience);
        $settingKey = $this->sentSettingKey($audience);
        $cacheKey = $this->sentCacheKey($audience);
        try {
            AppSetting::setValue($settingKey, '[]');
        } catch (\Throwable $e) {
        }
        Cache::forget($cacheKey);
        // توافق مع الحملات القديمة (زبائن فقط)
        if ($audience === self::AUDIENCE_CUSTOMERS) {
            try {
                AppSetting::setValue('mtn_sms_broadcast_batch_sent', '[]');
            } catch (\Throwable $e) {
            }
            Cache::forget('mtn_sms_broadcast:batch_sent');
        }
    }

    private function sentSettingKey(string $audience): string
    {
        return 'mtn_sms_broadcast_batch_sent_'.$audience;
    }

    private function sentCacheKey(string $audience): string
    {
        return 'mtn_sms_broadcast:batch_sent:'.$audience;
    }

    /** @return array<string, true> */
    private function campaignSentMap(string $audience): array
    {
        $audience = self::normalizeAudience($audience);
        $list = Cache::get($this->sentCacheKey($audience));
        if (! is_array($list)) {
            try {
                $raw = AppSetting::getString($this->sentSettingKey($audience), '');
                if ($raw === '' && $audience === self::AUDIENCE_CUSTOMERS) {
                    $raw = AppSetting::getString('mtn_sms_broadcast_batch_sent', '[]');
                }
                if ($raw === '') {
                    $raw = '[]';
                }
                $decoded = json_decode((string) $raw, true);
                $list = is_array($decoded) ? $decoded : [];
            } catch (\Throwable $e) {
                $list = [];
            }
        }
        $map = [];
        foreach ($list as $n) {
            $n = (string) $n;
            if ($n !== '') {
                $map[$n] = true;
            }
        }

        return $map;
    }

    /** @param list<string> $numbers */
    private function markSent(array $numbers, string $audience): void
    {
        $audience = self::normalizeAudience($audience);
        $map = $this->campaignSentMap($audience);
        foreach ($numbers as $n) {
            $map[(string) $n] = true;
        }
        $list = array_keys($map);
        try {
            AppSetting::setValue($this->sentSettingKey($audience), json_encode($list, JSON_UNESCAPED_UNICODE));
        } catch (\Throwable $e) {
        }
        Cache::put($this->sentCacheKey($audience), $list, now()->addDays(90));
    }

    public function lastBroadcast(): ?array
    {
        $raw = Cache::get('mtn_sms_broadcast:last');
        if (is_array($raw)) {
            return $raw;
        }
        try {
            $s = AppSetting::getString('mtn_sms_broadcast_last', '');
            if ($s === '') {
                return null;
            }
            $decoded = json_decode($s, true);

            return is_array($decoded) ? $decoded : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    private function saveLast(array $data): void
    {
        Cache::put('mtn_sms_broadcast:last', $data, now()->addDays(30));
        try {
            AppSetting::setValue('mtn_sms_broadcast_last', json_encode($data, JSON_UNESCAPED_UNICODE));
        } catch (\Throwable $e) {
        }
    }

    private function statusKey(string $id): string
    {
        return 'mtn_sms_broadcast:'.$id;
    }

    public function getStatus(string $id): ?array
    {
        $v = Cache::get($this->statusKey($id));

        return is_array($v) ? $v : null;
    }

    public function cancel(string $id): bool
    {
        $st = $this->getStatus($id);
        if (! $st || ($st['status'] ?? '') !== 'running') {
            return false;
        }
        $st['status'] = 'cancelled';
        Cache::put($this->statusKey($id), $st, now()->addDay());

        return true;
    }

    /**
     * @param  array{message:string, only_verified:bool, customer_ids:?list<int>, batch_mode?:bool, batch_size?:int, audience?:string}  $payload
     */
    public function runBroadcast(string $broadcastId, array $payload): void
    {
        $message = trim((string) ($payload['message'] ?? ''));
        if ($message === '') {
            Cache::put($this->statusKey($broadcastId), [
                'id' => $broadcastId,
                'status' => 'failed',
                'error' => 'رسالة فارغة',
                'total' => 0,
                'sent' => 0,
                'failed' => 0,
            ], now()->addDay());

            return;
        }

        $onlyVerified = (bool) ($payload['only_verified'] ?? true);
        $customerIds = $payload['customer_ids'] ?? null;
        if (is_array($customerIds) && $customerIds === []) {
            $customerIds = null;
        }
        $batchMode = (bool) ($payload['batch_mode'] ?? false);
        $batchSize = max(1, min(500, (int) ($payload['batch_size'] ?? self::BATCH_SIZE)));
        $audience = self::normalizeAudience($payload['audience'] ?? self::AUDIENCE_CUSTOMERS);

        $all = $this->uniqueRecipientNumbers(
            $onlyVerified,
            is_array($customerIds) ? $customerIds : null,
            $audience,
        );
        $sentMap = $this->campaignSentMap($audience);
        $targets = [];
        foreach ($all as $n) {
            if ($batchMode && isset($sentMap[$n])) {
                continue;
            }
            $targets[] = $n;
            if ($batchMode && count($targets) >= $batchSize) {
                break;
            }
        }

        $total = count($targets);
        $status = [
            'id' => $broadcastId,
            'status' => 'running',
            'total' => $total,
            'sent' => 0,
            'failed' => 0,
            'error' => null,
            'audience' => $audience,
        ];
        Cache::put($this->statusKey($broadcastId), $status, now()->addDay());

        $ok = 0;
        $fail = 0;
        $succeeded = [];
        foreach ($targets as $i => $number) {
            $cur = $this->getStatus($broadcastId);
            if (($cur['status'] ?? '') === 'cancelled') {
                break;
            }

            try {
                if ($this->mtn->send($number, $message, MtnSmsService::LANG_AR)) {
                    $ok++;
                    $succeeded[] = $number;
                } else {
                    $fail++;
                }
            } catch (\Throwable $e) {
                $fail++;
                Log::warning('[mtn-sms-broadcast] '.$e->getMessage());
            }

            if (($i + 1) % 5 === 0 || $i === $total - 1) {
                $status['sent'] = $ok;
                $status['failed'] = $fail;
                Cache::put($this->statusKey($broadcastId), $status, now()->addDay());
            }

            usleep(120000);
        }

        if ($succeeded !== []) {
            $this->markSent($succeeded, $audience);
        }

        $final = $this->getStatus($broadcastId) ?? $status;
        if (($final['status'] ?? '') === 'running') {
            $final['status'] = 'finished';
        }
        $final['sent'] = $ok;
        $final['failed'] = $fail;
        Cache::put($this->statusKey($broadcastId), $final, now()->addDay());

        $this->saveLast([
            'message' => mb_substr($message, 0, 200),
            'total' => $total,
            'sent' => $ok,
            'failed' => $fail,
            'audience' => $audience,
            'finished_at' => now()->toIso8601String(),
        ]);
    }
}
