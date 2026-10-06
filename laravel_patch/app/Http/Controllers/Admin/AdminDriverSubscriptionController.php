<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Driver;
use App\Services\DriverSubscriptionService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminDriverSubscriptionController extends Controller
{
    public function renew(Request $request, int $id): JsonResponse
    {
        $driver = Driver::findOrFail($id);
        DriverSubscriptionService::renewFromPayment($driver);
        $driver->refresh();

        return response()->json([
            'success' => true,
            'message' => 'تم تجديد الاشتراك 30 يوماً من تاريخ الدفع',
            'driver' => $this->subscriptionPayload($driver),
        ]);
    }

    public function unblock(Request $request, int $id): JsonResponse
    {
        $driver = Driver::findOrFail($id);
        DriverSubscriptionService::setBlocked($driver, false);
        if (! $driver->subscription_ends_at || Carbon::parse($driver->subscription_ends_at)->isPast()) {
            DriverSubscriptionService::renewFromPayment($driver);
        }
        $driver->refresh();

        return response()->json([
            'success' => true,
            'message' => 'تم إلغاء الحظر',
            'driver' => $this->subscriptionPayload($driver),
        ]);
    }

    public function block(Request $request, int $id): JsonResponse
    {
        $driver = Driver::findOrFail($id);
        DriverSubscriptionService::setBlocked($driver, true);
        $driver->refresh();

        return response()->json([
            'success' => true,
            'message' => 'تم حظر السائق',
            'driver' => $this->subscriptionPayload($driver),
        ]);
    }

    private function subscriptionPayload(Driver $driver): array
    {
        $ends = $driver->subscription_ends_at
            ? Carbon::parse($driver->subscription_ends_at)
            : null;

        $starts = $driver->subscription_starts_at
            ? Carbon::parse($driver->subscription_starts_at)
            : null;

        return [
            'id' => $driver->id,
            'subscription_starts_at' => $starts?->toIso8601String(),
            'subscription_ends_at' => $ends?->toIso8601String(),
            'subscription_blocked' => (bool) $driver->subscription_blocked,
            'subscription_active' => DriverSubscriptionService::isSubscriptionActive($driver),
            'days_remaining' => $ends && $ends->isFuture()
                ? (int) Carbon::now()->diffInDays($ends, false)
                : 0,
        ];
    }
}
