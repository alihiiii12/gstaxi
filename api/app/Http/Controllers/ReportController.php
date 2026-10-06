<?php

namespace App\Http\Controllers;

use App\Models\Driver;
use App\Models\RequestHistory;
use App\Models\RequestModel;
use App\Models\User;
use App\Services\AdminDriverPresenceService;
use App\Services\AdminLimitedViewService;
use App\Services\LocationDisplayService;
use App\Services\TripRevenueService;
use Illuminate\Http\Request ;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use PDF;

class ReportController extends Controller
{
    private function ensureReportsStaff(Request $request): ?\Illuminate\Http\JsonResponse
    {
        $u = $request->user();
        if (! $u || ! $u->hasStaffPermission('reports.read')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        return null;
    }

    /**
     * التقارير المالية
     */
    public function financialReport(Request $request)
    {
        if ($deny = $this->ensureReportsStaff($request)) {
            return $deny;
        }

        $request->validate([
            'from_date' => 'required|date',
            'to_date' => 'required|date|after_or_equal:from_date',
            'driver_id' => 'nullable|exists:drivers,id',
            'format' => 'sometimes|in:json,pdf,excel'
        ]);

        $query = RequestHistory::with(['request', 'driver.user'])
            ->whereBetween('created_at', [$request->from_date, $request->to_date]);
        AdminLimitedViewService::scopeRequestHistories($query, $request->user());

        // فلترة حسب السائق
        if ($request->has('driver_id')) {
            $driverId = (int) $request->driver_id;
            if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $driverId)) {
                return $deny;
            }
            $query->where('driverId', $driverId);
        }

        $histories = $query->get();

        $countingHistories = $histories->filter(function ($h) {
            return RequestModel::countsTowardPlatformRevenue($h->request);
        });

        // حساب الإحصائيات (الإيراد يستثني رحلات العداد الحر «السعر الافتتاحي فقط»)
        $statistics = [
            'total_trips' => $histories->count(),
            'total_revenue' => $countingHistories->sum('finalCost'),
            'average_cost' => $countingHistories->avg('finalCost'),
            'total_discounts' => $histories->whereNotNull('descountId')->count(),
            'total_discount_amount' => $this->calculateDiscountAmount($histories),
            'trips_by_driver' => $histories->groupBy('driverId')->map(function ($item) {
                return [
                    'count' => $item->count(),
                    'revenue' => $item->filter(function ($h) {
                        return RequestModel::countsTowardPlatformRevenue($h->request);
                    })->sum('finalCost'),
                ];
            }),
        ];

        $report = [
            'period' => [
                'from' => $request->from_date,
                'to' => $request->to_date
            ],
            'statistics' => $statistics,
            'details' => $histories
        ];

        // تصدير حسب التنسيق المطلوب
        if ($request->format === 'pdf') {
            return $this->exportToPDF($report);
        }

        if ($request->format === 'excel') {
            return $this->exportToExcel($report);
        }

        return response()->json([
            'success' => true,
            'data' => $report,
            'message' => 'تم إنشاء التقرير المالي بنجاح'
        ]);
    }

    /**
     * التقارير التشغيلية
     */
    public function operationalReport(Request $request)
    {
        if ($deny = $this->ensureReportsStaff($request)) {
            return $deny;
        }

        $request->validate([
            'from_date' => 'required|date',
            'to_date' => 'required|date|after_or_equal:from_date',
        ]);

        // إحصائيات الطلبات
        $requests = RequestModel::whereBetween('created_at', [$request->from_date, $request->to_date]);
        AdminLimitedViewService::scopeRequests($requests, $request->user());

        $statistics = [
            'total_requests' => $requests->count(),
            'scheduled_requests' => (clone $requests)->where('type', RequestModel::TYPE_SCHEDULE)->count(),
            'immediate_requests' => (clone $requests)->where('type', RequestModel::TYPE_IMMEDIATE)->count(),
            'pending_requests' => (clone $requests)->where('status', RequestModel::STATUS_PENDING)->count(),
            'running_requests' => (clone $requests)->where('status', RequestModel::STATUS_RUNNING)->count(),
            'finished_requests' => (clone $requests)->where('status', RequestModel::STATUS_FINISHED)->count(),
            'cancelled_requests' => (clone $requests)->where('status', RequestModel::STATUS_REMOVED)->count(),
            'completion_rate' => $this->calculateCompletionRate($requests),
            'average_response_time' => $this->calculateAverageResponseTime($request->from_date, $request->to_date),
        ];

        // أكثر المناطق طلباً
        $topLocations = $this->getTopLocations($request->from_date, $request->to_date);

        // أكثر أنواع السيارات طلباً
        $topCarTypes = $this->getTopCarTypes($request->from_date, $request->to_date);

        $report = [
            'period' => [
                'from' => $request->from_date,
                'to' => $request->to_date
            ],
            'statistics' => $statistics,
            'top_locations' => $topLocations,
            'top_car_types' => $topCarTypes
        ];

        return response()->json([
            'success' => true,
            'data' => $report,
            'message' => 'تم إنشاء التقرير التشغيلي بنجاح'
        ]);
    }

    /**
     * تقارير الجودة
     */
    public function qualityReport(Request $request)
    {
        if ($deny = $this->ensureReportsStaff($request)) {
            return $deny;
        }

        $request->validate([
            'from_date' => 'required|date',
            'to_date' => 'required|date|after_or_equal:from_date',
            'driver_id' => 'nullable|exists:drivers,id'
        ]);

        $query = RequestHistory::with(['request', 'driver.user'])
            ->whereBetween('created_at', [$request->from_date, $request->to_date]);
        AdminLimitedViewService::scopeRequestHistories($query, $request->user());

        if ($request->has('driver_id')) {
            $driverId = (int) $request->driver_id;
            if ($deny = AdminLimitedViewService::assertDriverAccessible($request->user(), $driverId)) {
                return $deny;
            }
            $query->where('driverId', $driverId);
        }

        $histories = $query->get();

        // حساب تقييم الجودة (إذا كان لديك جدول تقييمات)
        $statistics = [
            'total_trips' => $histories->count(),
            'on_time_percentage' => $this->calculateOnTimePercentage($histories),
            'driver_performance' => $this->calculateDriverPerformance($histories),
            'customer_satisfaction' => $this->calculateCustomerSatisfaction($histories),
        ];

        $report = [
            'period' => [
                'from' => $request->from_date,
                'to' => $request->to_date
            ],
            'statistics' => $statistics,
            'details' => $histories
        ];

        return response()->json([
            'success' => true,
            'data' => $report,
            'message' => 'تم إنشاء تقرير الجودة بنجاح'
        ]);
    }

    /**
     * دوال مساعدة للحسابات
     */
    private function calculateDiscountAmount($histories)
    {
        // حساب قيمة الخصومات
        return 0;
    }

    private function calculateCompletionRate($requests)
    {
        $total = $requests->count();
        if ($total == 0) return 0;

        $completed = (clone $requests)->where('status', RequestModel::STATUS_FINISHED)->count();
        return round(($completed / $total) * 100, 2);
    }

    private function calculateAverageResponseTime($fromDate, $toDate)
    {
        // حساب متوسط وقت الاستجابة
        return 0;
    }

    private function getTopLocations($fromDate, $toDate)
    {
        // أكثر المناطق طلباً
        return [];
    }

    private function getTopCarTypes($fromDate, $toDate)
    {
        // أكثر أنواع السيارات طلباً
        return [];
    }

    private function calculateOnTimePercentage($histories)
    {
        // حساب نسبة الرحلات في الوقت المحدد
        return 100;
    }

    private function calculateDriverPerformance($histories)
    {
        // حساب أداء السائقين
        return [];
    }

    private function calculateCustomerSatisfaction($histories)
    {
        // حساب رضا العملاء
        return 100;
    }

    private function exportToPDF($report)
    {
        $pdf = PDF::loadView('reports.financial', $report);
        return $pdf->download('financial_report.pdf');
    }

    private function exportToExcel($report)
    {
        // تصدير إلى Excel
        return response()->json(['message' => 'Excel export coming soon']);
    }

    /**
     * لوحة سريعة للأدمن (أعداد + SOS نشط)
     */
    public function dashboardSummary(Request $request)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('reports.read')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $staff = $request->user();

        try {
            return $this->buildDashboardSummaryPayload($staff);
        } catch (\Throwable $e) {
            \Log::error('dashboardSummary failed', [
                'message' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
            ]);

            return response()->json([
                'success' => false,
                'message' => 'تعذر تحميل لوحة التحكم. حدّث ملفات الـ API على السيرفر أو راجع سجل الأخطاء.',
            ], 500);
        }
    }

    private function buildDashboardSummaryPayload($staff)
    {
        $sosCount = 0;
        try {
            $sosRaw = Redis::hgetall('sos:active');
            $sosList = is_array($sosRaw) ? array_values($sosRaw) : [];
            $decoded = [];
            foreach ($sosList as $json) {
                $row = json_decode((string) $json, true);
                if (is_array($row)) {
                    $decoded[] = $row;
                }
            }
            $sosCount = count(AdminLimitedViewService::filterSosItems($staff, $decoded));
        } catch (\Throwable $e) {
            $sosCount = 0;
        }

        // الإيراد: طلبات Finished فقط، تاريخ الإتمام = requests.updated_at (وقت إنهاء الرحلة)،
        // المبلغ = requestHistories.finalCost (لا جمع histories بتحديث لاحق خارج يوم الإتمام).
        $todayStart = now()->copy()->startOfDay();
        $todayEnd = now()->copy()->endOfDay();
        $thirtyDaysAgo = now()->copy()->subDays(30)->startOfDay();

        $revenueToday = AdminLimitedViewService::sumRevenueBetween($staff, $todayStart, $todayEnd);
        // طلبات التطبيق فقط — العداد الحر في خانة منفصلة.
        $requestsFinishedToday = AdminLimitedViewService::countFinishedBetween(
            $staff,
            $todayStart,
            $todayEnd,
            'app'
        );
        $freeMeterFinishedToday = AdminLimitedViewService::countFinishedBetween(
            $staff,
            $todayStart,
            $todayEnd,
            'free_meter'
        );

        $assignedPipelineQuery = RequestModel::query()->whereIn('status', [
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
        ]);
        AdminLimitedViewService::scopeRequests($assignedPipelineQuery, $staff);
        $assignedPipelineCount = $assignedPipelineQuery->count();

        // كل الطلبات غير المغلقة رسمياً (للمطابقة الذهنية: Finished / Removed = انتهى)
        $requestsActiveQuery = RequestModel::query()
            ->whereNotIn('status', [
                RequestModel::STATUS_FINISHED,
                RequestModel::STATUS_REMOVED,
            ]);
        AdminLimitedViewService::scopeRequests($requestsActiveQuery, $staff);
        $requestsActiveTotal = $requestsActiveQuery->count();

        $driversTotalQuery = Driver::query();
        AdminLimitedViewService::scopeDrivers($driversTotalQuery, $staff);
        $driversTotal = $driversTotalQuery->count();

        $customersTotalQuery = User::query()->where('roll', 'Customer');
        AdminLimitedViewService::scopeCustomers($customersTotalQuery, $staff);
        $customersTotal = $customersTotalQuery->count();

        $pendingQuery = RequestModel::query()->where('status', RequestModel::STATUS_PENDING);
        AdminLimitedViewService::scopeRequests($pendingQuery, $staff);

        $runningQuery = RequestModel::query()->where('status', RequestModel::STATUS_RUNNING);
        AdminLimitedViewService::scopeRequests($runningQuery, $staff);

        $revenueLast30 = AdminLimitedViewService::sumRevenueBetween($staff, $thirtyDaysAgo, $todayEnd);

        $yesterdayStart = now()->copy()->subDay()->startOfDay();
        $yesterdayEnd = now()->copy()->subDay()->endOfDay();
        $revenueYesterday = AdminLimitedViewService::sumRevenueBetween($staff, $yesterdayStart, $yesterdayEnd);

        $charts = $this->buildDashboardCharts($staff, 14);

        $customersToday = 0;
        $customersYesterday = 0;
        $driversToday = 0;
        $driversYesterday = 0;
        try {
            $cq = User::query()->where('roll', 'Customer');
            AdminLimitedViewService::scopeCustomers($cq, $staff);
            $customersToday = (clone $cq)->whereBetween('created_at', [$todayStart, $todayEnd])->count();
            $customersYesterday = (clone $cq)->whereBetween('created_at', [$yesterdayStart, $yesterdayEnd])->count();

            $dq = Driver::query();
            AdminLimitedViewService::scopeDrivers($dq, $staff);
            $driversToday = (clone $dq)->whereBetween('created_at', [$todayStart, $todayEnd])->count();
            $driversYesterday = (clone $dq)->whereBetween('created_at', [$yesterdayStart, $yesterdayEnd])->count();
        } catch (\Throwable $e) {
        }

        // نفس مصدر خريطة العمليات تماماً حتى يتطابق الرقمان.
        $driverCounts = ['total' => 0, 'available' => 0, 'to_pickup' => 0, 'on_trip' => 0];
        $onlineIds = [];
        try {
            $markers = AdminLimitedViewService::filterDriverMarkers($staff, AdminDriverPresenceService::markers());
            $driverCounts = AdminDriverPresenceService::counts($markers);
            $onlineIds = array_flip(array_map(fn ($m) => (int) $m['driverId'], $markers));
        } catch (\Throwable $e) {
        }
        $driversOnline = $driverCounts['total'];

        // رحلات «جارية» وسائقها غير متصل — غالباً عداد حر نُسي إنهاؤه.
        $runningDisconnected = 0;
        try {
            foreach ((clone $runningQuery)->whereNotNull('driverId')->pluck('driverId') as $did) {
                if (! isset($onlineIds[(int) $did])) {
                    $runningDisconnected++;
                }
            }
        } catch (\Throwable $e) {
        }

        // المقارنة مع أمس حتى نفس الساعة (لا مع يوم أمس كاملاً).
        $yesterdaySameTime = now()->copy()->subDay();
        $revenueYesterdaySameTime = AdminLimitedViewService::sumRevenueBetween($staff, $yesterdayStart, $yesterdaySameTime);
        $customersYesterdaySameTime = 0;
        $driversYesterdaySameTime = 0;
        try {
            $cq = User::query()->where('roll', 'Customer');
            AdminLimitedViewService::scopeCustomers($cq, $staff);
            $customersYesterdaySameTime = $cq->whereBetween('created_at', [$yesterdayStart, $yesterdaySameTime])->count();
            $dq = Driver::query();
            AdminLimitedViewService::scopeDrivers($dq, $staff);
            $driversYesterdaySameTime = $dq->whereBetween('created_at', [$yesterdayStart, $yesterdaySameTime])->count();
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => [
                // ملفات سائق فعلية (جدول drivers)، وليس فقط حسابات User بدور Driver
                'drivers_total' => $driversTotal,
                'drivers_online' => $driversOnline,
                'drivers_online_available' => $driverCounts['available'],
                'drivers_online_to_pickup' => $driverCounts['to_pickup'],
                'drivers_online_on_trip' => $driverCounts['on_trip'],
                'customers_total' => $customersTotal,
                'requests_pending' => $pendingQuery->count(),
                'requests_running' => $runningQuery->count(),
                'requests_running_driver_offline' => $runningDisconnected,
                'revenue_yesterday_same_time' => round($revenueYesterdaySameTime, 2),
                'customers_new_yesterday_same_time' => $customersYesterdaySameTime,
                'drivers_new_yesterday_same_time' => $driversYesterdaySameTime,
                'requests_finished_today' => $requestsFinishedToday,
                'free_meter_finished_today' => $freeMeterFinishedToday,
                // اسم الحقل للتوافق مع التطبيق؛ المعنى: مراحل ما قبل «قيد التنفيذ»
                'unfinished_bookings' => $assignedPipelineCount,
                'requests_active_total' => $requestsActiveTotal,
                'revenue_today' => round($revenueToday, 2),
                'revenue_yesterday' => round($revenueYesterday, 2),
                'revenue_last_30_days' => round($revenueLast30, 2),
                'active_sos' => $sosCount,
                'customers_new_today' => $customersToday,
                'customers_new_yesterday' => $customersYesterday,
                'drivers_new_today' => $driversToday,
                'drivers_new_yesterday' => $driversYesterday,
                'charts' => $charts,
            ],
        ]);
    }

    /**
     * سلاسل زمنية للوحة التحكم (آخر N يوماً).
     *
     * @return array{revenue_daily: list<array{date:string,label:string,amount:float}>, customers_daily: list<array{date:string,label:string,count:int}>, drivers_daily: list<array{date:string,label:string,count:int}>, trips_daily: list<array{date:string,label:string,count:int}>}
     */
    private function buildDashboardCharts($staff, int $days = 14): array
    {
        $days = max(7, min(31, $days));
        $from = now()->copy()->subDays($days - 1)->startOfDay();
        $to = now()->copy()->endOfDay();

        $labels = [];
        for ($i = 0; $i < $days; $i++) {
            $d = $from->copy()->addDays($i);
            $key = $d->toDateString();
            $labels[$key] = [
                'date' => $key,
                'label' => $d->format('m/d'),
                'amount' => 0.0,
                'customers' => 0,
                'drivers' => 0,
                'trips' => 0,
            ];
        }

        // إيراد + عدد الرحلات المكتملة يومياً
        try {
            $revQ = RequestModel::query()
                ->where(TripRevenueService::finishedRevenueScope())
                ->whereBetween('updated_at', [$from, $to])
                ->with(['history', 'carType']);
            AdminLimitedViewService::scopeRequests($revQ, $staff);
            $revQ->chunkById(200, function ($rows) use (&$labels) {
                foreach ($rows as $row) {
                    $key = optional($row->updated_at)->toDateString();
                    if (! $key || ! isset($labels[$key])) {
                        continue;
                    }
                    $labels[$key]['amount'] += TripRevenueService::tripAmount($row);
                    $labels[$key]['trips']++;
                }
            });
        } catch (\Throwable $e) {
        }

        try {
            $custQ = User::query()
                ->where('roll', 'Customer')
                ->whereBetween('created_at', [$from, $to]);
            AdminLimitedViewService::scopeCustomers($custQ, $staff);
            $custRows = $custQ
                ->selectRaw('DATE(created_at) as d, COUNT(*) as c')
                ->groupBy('d')
                ->pluck('c', 'd');
            foreach ($custRows as $d => $c) {
                $key = (string) $d;
                if (isset($labels[$key])) {
                    $labels[$key]['customers'] = (int) $c;
                }
            }
        } catch (\Throwable $e) {
        }

        try {
            $drvQ = Driver::query()->whereBetween('created_at', [$from, $to]);
            AdminLimitedViewService::scopeDrivers($drvQ, $staff);
            $drvRows = $drvQ
                ->selectRaw('DATE(created_at) as d, COUNT(*) as c')
                ->groupBy('d')
                ->pluck('c', 'd');
            foreach ($drvRows as $d => $c) {
                $key = (string) $d;
                if (isset($labels[$key])) {
                    $labels[$key]['drivers'] = (int) $c;
                }
            }
        } catch (\Throwable $e) {
        }

        $revenueDaily = [];
        $customersDaily = [];
        $driversDaily = [];
        $tripsDaily = [];
        foreach ($labels as $row) {
            $revenueDaily[] = [
                'date' => $row['date'],
                'label' => $row['label'],
                'amount' => round((float) $row['amount'], 2),
            ];
            $customersDaily[] = [
                'date' => $row['date'],
                'label' => $row['label'],
                'count' => (int) $row['customers'],
            ];
            $driversDaily[] = [
                'date' => $row['date'],
                'label' => $row['label'],
                'count' => (int) $row['drivers'],
            ];
            $tripsDaily[] = [
                'date' => $row['date'],
                'label' => $row['label'],
                'count' => (int) $row['trips'],
            ];
        }

        return [
            'revenue_daily' => $revenueDaily,
            'customers_daily' => $customersDaily,
            'drivers_daily' => $driversDaily,
            'trips_daily' => $tripsDaily,
        ];
    }

    /**
     * تفاصيل رحلات الإيراد للوحة التحكم — استعلام واحد سريع بدل جلب كل الصفحات من الواجهة.
     * GET /reports/dashboard-revenue-trips?from_date=&to_date=&billing=
     */
    public function dashboardRevenueTrips(Request $request)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('reports.read')) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $request->validate([
            'from_date' => 'required|date',
            'to_date' => 'required|date|after_or_equal:from_date',
            'billing' => 'nullable|in:all,app,free_meter',
        ]);

        $from = \Carbon\Carbon::parse($request->input('from_date'))->startOfDay();
        $to = \Carbon\Carbon::parse($request->input('to_date'))->endOfDay();
        if ($from->diffInDays($to) > 62) {
            return response()->json([
                'success' => false,
                'message' => 'النطاق الأقصى 62 يوماً',
            ], 422);
        }

        $billing = strtolower(trim((string) $request->input('billing', 'all')));
        $staff = $request->user();

        $query = RequestModel::query()
            ->where('status', RequestModel::STATUS_FINISHED)
            ->whereBetween('updated_at', [$from, $to])
            ->with([
                'history:id,requestId,finalCost,distanceTraveledKm,updated_at',
                'driver:id,userId,carNumber',
                'driver.user:id,firstName,lastName,number',
                'carType:id,openPrice,KMPrice,timePrice',
                'startLocation:id,name,latitude,longitude',
                'destLocation:id,name,latitude,longitude',
            ])
            ->orderByDesc('updated_at')
            ->limit(800);

        if (TripRevenueService::hasBillingColumns()) {
            if ($billing === 'free_meter') {
                $query->where('billing_kind', RequestModel::BILLING_KIND_FREE_METER);
            } elseif ($billing === 'app') {
                $query->where(function ($q) {
                    $q->whereNull('billing_kind')
                        ->orWhere('billing_kind', '!=', RequestModel::BILLING_KIND_FREE_METER);
                });
            }
        }

        AdminLimitedViewService::scopeRequests($query, $staff);
        $rows = $query->get();

        $out = [];
        $sum = 0.0;
        foreach ($rows as $req) {
            $cost = TripRevenueService::tripAmount($req);
            $sum += $cost;
            $driverUser = $req->driver?->user;
            $driverName = trim(($driverUser->firstName ?? '').' '.($driverUser->lastName ?? ''));
            if ($driverName === '') {
                $driverName = $req->driverId ? ('سائق #'.$req->driverId) : '—';
            }
            $pickup = LocationDisplayService::labelForRequestPoint($req, false, false);
            $dest = LocationDisplayService::labelForRequestPoint($req, true, false);
            $pathLabel = trim($pickup.' → '.$dest);
            if ($pathLabel === '→') {
                $pathLabel = '—';
            }

            $out[] = [
                'id' => (int) $req->id,
                'driver' => $driverName,
                'cost' => round($cost, 2),
                'at' => optional($req->updated_at)?->toIso8601String(),
                'at_label' => optional($req->updated_at)?->format('Y/m/d H:i') ?? '—',
                'path_label' => $pathLabel,
                'billing_kind' => $req->billing_kind,
                'sort_ms' => $req->updated_at
                    ? ((int) $req->updated_at->getTimestamp() * 1000)
                    : 0,
            ];
        }

        return response()->json([
            'success' => true,
            'data' => [
                'from_date' => $from->toDateString(),
                'to_date' => $to->toDateString(),
                'billing' => $billing,
                'count' => count($out),
                'sum' => round($sum, 2),
                'trips' => $out,
            ],
        ]);
    }
}
