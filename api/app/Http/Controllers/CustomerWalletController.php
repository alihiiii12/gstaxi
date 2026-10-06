<?php

namespace App\Http\Controllers;

use App\Models\CustomerWalletTransaction;
use App\Models\Driver;
use App\Models\DriverNotification;
use App\Models\RequestModel;
use App\Services\CustomerWalletService;
use App\Services\FcmPushService;
use App\Services\WalletTripParties;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CustomerWalletController extends Controller
{
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        if (! CustomerWalletService::tablesReady()) {
            return response()->json([
                'success' => true,
                'data' => [
                    'wallet' => ['user_id' => (int) $user->id, 'balance' => 0, 'currency' => 'SYP'],
                    'transactions' => [],
                ],
            ]);
        }

        $wallet = CustomerWalletService::ensureWallet((int) $user->id);
        $limit = min(100, max(1, (int) $request->query('limit', 50)));
        $txs = CustomerWalletTransaction::where('user_id', $user->id)
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
                'topup_note' => 'تعبئة الرصيد تتم عن طريق الإدارة',
            ],
        ]);
    }

    /** حالة دفع رحلة — للراكب صاحب الطلب أو السائق المعيَّن. */
    public function paymentStatus(Request $request, $requestId): JsonResponse
    {
        $user = $request->user();
        $req = RequestModel::find($requestId);
        if (! $user || ! $req) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        }
        if (! CustomerWalletService::tablesReady()) {
            return response()->json(['success' => false, 'message' => 'المحفظة غير مفعّلة'], 503);
        }

        $isCustomer = $user->roll === 'Customer' && (int) $req->userId === (int) $user->id;
        $isDriver = false;
        if ($user->roll === 'Driver') {
            $driver = Driver::where('userId', $user->id)->first();
            $isDriver = $driver && (int) $driver->id === (int) $req->driverId;
        }
        if (! $isCustomer && ! $isDriver) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $balance = $isCustomer
            ? round((float) CustomerWalletService::ensureWallet((int) $user->id)->balance, 2)
            : null;

        return response()->json([
            'success' => true,
            'data' => CustomerWalletService::paymentPayload($req, $balance),
        ]);
    }

    public function pay(Request $request, $requestId): JsonResponse
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }
        if (! CustomerWalletService::tablesReady()) {
            return response()->json(['success' => false, 'message' => 'المحفظة غير مفعّلة'], 503);
        }
        $data = $request->validate([
            'method' => 'required|string|in:wallet,cash',
        ]);

        try {
            $out = CustomerWalletService::payTrip((int) $requestId, (int) $user->id, $data['method']);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            return response()->json(['success' => false, 'message' => 'Request not found'], 404);
        } catch (\DomainException $e) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $req = $out['request'];
        $balance = round((float) CustomerWalletService::ensureWallet((int) $user->id)->balance, 2);
        $payload = CustomerWalletService::paymentPayload($req, $balance);

        if ($out['error'] !== null) {
            return response()->json([
                'success' => false,
                'code' => 'PAYMENT_NOT_ALLOWED',
                'message' => $out['error'],
                'data' => $payload,
            ], 422);
        }

        if ($out['settled_now']) {
            $this->notifyDriverOfPayment($req, $payload);
        }

        $message = match ($payload['method']) {
            CustomerWalletService::METHOD_WALLET => 'تم دفع الأجرة كاملة من المحفظة',
            CustomerWalletService::METHOD_MIXED => 'تم دفع '.self::fmt($payload['wallet_paid']).' من المحفظة — الباقي '.self::fmt($payload['cash_due']).' كاش',
            default => $data['method'] === 'wallet'
                ? 'رصيد المحفظة غير كافٍ — ادفع '.self::fmt($payload['cash_due']).' كاش'
                : 'تم اختيار الدفع كاش',
        };

        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => $payload,
        ]);
    }

    private function notifyDriverOfPayment(RequestModel $req, array $payload): void
    {
        $driver = (int) $req->driverId > 0 ? Driver::find($req->driverId) : null;
        if (! $driver || ! $driver->userId) {
            return;
        }
        $body = match ($payload['method']) {
            CustomerWalletService::METHOD_WALLET => 'دفع الراكب الأجرة كاملة من المحفظة ('.self::fmt($payload['wallet_paid']).') — أُضيفت لمحفظتك، لا تستلم كاش',
            CustomerWalletService::METHOD_MIXED => 'دُفع '.self::fmt($payload['wallet_paid']).' من محفظة الراكب — استلم '.self::fmt($payload['cash_due']).' كاش',
            default => 'الدفع كاش — استلم '.self::fmt($payload['cash_due']),
        };
        $title = 'طريقة دفع رحلة #'.$req->id;
        $data = [
            'kind' => 'trip.payment',
            'request_id' => (string) $req->id,
            'method' => (string) $payload['method'],
            'wallet_paid' => (string) $payload['wallet_paid'],
            'cash_due' => (string) $payload['cash_due'],
        ];
        try {
            DriverNotification::create([
                'user_id' => (int) $driver->userId,
                'title' => $title,
                'body' => $body,
                'kind' => 'trip.payment',
                'reference_type' => 'request',
                'reference_id' => (int) $req->id,
                'payload' => $data,
            ]);
        } catch (\Throwable $e) {
        }
        try {
            app(FcmPushService::class)->sendToUserId((int) $driver->userId, $title, $body, $data);
        } catch (\Throwable $e) {
        }
    }

    private static function fmt(float $v): string
    {
        return number_format($v, $v == floor($v) ? 0 : 2).' ل.س';
    }
}
