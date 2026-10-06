<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\CustomerWalletTransaction;
use App\Models\RequestModel;
use App\Models\User;
use App\Services\AdminLimitedViewService;
use App\Services\CustomerWalletService;
use App\Services\WalletTripParties;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminCustomerWalletController extends Controller
{
    private function guard(Request $request, int $id, string $permission): ?JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission($permission)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        if (! User::query()->where('roll', 'Customer')->whereKey($id)->exists()) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }
        if ($deny = AdminLimitedViewService::assertCustomerAccessible($u, $id)) {
            return $deny;
        }
        if (! CustomerWalletService::tablesReady()) {
            return response()->json(['success' => false, 'message' => 'جداول محفظة الراكب غير جاهزة'], 503);
        }

        return null;
    }

    public function show(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->guard($request, $id, 'customers.read')) {
            return $deny;
        }

        $wallet = CustomerWalletService::ensureWallet($id);
        $limit = min(100, max(1, (int) $request->query('limit', 40)));
        $txs = CustomerWalletTransaction::where('user_id', $id)
            ->orderByDesc('id')
            ->limit($limit)
            ->get()
            ->map(fn (CustomerWalletTransaction $tx) => CustomerWalletService::txPayload($tx))
            ->values()
            ->all();
        $txs = WalletTripParties::attach($txs, 'customer');

        return response()->json([
            'success' => true,
            'data' => [
                'wallet' => CustomerWalletService::payload($wallet),
                'transactions' => $txs,
                'can_manage' => $request->user()->hasStaffPermission('customers.wallet'),
            ],
        ]);
    }

    /** سجل عام لكل حركات محافظ الزبائن (دفع رحلات، تعبئة، خصم، تصحيح). */
    public function log(Request $request): JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission('customers.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        if (! CustomerWalletService::tablesReady()) {
            return response()->json(['success' => false, 'message' => 'جداول محفظة الراكب غير جاهزة'], 503);
        }

        $data = $request->validate([
            'type' => 'nullable|string|in:admin_topup,admin_deduct,admin_adjust,trip_payment',
            'search' => 'nullable|string|max:100',
            'from' => 'nullable|date',
            'to' => 'nullable|date',
            'per_page' => 'nullable|integer|min:1|max:200',
        ]);

        $q = CustomerWalletTransaction::query()->orderByDesc('id');
        $scoped = AdminLimitedViewService::scopedCustomerUserIds($u);
        if ($scoped !== null) {
            $q->whereIn('user_id', $scoped);
        }
        if (! empty($data['type'])) {
            $q->where('type', $data['type']);
        }
        if (! empty($data['from'])) {
            $q->where('created_at', '>=', $data['from'].' 00:00:00');
        }
        if (! empty($data['to'])) {
            $q->where('created_at', '<=', $data['to'].' 23:59:59');
        }
        if (! empty($data['search'])) {
            $s = trim($data['search']);
            $like = '%'.$s.'%';
            $userIds = User::query()->withTrashed()
                ->where(function ($qq) use ($like) {
                    $qq->where('firstName', 'like', $like)
                        ->orWhere('lastName', 'like', $like)
                        ->orWhere('number', 'like', $like);
                })
                ->limit(500)
                ->pluck('id');
            $driverIds = \App\Models\Driver::withTrashed()->whereIn('userId', $userIds)->pluck('id');
            $tripIds = RequestModel::withTrashed()->whereIn('driverId', $driverIds)->limit(5000)->pluck('id');
            $q->where(function ($qq) use ($s, $userIds, $tripIds) {
                $qq->whereIn('user_id', $userIds)->orWhereIn('request_id', $tripIds);
                if (ctype_digit(ltrim($s, '#'))) {
                    $qq->orWhere('request_id', (int) ltrim($s, '#'));
                }
            });
        }

        $totals = (clone $q)->reorder()
            ->selectRaw('type, SUM(amount) as total, COUNT(*) as cnt')
            ->groupBy('type')
            ->get()
            ->mapWithKeys(fn ($r) => [$r->type => ['total' => round((float) $r->total, 2), 'count' => (int) $r->cnt]])
            ->all();

        $page = $q->paginate((int) ($data['per_page'] ?? 50));
        $rows = collect($page->items())
            ->map(fn (CustomerWalletTransaction $tx) => CustomerWalletService::txPayload($tx) + [
                'user_id' => (int) $tx->user_id,
                'created_by_user_id' => $tx->created_by_user_id ? (int) $tx->created_by_user_id : null,
            ])
            ->values()
            ->all();
        $rows = WalletTripParties::attach($rows, 'customer');

        $userNames = User::query()->withTrashed()
            ->whereIn('id', array_filter(array_merge(
                array_column($rows, 'user_id'),
                array_column($rows, 'created_by_user_id'),
            )))
            ->get(['id', 'firstName', 'lastName', 'number'])
            ->keyBy('id');
        foreach ($rows as &$r) {
            $cu = $userNames[$r['user_id']] ?? null;
            $r['customer_id'] = $r['customer_id'] ?? $r['user_id'];
            $r['customer_name'] = $r['customer_name'] ?? (WalletTripParties::name($cu) ?? 'زبون #'.$r['user_id']);
            $r['customer_phone'] = $cu->number ?? null;
            $by = $r['created_by_user_id'] ? ($userNames[$r['created_by_user_id']] ?? null) : null;
            $r['created_by_name'] = WalletTripParties::name($by);
        }
        unset($r);

        return response()->json([
            'success' => true,
            'data' => [
                'rows' => $rows,
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
                'totals' => $totals,
            ],
        ]);
    }

    public function topup(Request $request, int $id): JsonResponse
    {
        return $this->mutate($request, $id, 'topup');
    }

    public function deduct(Request $request, int $id): JsonResponse
    {
        return $this->mutate($request, $id, 'deduct');
    }

    public function adjust(Request $request, int $id): JsonResponse
    {
        return $this->mutate($request, $id, 'adjust');
    }

    private function mutate(Request $request, int $id, string $kind): JsonResponse
    {
        if ($deny = $this->guard($request, $id, 'customers.wallet')) {
            return $deny;
        }

        $request->validate([
            'amount' => $kind === 'adjust' ? 'required|numeric|min:0' : 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:500',
        ]);
        $amount = (float) $request->input('amount');
        $note = $request->input('note');
        $by = (int) $request->user()->id;

        try {
            $result = match ($kind) {
                'topup' => CustomerWalletService::adminTopup($id, $amount, $note, $by),
                'deduct' => CustomerWalletService::adminDeduct($id, $amount, $note, $by),
                'adjust' => CustomerWalletService::adminAdjust($id, $amount, $note, $by),
            };
        } catch (\Throwable $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        $message = match ($kind) {
            'topup' => 'تمت تعبئة محفظة الراكب',
            'deduct' => 'تم الخصم من محفظة الراكب',
            'adjust' => 'تم تصحيح رصيد محفظة الراكب',
        };

        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => [
                'wallet' => CustomerWalletService::payload($result['wallet']),
                'transaction' => CustomerWalletService::txPayload($result['tx']),
            ],
        ]);
    }
}
