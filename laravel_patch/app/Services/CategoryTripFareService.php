<?php

/**
 * انسخ إلى app/Services/CategoryTripFareService.php
 * يُستخدم من TripRevenueService و RequestController::finishTrip
 */

namespace App\Services;

use App\Models\CarType;
use App\Models\RequestModel;

class CategoryTripFareService
{
    public static function fareFromCategory(?CarType $carType, float $km, ?float $durationMinutes): ?float
    {
        if (! $carType || $km <= 0) {
            return null;
        }
        $openP = (float) ($carType->openPrice ?? $carType->open_price ?? 0);
        $kmP = (float) ($carType->KMPrice ?? $carType->km_price ?? 0);
        $minP = (float) ($carType->timePrice ?? $carType->time_price ?? 0);
        $fare = $openP > 0 ? $openP : 0.0;
        if ($kmP > 0) {
            $fare += $km * $kmP;
        }
        if ($durationMinutes !== null && $durationMinutes > 0 && $minP > 0) {
            $fare += $durationMinutes * $minP;
        }

        return $fare > 0 ? round($fare, 2) : null;
    }

    public static function bookedFareLiras(RequestModel $request, ?CarType $carType = null): ?float
    {
        if (self::isFreeMeter($request)) {
            return null;
        }

        $predicted = (float) ($request->predectedCost ?? 0);
        if ($predicted > 0) {
            return round($predicted, 2);
        }

        $carType = $carType ?? $request->carType;
        if (! $carType && $request->carTypeId) {
            $carType = CarType::find($request->carTypeId);
        }
        if (! $carType) {
            return null;
        }

        $km = self::tripKmForFare($request);
        $mins = $request->estimated_duration_minutes !== null
            ? (float) $request->estimated_duration_minutes
            : null;

        return self::fareFromCategory($carType, $km, $mins);
    }

    public static function revenueAmountForRequest(RequestModel $request): float
    {
        if (! RequestModel::countsTowardPlatformRevenue($request)) {
            return 0.0;
        }

        if (self::isAppRequest($request)) {
            $booked = self::bookedFareLiras($request);
            if ($booked !== null && $booked > 0) {
                return $booked;
            }
        }

        $history = $request->relationLoaded('history')
            ? $request->history
            : $request->history()->first();
        $fromHistory = $history ? (float) $history->finalCost : 0.0;

        return $fromHistory > 0 ? round($fromHistory, 2) : 0.0;
    }

    public static function finalizeAppRequestCost(RequestModel $request, ?CarType $carType = null): float
    {
        $booked = self::bookedFareLiras($request, $carType);

        return $booked !== null && $booked > 0 ? $booked : 0.0;
    }

    public static function isAppRequest(RequestModel $request): bool
    {
        if (self::isFreeMeter($request)) {
            return false;
        }
        if ($request->is_app_request === true) {
            return true;
        }
        $bk = strtolower(trim((string) ($request->billing_kind ?? '')));

        return $bk === '' || $bk === RequestModel::BILLING_KIND_APP_REQUEST;
    }

    public static function isFreeMeter(RequestModel $request): bool
    {
        $bk = strtolower(trim((string) ($request->billing_kind ?? '')));

        return $bk === RequestModel::BILLING_KIND_FREE_METER;
    }

    public static function tripKmForFare(RequestModel $request): float
    {
        if (isset($request->estimated_trip_km) && (float) $request->estimated_trip_km > 0) {
            return (float) $request->estimated_trip_km;
        }

        $start = $request->startLocation;
        $dest = $request->destLocation;
        if ($start && $dest) {
            return self::haversineKm(
                (float) $start->latitude,
                (float) $start->longitude,
                (float) $dest->latitude,
                (float) $dest->longitude
            );
        }

        return 0.0;
    }

    public static function haversineKm(
        float $lat1,
        float $lon1,
        float $lat2,
        float $lon2,
    ): float {
        $earthRadius = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLon / 2) ** 2;
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return round($earthRadius * $c, 3);
    }
}
