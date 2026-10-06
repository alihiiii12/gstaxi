<?php

/**
 * توحيد تسعيرة «طلب التطبيق» (VIP / اقتصادي…) مع بطاقة الزبون:
 * (كم × KMPrice) + (دقائق × timePrice) — بدون سعر افتتاحي.
 *
 * 1) أضف في `app/Http/Controllers/RequestController.php` (أو خدمة مشتركة):
 */

/*
protected function categoryTripFareLiras(?\App\Models\CarType $carType, float $km, ?float $durationMinutes): ?int
{
    if (! $carType || $km <= 0) {
        return null;
    }
    $kmP = (float) ($carType->KMPrice ?? $carType->km_price ?? 0);
    $minP = (float) ($carType->timePrice ?? $carType->time_price ?? 0);
    $fare = 0.0;
    if ($kmP > 0) {
        $fare += $km * $kmP;
    }
    if ($durationMinutes !== null && $durationMinutes > 0 && $minP > 0) {
        $fare += $durationMinutes * $minP;
    }
    if ($fare <= 0) {
        return null;
    }

    return (int) round($fare);
}

protected function resolvePredectedCostForStore(\Illuminate\Http\Request $request, \App\Models\CarType $carType): int
{
    $quoted = $request->input('customerQuotedFare') ?? $request->input('customer_quoted_fare');
    if ($quoted !== null && is_numeric($quoted) && (float) $quoted > 0) {
        return (int) round((float) $quoted);
    }
    $fromBody = $request->input('predectedCost') ?? $request->input('predected_cost');
    if ($fromBody !== null && is_numeric($fromBody) && (float) $fromBody > 0) {
        return (int) round((float) $fromBody);
    }

    $km = (float) ($request->input('estimatedTripKm') ?? $request->input('estimated_trip_km') ?? 0);
    $mins = $request->input('estimatedDurationMinutes') ?? $request->input('estimated_duration_minutes');
    $minsF = $mins !== null && is_numeric($mins) ? (float) $mins : null;

    $computed = $this->categoryTripFareLiras($carType, $km, $minsF);
    if ($computed !== null && $computed > 0) {
        return $computed;
    }

    return 0;
}
*/

/**
 * 2) داخل `store` بعد تحميل `$carType`:
 *
 *    $predected = $this->resolvePredectedCostForStore($request, $carType);
 *    $requestModel->predectedCost = $predected;
 *    // احفظ أيضاً إن وُجدت أعمدة:
 *    // $requestModel->estimated_trip_km = ...
 *    // $requestModel->estimated_duration_minutes = ...
 *
 * 3) عند إنهاء الرحلة (finishTrip — app_request):
 *
 *    $finalCost = CategoryTripFareService::finalizeAppRequestCost($requestData, $requestData->carType);
 *    // لا تستخدم مدة الرحلة الفعلية × سعر الدقيقة — يطابق بطاقة الزبون.
 *    // إن وُجد خصم مُطبَّق مسبقاً على الطلب، استخدم السعر بعد الخصم المخزّن.
 *
 * 4) في `StoreRequest` validation أضف اختيارياً:
 *    'customerQuotedFare' => 'nullable|numeric|min:0',
 *    'predectedCost' => 'nullable|numeric|min:0',
 *    'estimatedTripKm' => 'nullable|numeric|min:0',
 *    'estimatedDurationMinutes' => 'nullable|numeric|min:0',
 */
