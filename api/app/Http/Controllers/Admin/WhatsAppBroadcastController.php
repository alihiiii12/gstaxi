<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Services\CustomerWhatsAppBroadcastService;
use App\Services\UltraMsgWhatsAppService;
use App\Models\AppSetting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class WhatsAppBroadcastController extends Controller
{
    public function recipientsCount(Request $request, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $onlyVerified = filter_var(
            $request->query('only_verified', true),
            FILTER_VALIDATE_BOOLEAN,
        );

        $ids = $this->parseCustomerIds($request->query('customer_ids'));

        $batchSize = (int) $request->query('batch_size', CustomerWhatsAppBroadcastService::BATCH_SIZE);
        $stats = $broadcast->batchStats($onlyVerified, $ids, $batchSize);

        return response()->json([
            'success' => true,
            'data' => [
                'recipients' => $stats['total'],
                'batch' => $stats,
                'ultramsg_configured' => app(UltraMsgWhatsAppService::class)->isConfigured(),
                'last_broadcast' => $broadcast->lastBroadcast(),
            ],
        ]);
    }

    public function resetBatch(Request $request, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $broadcast->resetCampaignSent();

        $onlyVerified = filter_var(
            $request->input('only_verified', true),
            FILTER_VALIDATE_BOOLEAN,
        );
        $ids = $this->parseCustomerIds($request->input('customer_ids'));
        $stats = $broadcast->batchStats($onlyVerified, $ids);

        return response()->json([
            'success' => true,
            'message' => 'تم مسح سجل المستلمين السابقين — يمكن البدء من أول دفعة',
            'data' => ['batch' => $stats],
        ]);
    }

    public function lastBroadcast(Request $request, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return response()->json([
            'success' => true,
            'data' => $broadcast->lastBroadcast(),
        ]);
    }

    public function appUpdateSettings(Request $request)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        return response()->json([
            'success' => true,
            'data' => \App\Services\AppUpdatePolicy::config(),
        ]);
    }

    public function updateAppUpdateSettings(Request $request)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $v = $request->validate([
            'min_build' => 'required|integer|min:1|max:999999',
            'download_url' => 'required|url|max:2000',
            'message' => 'nullable|string|max:1000',
            'block_old_login' => 'nullable|boolean',
        ]);

        AppSetting::setValue(
            \App\Services\AppUpdatePolicy::KEY_MIN_BUILD,
            (string) (int) $v['min_build']
        );
        AppSetting::setValue(
            \App\Services\AppUpdatePolicy::KEY_DOWNLOAD_URL,
            trim((string) $v['download_url'])
        );
        AppSetting::setValue(
            \App\Services\AppUpdatePolicy::KEY_MESSAGE,
            trim((string) ($v['message'] ?? ''))
        );
        $block = array_key_exists('block_old_login', $v)
            ? (bool) $v['block_old_login']
            : filter_var($request->input('block_old_login', true), FILTER_VALIDATE_BOOLEAN);
        AppSetting::setValue(
            \App\Services\AppUpdatePolicy::KEY_BLOCK_OLD,
            $block ? '1' : '0'
        );

        return response()->json([
            'success' => true,
            'message' => 'تم حفظ إعدادات تحديث التطبيق',
            'data' => \App\Services\AppUpdatePolicy::config(),
        ]);
    }

    public function status(Request $request, string $id, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $data = $broadcast->readStatus($id);
        if ($data === null) {
            return response()->json(['success' => false, 'message' => 'غير موجود'], 404);
        }

        return response()->json(['success' => true, 'data' => $data]);
    }

    public function cancel(Request $request, string $id, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if (! $broadcast->requestCancel($id)) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن الإلغاء — الإرسال غير جارٍ أو غير موجود',
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم طلب إلغاء الإرسال — يتوقف بعد الرسالة الحالية',
            'data' => $broadcast->readStatus($id),
        ]);
    }

    public function send(Request $request, CustomerWhatsAppBroadcastService $broadcast)
    {
        if (! $this->ensureStaff($request, 'customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        if (! app(UltraMsgWhatsAppService::class)->isConfigured()) {
            return response()->json([
                'success' => false,
                'message' => 'UltraMsg غير مُعدّ — أضف ULTRAMSG_INSTANCE_ID و ULTRAMSG_TOKEN في .env',
            ], 422);
        }

        $validated = $request->validate([
            'message' => 'nullable|string|max:4000',
            'media_url' => 'nullable|url|max:2000',
            'media_type' => 'nullable|in:image,document',
            'media_filename' => 'nullable|string|max:255',
            'send_all' => 'nullable',
            'customer_ids' => 'nullable',
            'batch_mode' => 'nullable',
            'batch_size' => 'nullable|integer|min:1|max:500',
            // حتى ~100MB — يحتاج nginx client_max_body_size و PHP upload_max_filesize
            'media' => 'nullable|file|max:102400|mimes:jpg,jpeg,png,webp,gif,pdf,doc,docx,xls,xlsx,ppt,pptx,txt,zip,apk',
        ]);

        $message = trim((string) ($validated['message'] ?? ''));
        $hasFile = $request->hasFile('media');
        $mediaUrlInput = trim((string) ($validated['media_url'] ?? ''));

        if ($message === '' && ! $hasFile && $mediaUrlInput === '') {
            return response()->json([
                'success' => false,
                'message' => 'أدخل نص الإعلان أو أرفق ملفاً أو ضع رابط تحميل عام',
            ], 422);
        }

        $onlyVerified = filter_var(
            $request->input('only_verified', true),
            FILTER_VALIDATE_BOOLEAN,
        );
        $sendAll = filter_var(
            $request->input('send_all', true),
            FILTER_VALIDATE_BOOLEAN,
        );
        $batchMode = filter_var(
            $request->input('batch_mode', true),
            FILTER_VALIDATE_BOOLEAN,
        );
        $batchSize = (int) ($validated['batch_size'] ?? CustomerWhatsAppBroadcastService::BATCH_SIZE);
        if ($batchSize < 1) {
            $batchSize = CustomerWhatsAppBroadcastService::BATCH_SIZE;
        }

        $customerIds = $sendAll ? null : $this->parseCustomerIds($request->input('customer_ids'));
        if (! $sendAll && ($customerIds === null || $customerIds === [])) {
            return response()->json([
                'success' => false,
                'message' => 'حدّد مشتركين أو اختر «الكل»',
            ], 422);
        }

        $mediaUrl = null;
        $mediaType = null;
        $mediaFilename = null;

        if ($hasFile) {
            $file = $request->file('media');
            $mime = (string) $file->getMimeType();
            $ext = strtolower((string) $file->getClientOriginalExtension());
            $isImage = str_starts_with($mime, 'image/')
                || in_array($ext, ['jpg', 'jpeg', 'png', 'webp', 'gif'], true);
            $mediaType = $isImage ? 'image' : 'document';
            $mediaFilename = $file->getClientOriginalName();

            $path = $file->storeAs(
                'whatsapp-broadcasts/'.now()->format('Y/m'),
                Str::uuid()->toString().'_'.preg_replace('/[^A-Za-z0-9._-]+/', '_', $mediaFilename),
                'public',
            );

            $mediaUrl = url(Storage::disk('public')->url($path));
            if (! str_starts_with($mediaUrl, 'http')) {
                $mediaUrl = rtrim((string) config('app.url'), '/').'/'.ltrim($mediaUrl, '/');
            }
        } elseif ($mediaUrlInput !== '') {
            $mediaUrl = $mediaUrlInput;
            $mediaType = $validated['media_type']
                ?? (preg_match('/\.(jpe?g|png|webp|gif)(\?|$)/i', $mediaUrlInput) ? 'image' : 'document');
            $mediaFilename = trim((string) ($validated['media_filename'] ?? ''));
            if ($mediaFilename === '') {
                $mediaFilename = basename(parse_url($mediaUrlInput, PHP_URL_PATH) ?: 'file');
            }
        }

        $stats = $broadcast->batchStats($onlyVerified, $customerIds, $batchSize);
        $recipients = $batchMode ? $stats['next_batch'] : $stats['total'];
        if ($recipients < 1) {
            return response()->json([
                'success' => false,
                'message' => $batchMode
                    ? 'لا متبقّين لهذه الدفعة. اضغط «إعادة التعيين» للبدء من جديد أو انتهى الجميع.'
                    : 'لا يوجد زبائن مطابقون للإرسال',
                'data' => ['batch' => $stats],
            ], 422);
        }

        $broadcastId = (string) Str::uuid();
        $broadcast->writeStatus($broadcastId, [
            'status' => 'queued',
            'total' => $recipients,
            'sent' => 0,
            'failed' => 0,
            'batch_mode' => $batchMode,
            'message_preview' => mb_substr($message, 0, 120),
            'has_media' => $mediaUrl !== null,
            'media_type' => $mediaType,
            'created_at' => now()->toIso8601String(),
            'created_by' => $request->user()?->id,
        ]);

        $payload = [
            'message' => $message,
            'media_url' => $mediaUrl,
            'media_type' => $mediaType,
            'media_filename' => $mediaFilename,
            'only_verified' => $onlyVerified,
            'customer_ids' => $customerIds,
            'batch_mode' => $batchMode,
            'batch_size' => $batchSize,
        ];

        dispatch(function () use ($broadcast, $broadcastId, $payload) {
            $broadcast->runBroadcast($broadcastId, $payload);
        })->afterResponse();

        $msg = $batchMode
            ? "بدأ إرسال دفعة من {$recipients} مستلم (تخطي من أُرسل لهم سابقاً)"
            : "بدأ الإرسال إلى {$recipients} زبون عبر واتساب";

        return response()->json([
            'success' => true,
            'message' => $msg,
            'data' => [
                'broadcast_id' => $broadcastId,
                'recipients' => $recipients,
                'batch' => $stats,
            ],
        ]);
    }

    /**
     * @return list<int>|null
     */
    private function parseCustomerIds(mixed $raw): ?array
    {
        if ($raw === null || $raw === '' || $raw === []) {
            return null;
        }
        if (is_string($raw)) {
            $raw = array_filter(array_map('trim', explode(',', $raw)));
        }
        if (! is_array($raw)) {
            return null;
        }
        $ids = [];
        foreach ($raw as $v) {
            $n = (int) $v;
            if ($n > 0) {
                $ids[] = $n;
            }
        }

        return $ids === [] ? null : array_values(array_unique($ids));
    }

    private function ensureStaff(Request $request, string $permission): bool
    {
        $u = $request->user();

        return $u && $u->hasStaffPermission($permission);
    }
}
