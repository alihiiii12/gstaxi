<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Services\CustomerMtnSmsBroadcastService;
use App\Services\MtnSmsService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class MtnSmsBroadcastController extends Controller
{
    public function recipientsCount(Request $request, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $onlyVerified = filter_var($request->query('only_verified', true), FILTER_VALIDATE_BOOLEAN);
        $ids = $this->parseUserIds($request->query('customer_ids'));
        $batchSize = (int) $request->query('batch_size', CustomerMtnSmsBroadcastService::BATCH_SIZE);
        $audience = CustomerMtnSmsBroadcastService::normalizeAudience(
            (string) $request->query('audience', CustomerMtnSmsBroadcastService::AUDIENCE_CUSTOMERS)
        );
        $stats = $broadcast->batchStats($onlyVerified, $ids, $batchSize, $audience);

        return response()->json([
            'success' => true,
            'data' => [
                'recipients' => $stats['total'],
                'batch' => $stats,
                'audience' => $audience,
                'mtn_configured' => app(MtnSmsService::class)->isConfigured(),
                'last_broadcast' => $broadcast->lastBroadcast(),
            ],
        ]);
    }

    public function resetBatch(Request $request, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $audience = CustomerMtnSmsBroadcastService::normalizeAudience(
            (string) $request->input('audience', CustomerMtnSmsBroadcastService::AUDIENCE_CUSTOMERS)
        );
        $broadcast->resetCampaignSent($audience);
        $onlyVerified = filter_var($request->input('only_verified', true), FILTER_VALIDATE_BOOLEAN);
        $ids = $this->parseUserIds($request->input('customer_ids'));
        $stats = $broadcast->batchStats($onlyVerified, $ids, CustomerMtnSmsBroadcastService::BATCH_SIZE, $audience);

        return response()->json([
            'success' => true,
            'message' => 'تم مسح سجل مستلمي SMS — يمكن البدء من أول دفعة',
            'data' => ['batch' => $stats, 'audience' => $audience],
        ]);
    }

    public function lastBroadcast(Request $request, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return response()->json([
            'success' => true,
            'data' => $broadcast->lastBroadcast(),
        ]);
    }

    public function status(Request $request, string $id, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $st = $broadcast->getStatus($id);
        if (! $st) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        return response()->json(['success' => true, 'data' => $st]);
    }

    public function cancel(Request $request, string $id, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if (! $broadcast->cancel($id)) {
            return response()->json(['success' => false, 'message' => 'تعذر الإلغاء'], 422);
        }

        return response()->json(['success' => true, 'message' => 'تم طلب الإلغاء']);
    }

    public function send(Request $request, CustomerMtnSmsBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if (! app(MtnSmsService::class)->isConfigured()) {
            return response()->json([
                'success' => false,
                'message' => 'MTN SMS غير مُعدّ — أضف MTN_SMS_USER و MTN_SMS_PASS و MTN_SMS_FROM في .env',
            ], 422);
        }

        $validated = $request->validate([
            'message' => 'required|string|max:700',
            'send_all' => 'nullable',
            'customer_ids' => 'nullable',
            'batch_mode' => 'nullable',
            'batch_size' => 'nullable|integer|min:1|max:500',
            'only_verified' => 'nullable',
            'audience' => 'nullable|string|in:customers,drivers,all',
        ]);

        $message = trim((string) $validated['message']);
        $onlyVerified = filter_var($request->input('only_verified', true), FILTER_VALIDATE_BOOLEAN);
        $sendAll = filter_var($request->input('send_all', true), FILTER_VALIDATE_BOOLEAN);
        $batchMode = filter_var($request->input('batch_mode', true), FILTER_VALIDATE_BOOLEAN);
        $batchSize = (int) ($validated['batch_size'] ?? CustomerMtnSmsBroadcastService::BATCH_SIZE);
        $audience = CustomerMtnSmsBroadcastService::normalizeAudience(
            (string) ($validated['audience'] ?? CustomerMtnSmsBroadcastService::AUDIENCE_CUSTOMERS)
        );

        $customerIds = $sendAll ? null : $this->parseUserIds($request->input('customer_ids'));
        if (! $sendAll && ($customerIds === null || $customerIds === [])) {
            return response()->json([
                'success' => false,
                'message' => 'حدّد مشتركين أو اختر «الكل»',
            ], 422);
        }

        $stats = $broadcast->batchStats($onlyVerified, $customerIds, $batchSize, $audience);
        $recipients = $batchMode ? $stats['next_batch'] : $stats['total'];
        if ($recipients < 1) {
            $emptyMsg = match ($audience) {
                CustomerMtnSmsBroadcastService::AUDIENCE_DRIVERS => 'لا يوجد سائقون مطابقون للإرسال',
                CustomerMtnSmsBroadcastService::AUDIENCE_ALL => 'لا يوجد أرقام مطابقة للإرسال',
                default => 'لا يوجد زبائن مطابقون للإرسال',
            };

            return response()->json([
                'success' => false,
                'message' => $batchMode
                    ? 'لا متبقّين لهذه الدفعة. اضغط «إعادة التعيين» أو انتهى الجميع.'
                    : $emptyMsg,
                'data' => ['batch' => $stats],
            ], 422);
        }

        $broadcastId = (string) Str::uuid();
        $payload = [
            'message' => $message,
            'only_verified' => $onlyVerified,
            'customer_ids' => $customerIds,
            'batch_mode' => $batchMode,
            'batch_size' => $batchSize,
            'audience' => $audience,
        ];

        dispatch(function () use ($broadcast, $broadcastId, $payload) {
            $broadcast->runBroadcast($broadcastId, $payload);
        })->afterResponse();

        return response()->json([
            'success' => true,
            'message' => 'بدأ إرسال SMS',
            'data' => [
                'id' => $broadcastId,
                'recipients' => $recipients,
                'batch' => $stats,
                'audience' => $audience,
            ],
        ]);
    }

    /** @return list<int>|null */
    private function parseUserIds(mixed $raw): ?array
    {
        if ($raw === null || $raw === '' || $raw === []) {
            return null;
        }
        if (is_string($raw)) {
            $raw = preg_split('/[,\s]+/', $raw) ?: [];
        }
        if (! is_array($raw)) {
            return null;
        }
        $ids = array_values(array_unique(array_filter(array_map('intval', $raw))));

        return $ids === [] ? null : $ids;
    }

    private function ensureStaff(Request $request, string $permission): bool
    {
        $user = $request->user();
        if (! $user) {
            return false;
        }
        if (method_exists($user, 'hasStaffPermission')) {
            return $user->hasStaffPermission($permission);
        }

        return ($user->roll ?? '') === 'Admin';
    }
}
