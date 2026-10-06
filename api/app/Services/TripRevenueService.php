<?php

namespace App\Services;

use App\Models\RequestModel;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Schema;

/**
 * إيراد منصة موحّد: رحلات Finished فقط، تاريخ الإتمام = requests.updated_at.
 */
class TripRevenueService
{
    public static function hasBillingColumns(): bool
    {
        static $cached = null;
        if ($cached === null) {
            $cached = Schema::hasColumn('requests', 'billing_kind');
        }

        return $cached;
    }

    public static function finishedRevenueScope(): \Closure
    {
        return function (Builder $q) {
            $q->where('status', RequestModel::STATUS_FINISHED);
            if (! static::hasBillingColumns()) {
                return;
            }
            $q->where(function ($qq) {
                $qq->where(function ($a) {
                    $a->whereNull('billing_kind')
                        ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
                })->orWhere(function ($q2) {
                    $q2->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER)
                        ->where(function ($q3) {
                            $q3->whereNull('free_meter_counts_for_revenue')
                                ->orWhere('free_meter_counts_for_revenue', true);
                        });
                });
            });
        };
    }

    public static function tripAmount(RequestModel $request): float
    {
        return CategoryTripFareService::revenueAmountForRequest($request);
    }

    /** @return float */
    public static function sumRevenueBetween(Carbon $from, Carbon $to): float
    {
        $revenue = 0.0;
        RequestModel::query()
            ->where(static::finishedRevenueScope())
            ->whereBetween('updated_at', [$from, $to])
            ->with(['history', 'carType'])
            ->chunkById(150, function ($rows) use (&$revenue) {
                foreach ($rows as $row) {
                    $revenue += static::tripAmount($row);
                }
            });

        return round($revenue, 2);
    }

    public static function countFinishedBetween(Carbon $from, Carbon $to): int
    {
        return RequestModel::query()
            ->where('status', RequestModel::STATUS_FINISHED)
            ->whereBetween('updated_at', [$from, $to])
            ->count();
    }
}
