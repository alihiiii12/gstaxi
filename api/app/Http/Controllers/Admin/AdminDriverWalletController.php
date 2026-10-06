<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Driver;
use App\Models\DriverWalletTransaction;
use App\Services\AdminLimitedViewService;
use App\Services\DriverWalletService;
use App\Services\WalletTripParties;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminDriverWalletController extends Controller
{
    private function forbidUnlessDriversWrite(Request $request): ?JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission('drivers.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return null;
    }

    private function forbidUnlessDriversRead(Request $request): ?JsonResponse
    {
        $u = $request->user();
        if (! $u || (! $u->hasStaffPermission('drivers.read') && ! $u->hasStaffPermission('drivers.write'))) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return null;
    }

    public function show(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversRead($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }
        if (! DriverWalletService::tablesReady()) {
            return response()->json([
                'success' => false,
                'message' => 'جداول المحفظة غير جاهزة',
            ], 503);
        }

        Driver::findOrFail($id);
        $wallet = DriverWalletService::ensureWallet($id);
        $limit = min(100, max(1, (int) $request->query('limit', 40)));
        $txs = DriverWalletTransaction::where('driver_id', $id)
            ->orderByDesc('id')
            ->limit($limit)
            ->get()
            ->map(fn (DriverWalletTransaction $tx) => DriverWalletService::txPayload($tx))
            ->values()
            ->all();
        $txs = WalletTripParties::attach($txs, 'driver');

        return response()->json([
            'success' => true,
            'data' => [
                'wallet' => DriverWalletService::payload($wallet),
                'transactions' => $txs,
            ],
        ]);
    }

    public function reward(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }
        if (! DriverWalletService::tablesReady()) {
            return response()->json([
                'success' => false,
                'message' => 'جداول المحفظة غير جاهزة',
            ], 503);
        }

        $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:500',
        ]);

        Driver::findOrFail($id);

        try {
            $result = DriverWalletService::adminReward(
                $id,
                (float) $request->input('amount'),
                $request->input('note'),
                (int) $request->user()->id,
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تمت إضافة المكافأة إلى محفظة السائق',
            'data' => [
                'wallet' => DriverWalletService::payload($result['wallet']),
                'transaction' => DriverWalletService::txPayload($result['tx']),
            ],
        ]);
    }

    public function withdraw(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }
        if (! DriverWalletService::tablesReady()) {
            return response()->json([
                'success' => false,
                'message' => 'جداول المحفظة غير جاهزة',
            ], 503);
        }

        $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:500',
        ]);

        Driver::findOrFail($id);

        try {
            $result = DriverWalletService::adminWithdraw(
                $id,
                (float) $request->input('amount'),
                $request->input('note'),
                (int) $request->user()->id,
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم السحب من محفظة السائق',
            'data' => [
                'wallet' => DriverWalletService::payload($result['wallet']),
                'transaction' => DriverWalletService::txPayload($result['tx']),
            ],
        ]);
    }

    public function violation(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }
        if (! DriverWalletService::tablesReady()) {
            return response()->json([
                'success' => false,
                'message' => 'جداول المحفظة غير جاهزة',
            ], 503);
        }

        $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'note' => 'nullable|string|max:500',
        ]);

        Driver::findOrFail($id);

        try {
            $result = DriverWalletService::adminViolation(
                $id,
                (float) $request->input('amount'),
                $request->input('note') ?: 'مخالفة',
                (int) $request->user()->id,
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'تم تسجيل المخالفة وخصم المبلغ من المحفظة',
            'data' => [
                'wallet' => DriverWalletService::payload($result['wallet']),
                'transaction' => DriverWalletService::txPayload($result['tx']),
            ],
        ]);
    }
}
