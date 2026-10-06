<?php

namespace App\Services;

use App\Models\CustomerWallet;
use App\Models\CustomerWalletTransaction;
use App\Models\DriverWalletTransaction;
use App\Models\RequestHistory;
use App\Models\RequestModel;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CustomerWalletService
{
    public const METHOD_CASH = 'cash';

    public const METHOD_WALLET = 'wallet';

    public const METHOD_MIXED = 'mixed';

    /** بعد هذه المدة من نهاية الرحلة بدون اختيار تُعتبر الرحلة كاش. */
    public const CHOICE_WINDOW_MINUTES = 10;

    public static function tablesReady(): bool
    {
        try {
            return Schema::hasTable('customer_wallets')
                && Schema::hasTable('customer_wallet_transactions')
                && Schema::hasColumn('requests', 'payment_settled_at');
        } catch (\Throwable $e) {
            return false;
        }
    }

    public static function ensureWallet(int $userId): CustomerWallet
    {
        $wallet = CustomerWallet::where('user_id', $userId)->first();
        if ($wallet) {
            return $wallet;
        }

        return CustomerWallet::create([
            'user_id' => $userId,
            'balance' => 0,
            'currency' => 'SYP',
        ]);
    }

    /**
     * @return array{wallet: CustomerWallet, tx: CustomerWalletTransaction}
     */
    private static function applyDelta(
        int $userId,
        float $delta,
        string $type,
        ?string $note,
        ?int $requestId,
        ?int $createdByUserId,
        bool $allowNegative = false,
    ): array {
        return DB::transaction(function () use ($userId, $delta, $type, $note, $requestId, $createdByUserId, $allowNegative) {
            $wallet = self::ensureWallet($userId);
            $locked = CustomerWallet::whereKey($wallet->id)->lockForUpdate()->first();
            $newBal = round((float) $locked->balance + $delta, 2);
            if (! $allowNegative && $newBal < -0.001) {
                throw new \RuntimeException('الرصيد غير كافٍ');
            }
            $locked->balance = $newBal;
            $locked->save();

            $tx = CustomerWalletTransaction::create([
                'customer_wallet_id' => $locked->id,
                'user_id' => $userId,
                'type' => $type,
                'amount' => round($delta, 2),
                'balance_after' => $newBal,
                'request_id' => $requestId,
                'note' => $note,
                'created_by_user_id' => $createdByUserId,
            ]);

            return ['wallet' => $locked->fresh(), 'tx' => $tx];
        });
    }

    public static function adminTopup(int $userId, float $amount, ?string $note, ?int $by): array
    {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('مبلغ التعبئة يجب أن يكون موجباً');
        }

        return self::applyDelta($userId, $amount, CustomerWalletTransaction::TYPE_TOPUP, $note ?: 'تعبئة رصيد من الإدارة', null, $by);
    }

    public static function adminDeduct(int $userId, float $amount, ?string $note, ?int $by): array
    {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('مبلغ الخصم يجب أن يكون موجباً');
        }

        return self::applyDelta($userId, -$amount, CustomerWalletTransaction::TYPE_DEDUCT, $note ?: 'خصم من الإدارة', null, $by);
    }

    /** تصحيح: ضبط الرصيد على قيمة محددة (تُسجَّل الفروقات كحركة). */
    public static function adminAdjust(int $userId, float $newBalance, ?string $note, ?int $by): array
    {
        if ($newBalance < 0) {
            throw new \InvalidArgumentException('الرصيد الجديد لا يمكن أن يكون سالباً');
        }

        return DB::transaction(function () use ($userId, $newBalance, $note, $by) {
            $wallet = self::ensureWallet($userId);
            $locked = CustomerWallet::whereKey($wallet->id)->lockForUpdate()->first();
            $delta = round($newBalance - (float) $locked->balance, 2);
            if (abs($delta) < 0.005) {
                throw new \RuntimeException('الرصيد مطابق للقيمة المطلوبة');
            }

            return self::applyDelta($userId, $delta, CustomerWalletTransaction::TYPE_ADJUST, $note ?: 'تصحيح رصيد من الإدارة', null, $by);
        });
    }

    public static function finalCostFor(RequestModel $req): float
    {
        $hist = RequestHistory::where('requestId', $req->id)->first();

        return round(max(0.0, (float) ($hist->finalCost ?? 0)), 2);
    }

    /** تُستدعى عند إنهاء رحلة طلب التطبيق: تبدأ نافذة اختيار الدفع. */
    public static function resetForFinishedTrip(RequestModel $req, float $finalCost): void
    {
        if (! self::tablesReady()) {
            return;
        }
        $req->payment_method = null;
        $req->wallet_paid_amount = 0;
        $req->cash_due_amount = round(max(0.0, $finalCost), 2);
        $req->payment_settled_at = null;
        if ($finalCost <= 0.0) {
            $req->payment_method = self::METHOD_CASH;
            $req->payment_settled_at = now();
        }
    }

    public static function choiceDeadline(RequestModel $req): ?Carbon
    {
        $ended = $req->trip_ended_at ?? $req->updated_at;

        return $ended ? Carbon::parse($ended)->addMinutes(self::CHOICE_WINDOW_MINUTES) : null;
    }

    public static function isChoiceOpen(RequestModel $req): bool
    {
        if ($req->status !== RequestModel::STATUS_FINISHED) {
            return false;
        }
        if ($req->billing_kind === RequestModel::BILLING_KIND_FREE_METER) {
            return false;
        }
        if ($req->payment_settled_at !== null) {
            return false;
        }
        $deadline = self::choiceDeadline($req);

        return $deadline === null || now()->lt($deadline);
    }

    /**
     * دفع أجرة رحلة: من المحفظة (جزئياً إن لم يكفِ الرصيد) أو كاش.
     * المبلغ المدفوع من المحفظة يُضاف كاملاً إلى محفظة السائق.
     *
     * @return array{request: RequestModel, error: ?string, settled_now: bool}
     */
    public static function payTrip(int $requestId, int $customerUserId, string $method): array
    {
        return DB::transaction(function () use ($requestId, $customerUserId, $method) {
            $req = RequestModel::whereKey($requestId)->lockForUpdate()->firstOrFail();
            if ((int) $req->userId !== $customerUserId) {
                throw new \DomainException('Forbidden');
            }
            if ($req->payment_settled_at !== null) {
                return ['request' => $req, 'error' => null, 'settled_now' => false];
            }
            if (! self::isChoiceOpen($req)) {
                if ($req->status !== RequestModel::STATUS_FINISHED
                    || $req->billing_kind === RequestModel::BILLING_KIND_FREE_METER) {
                    return ['request' => $req, 'error' => 'لا يمكن الدفع لهذه الرحلة في حالتها الحالية', 'settled_now' => false];
                }
                $req->payment_method = self::METHOD_CASH;
                $req->wallet_paid_amount = 0;
                $req->cash_due_amount = self::finalCostFor($req);
                $req->payment_settled_at = now();
                $req->save();

                return ['request' => $req, 'error' => 'انتهت مهلة اختيار طريقة الدفع — تُحسب الرحلة كاش', 'settled_now' => false];
            }

            $finalCost = self::finalCostFor($req);
            $paid = 0.0;

            if ($method === self::METHOD_WALLET && $finalCost > 0) {
                $wallet = self::ensureWallet($customerUserId);
                $locked = CustomerWallet::whereKey($wallet->id)->lockForUpdate()->first();
                $paid = round(min(max(0.0, (float) $locked->balance), $finalCost), 2);
                if ($paid > 0) {
                    self::applyDelta(
                        $customerUserId,
                        -$paid,
                        CustomerWalletTransaction::TYPE_TRIP_PAYMENT,
                        'أجرة رحلة #'.$req->id,
                        (int) $req->id,
                        null,
                    );
                    if ((int) $req->driverId > 0 && DriverWalletService::tablesReady()) {
                        DriverWalletService::credit(
                            (int) $req->driverId,
                            $paid,
                            DriverWalletTransaction::TYPE_TRIP_WALLET,
                            'أجرة رحلة #'.$req->id.' من محفظة الراكب',
                            (int) $req->id,
                        );
                    }
                }
            }

            $cashDue = round(max(0.0, $finalCost - $paid), 2);
            $req->payment_method = $paid <= 0
                ? self::METHOD_CASH
                : ($cashDue > 0 ? self::METHOD_MIXED : self::METHOD_WALLET);
            $req->wallet_paid_amount = $paid;
            $req->cash_due_amount = $cashDue;
            $req->payment_settled_at = now();
            $req->save();

            return ['request' => $req, 'error' => null, 'settled_now' => true];
        });
    }

    public static function paymentPayload(RequestModel $req, ?float $walletBalance = null): array
    {
        $finalCost = self::finalCostFor($req);
        $open = self::isChoiceOpen($req);
        $settled = $req->payment_settled_at !== null;

        if ($settled) {
            $method = (string) ($req->payment_method ?: self::METHOD_CASH);
            $walletPaid = round((float) ($req->wallet_paid_amount ?? 0), 2);
            $cashDue = round((float) ($req->cash_due_amount ?? $finalCost), 2);
        } elseif ($open) {
            $method = null;
            $walletPaid = 0.0;
            $cashDue = $finalCost;
        } else {
            $method = self::METHOD_CASH;
            $walletPaid = 0.0;
            $cashDue = $finalCost;
        }

        $deadline = self::choiceDeadline($req);

        return [
            'request_id' => (int) $req->id,
            'status' => $open ? 'pending' : 'settled',
            'method' => $method,
            'final_cost' => $finalCost,
            'wallet_paid' => $walletPaid,
            'cash_due' => $cashDue,
            'choice_open' => $open,
            'choice_deadline_at' => $open && $deadline ? $deadline->toIso8601String() : null,
            'wallet_balance' => $walletBalance,
            'currency' => 'SYP',
        ];
    }

    public static function payload(CustomerWallet $wallet): array
    {
        return [
            'user_id' => (int) $wallet->user_id,
            'balance' => round((float) $wallet->balance, 2),
            'currency' => $wallet->currency ?: 'SYP',
            'updated_at' => optional($wallet->updated_at)?->toIso8601String(),
        ];
    }

    public static function txPayload(CustomerWalletTransaction $tx): array
    {
        return [
            'id' => (int) $tx->id,
            'type' => $tx->type,
            'type_label' => CustomerWalletTransaction::typeLabel((string) $tx->type),
            'amount' => round((float) $tx->amount, 2),
            'balance_after' => round((float) $tx->balance_after, 2),
            'request_id' => $tx->request_id ? (int) $tx->request_id : null,
            'note' => $tx->note,
            'created_at' => optional($tx->created_at)?->toIso8601String(),
        ];
    }
}
