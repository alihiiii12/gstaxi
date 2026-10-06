<?php

namespace App\Services;

use App\Models\DriverWallet;
use App\Models\DriverWalletTransaction;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

class DriverWalletService
{
    public static function tablesReady(): bool
    {
        try {
            return Schema::hasTable('driver_wallets')
                && Schema::hasTable('driver_wallet_transactions');
        } catch (\Throwable $e) {
            return false;
        }
    }

    public static function ensureWallet(int $driverId): DriverWallet
    {
        $wallet = DriverWallet::where('driver_id', $driverId)->first();
        if ($wallet) {
            return $wallet;
        }

        return DriverWallet::create([
            'driver_id' => $driverId,
            'balance' => 0,
            'currency' => 'SYP',
        ]);
    }

    /**
     * @return array{wallet: DriverWallet, tx: DriverWalletTransaction}
     */
    public static function credit(
        int $driverId,
        float $amount,
        string $type,
        ?string $note = null,
        ?int $requestId = null,
        ?int $discountId = null,
        ?int $createdByUserId = null,
    ): array {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('مبلغ الإضافة يجب أن يكون موجباً');
        }

        return DB::transaction(function () use ($driverId, $amount, $type, $note, $requestId, $discountId, $createdByUserId) {
            if ($type === DriverWalletTransaction::TYPE_COUPON && $requestId) {
                $exists = DriverWalletTransaction::where('type', DriverWalletTransaction::TYPE_COUPON)
                    ->where('request_id', $requestId)
                    ->exists();
                if ($exists) {
                    $wallet = self::ensureWallet($driverId);
                    $tx = DriverWalletTransaction::where('type', DriverWalletTransaction::TYPE_COUPON)
                        ->where('request_id', $requestId)
                        ->first();

                    return ['wallet' => $wallet, 'tx' => $tx];
                }
            }

            $wallet = self::ensureWallet($driverId);
            $locked = DriverWallet::whereKey($wallet->id)->lockForUpdate()->first();
            $newBal = round((float) $locked->balance + $amount, 2);
            $locked->balance = $newBal;
            $locked->save();

            $tx = DriverWalletTransaction::create([
                'driver_wallet_id' => $locked->id,
                'driver_id' => $driverId,
                'type' => $type,
                'amount' => round($amount, 2),
                'balance_after' => $newBal,
                'request_id' => $requestId,
                'discount_id' => $discountId,
                'note' => $note,
                'created_by_user_id' => $createdByUserId,
            ]);

            return ['wallet' => $locked->fresh(), 'tx' => $tx];
        });
    }

    /**
     * سحب من الأدمن فقط — مبلغ موجب يُخصم من الرصيد.
     *
     * @return array{wallet: DriverWallet, tx: DriverWalletTransaction}
     */
    public static function adminWithdraw(
        int $driverId,
        float $amount,
        ?string $note = null,
        ?int $createdByUserId = null,
    ): array {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('مبلغ السحب يجب أن يكون موجباً');
        }

        return DB::transaction(function () use ($driverId, $amount, $note, $createdByUserId) {
            $wallet = self::ensureWallet($driverId);
            $locked = DriverWallet::whereKey($wallet->id)->lockForUpdate()->first();
            $bal = (float) $locked->balance;
            if ($amount > $bal + 0.001) {
                throw new \RuntimeException('الرصيد غير كافٍ للسحب');
            }
            $newBal = round($bal - $amount, 2);
            $locked->balance = $newBal;
            $locked->save();

            $tx = DriverWalletTransaction::create([
                'driver_wallet_id' => $locked->id,
                'driver_id' => $driverId,
                'type' => DriverWalletTransaction::TYPE_WITHDRAW,
                'amount' => round(-$amount, 2),
                'balance_after' => $newBal,
                'note' => $note ?: 'سحب بواسطة الإدارة',
                'created_by_user_id' => $createdByUserId,
            ]);

            return ['wallet' => $locked->fresh(), 'tx' => $tx];
        });
    }

    /**
     * مكافأة من الأدمن.
     */
    public static function adminReward(
        int $driverId,
        float $amount,
        ?string $note = null,
        ?int $createdByUserId = null,
    ): array {
        return self::credit(
            $driverId,
            $amount,
            DriverWalletTransaction::TYPE_REWARD,
            $note ?: 'مكافأة من الإدارة',
            null,
            null,
            $createdByUserId,
        );
    }

    /**
     * مخالفة — خصم من المحفظة (يسمح برصيد سالب).
     *
     * @return array{wallet: DriverWallet, tx: DriverWalletTransaction}
     */
    public static function adminViolation(
        int $driverId,
        float $amount,
        ?string $note = null,
        ?int $createdByUserId = null,
    ): array {
        if ($amount <= 0) {
            throw new \InvalidArgumentException('مبلغ المخالفة يجب أن يكون موجباً');
        }

        return DB::transaction(function () use ($driverId, $amount, $note, $createdByUserId) {
            $wallet = self::ensureWallet($driverId);
            $locked = DriverWallet::whereKey($wallet->id)->lockForUpdate()->first();
            $newBal = round((float) $locked->balance - $amount, 2);
            $locked->balance = $newBal;
            $locked->save();

            $tx = DriverWalletTransaction::create([
                'driver_wallet_id' => $locked->id,
                'driver_id' => $driverId,
                'type' => DriverWalletTransaction::TYPE_VIOLATION,
                'amount' => round(-$amount, 2),
                'balance_after' => $newBal,
                'note' => $note ?: 'مخالفة من الإدارة',
                'created_by_user_id' => $createdByUserId,
            ]);

            return ['wallet' => $locked->fresh(), 'tx' => $tx];
        });
    }

    public static function creditCouponCompensation(
        int $driverId,
        int $requestId,
        ?int $discountId,
        float $deduction,
    ): void {
        if (! self::tablesReady() || $deduction <= 0 || $driverId <= 0) {
            return;
        }
        try {
            self::credit(
                $driverId,
                $deduction,
                DriverWalletTransaction::TYPE_COUPON,
                'تعويض خصم كوبون الزبون',
                $requestId,
                $discountId,
                null,
            );
        } catch (\Throwable $e) {
            Log::warning('[driver_wallet_coupon] '.$e->getMessage(), [
                'driver_id' => $driverId,
                'request_id' => $requestId,
            ]);
        }
    }

    public static function payload(DriverWallet $wallet): array
    {
        return [
            'driver_id' => (int) $wallet->driver_id,
            'balance' => round((float) $wallet->balance, 2),
            'currency' => $wallet->currency ?: 'SYP',
            'updated_at' => optional($wallet->updated_at)?->toIso8601String(),
        ];
    }

    public static function txPayload(DriverWalletTransaction $tx): array
    {
        return [
            'id' => (int) $tx->id,
            'type' => $tx->type,
            'type_label' => DriverWalletTransaction::typeLabel((string) $tx->type),
            'amount' => round((float) $tx->amount, 2),
            'balance_after' => round((float) $tx->balance_after, 2),
            'request_id' => $tx->request_id ? (int) $tx->request_id : null,
            'discount_id' => $tx->discount_id ? (int) $tx->discount_id : null,
            'note' => $tx->note,
            'created_at' => optional($tx->created_at)?->toIso8601String(),
        ];
    }
}
