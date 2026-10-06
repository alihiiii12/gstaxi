<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Driver;
use App\Services\AdminLimitedViewService;
use App\Services\DriverSubscriptionService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AdminDriverSubscriptionController extends Controller
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

    public function renew(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }

        $driver = Driver::findOrFail($id);

        $hasCustom = $request->filled('starts_at') || $request->filled('ends_at')
            || $request->filled('subscription_starts_at') || $request->filled('subscription_ends_at');

        if ($hasCustom) {
            $request->validate([
                'starts_at' => 'nullable|date',
                'ends_at' => 'nullable|date',
                'subscription_starts_at' => 'nullable|date',
                'subscription_ends_at' => 'nullable|date',
            ]);
            $startsRaw = $request->input('starts_at', $request->input('subscription_starts_at'));
            $endsRaw = $request->input('ends_at', $request->input('subscription_ends_at'));
            if (! $startsRaw || ! $endsRaw) {
                return response()->json([
                    'success' => false,
                    'message' => 'أرسل تاريخ البداية والنهاية معاً',
                ], 422);
            }
            try {
                DriverSubscriptionService::setCustomPeriod(
                    $driver,
                    Carbon::parse($startsRaw)->startOfDay(),
                    Carbon::parse($endsRaw)->endOfDay(),
                );
            } catch (\Throwable $e) {
                return response()->json([
                    'success' => false,
                    'message' => $e->getMessage(),
                ], 422);
            }
            $driver->refresh();

            return response()->json([
                'success' => true,
                'message' => 'تم ضبط فترة الاشتراك',
                'driver' => $this->subscriptionPayload($driver),
            ]);
        }

        DriverSubscriptionService::renewFromPayment($driver);
        $driver->refresh();

        return response()->json([
            'success' => true,
            'message' => 'تم تجديد الاشتراك 30 يوماً من تاريخ الدفع',
            'driver' => $this->subscriptionPayload($driver),
        ]);
    }

    /** ضبط فترة الاشتراك من تاريخ إلى تاريخ. */
    public function setPeriod(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }

        $data = $request->validate([
            'starts_at' => 'required|date',
            'ends_at' => 'required|date|after:starts_at',
        ]);

        $driver = Driver::findOrFail($id);
        try {
            DriverSubscriptionService::setCustomPeriod(
                $driver,
                Carbon::parse($data['starts_at'])->startOfDay(),
                Carbon::parse($data['ends_at'])->endOfDay(),
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], 422);
        }
        $driver->refresh();

        return response()->json([
            'success' => true,
            'message' => 'تم ضبط فترة الاشتراك',
            'driver' => $this->subscriptionPayload($driver),
        ]);
    }

    public function unblock(Request $request, int $id): JsonResponse
    {
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }

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
        if ($deny = $this->forbidUnlessDriversWrite($request)) {
            return $deny;
        }
        if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $id)) {
            return $deny;
        }

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
