<?php

namespace App\Http\Controllers;

use App\Models\Driver;
use App\Models\DriverWalletTransaction;
use App\Services\DriverWalletService;
use App\Services\WalletTripParties;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DriverWalletController extends Controller
{
    private function driverOrForbid(Request $request): Driver|JsonResponse
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        $driver = Driver::where('userId', $user->id)->first();
        if (! $driver) {
            return response()->json(['success' => false, 'message' => 'Driver profile not found'], 404);
        }

        return $driver;
    }

    public function me(Request $request): JsonResponse
    {
        $driver = $this->driverOrForbid($request);
        if ($driver instanceof JsonResponse) {
            return $driver;
        }
        if (! DriverWalletService::tablesReady()) {
            return response()->json([
                'success' => true,
                'data' => [
                    'wallet' => [
                        'driver_id' => (int) $driver->id,
                        'balance' => 0,
                        'currency' => 'SYP',
                    ],
                    'transactions' => [],
                ],
            ]);
        }

        $wallet = DriverWalletService::ensureWallet((int) $driver->id);
        $limit = min(100, max(1, (int) $request->query('limit', 50)));
        $txs = DriverWalletTransaction::where('driver_id', $driver->id)
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
                'can_withdraw' => false,
                'withdraw_note' => 'السحب يتم حصراً بواسطة الإدارة',
            ],
        ]);
    }
}
