<?php

namespace App\Http\Controllers;

use App\Models\Complaint;
use App\Models\Driver;
use App\Models\User;
use App\Http\Requests\StoreComplaintRequest;
use App\Http\Requests\ResolveComplaintRequest;
use App\Models\RequestModel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;

class ComplaintController extends Controller
{
    /**
     * عرض قائمة جميع الشكاوى (للأدمن)
     */
    public function index(Request $request)
    {
        $query = Complaint::with(['request', 'driver.user']);

        // فلترة حسب الحالة
        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        // فلترة حسب السائق
        if ($request->has('driverId')) {
            $query->where('driverId', $request->driverId);
        }

        // فلترة حسب الرحلة
        if ($request->has('requestId')) {
            $query->where('requestId', $request->requestId);
        }

        // فلترة حسب التاريخ
        if ($request->has('from_date')) {
            $query->whereDate('created_at', '>=', $request->from_date);
        }
        if ($request->has('to_date')) {
            $query->whereDate('created_at', '<=', $request->to_date);
        }

        // ترتيب (الأحدث أولاً)
        $sortBy = $request->get('sort_by', 'created_at');
        $sortOrder = $request->get('sort_order', 'desc');
        $query->orderBy($sortBy, $sortOrder);

        // عرض المحذوفين
        if ($request->has('with_trashed') && $request->with_trashed) {
            $query->withTrashed();
        }

        $complaints = $query->paginate($request->get('per_page', 15));

        // إضافة إحصائيات
        $statistics = [
            'total' => Complaint::count(),
            'pending' => Complaint::where('status', Complaint::STATUS_PENDING)->count(),
            'resolved' => Complaint::where('status', Complaint::STATUS_RESOLVED)->count(),
        ];

        return response()->json([
            'success' => true,
            'data' => $complaints,
            'statistics' => $statistics,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * عرض شكوى محددة
     */
    public function show($id)
    {
        $complaint = Complaint::with(['request' => function($q) {
            $q->with(['user', 'startLocation', 'destLocation']);
        }, 'driver.user'])->find($id);

        if (!$complaint) {
            return response()->json([
                'success' => false,
                'message' => 'Complaint not found'
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $complaint,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * تقديم شكوى جديدة (للمستخدم)
     */
    public function store(StoreComplaintRequest $request)
    {
        $auth = $request->user();
        if (! $auth || $auth->roll !== 'Customer') {
            return response()->json([
                'success' => false,
                'message' => 'يجب تسجيل الدخول كزبون',
            ], 403);
        }

        // التحقق من أن الرحلة انتهت أو ألغيت
        $rideRequest = RequestModel::find($request->requestId);

        if (! $rideRequest || (int) $rideRequest->userId !== (int) $auth->id) {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        if (! in_array($rideRequest->status, ['Finished', 'Removed'])) {
            return response()->json([
                'success' => false,
                'message' => 'لا يمكن تقديم شكوى إلا بعد انتهاء الرحلة أو إلغائها'
            ], 400);
        }

        // التحقق من عدم وجود شكوى مسبقة لنفس الرحلة
        $existingComplaint = Complaint::where('requestId', $request->requestId)->first();

        if ($existingComplaint) {
            return response()->json([
                'success' => false,
                'message' => 'تم تقديم شكوى لهذه الرحلة مسبقاً'
            ], 400);
        }

        if ((int) $request->driverId !== (int) ($rideRequest->driverId ?? 0)) {
            return response()->json([
                'success' => false,
                'message' => 'معرف السائق لا يطابق الرحلة',
            ], 422);
        }

        $complaint = Complaint::create([
            'requestId' => $request->requestId,
            'driverId' => $request->driverId,
            'detail' => $request->detail,
            'rating' => $request->input('rating'),
            'status' => Complaint::STATUS_PENDING,
        ]);

        // إرسال إشعار للأدمن بوجود شكوى جديدة
        $this->notifyAdminNewComplaint($complaint);

        return response()->json([
            'success' => true,
            'data' => $complaint,
            'message' => 'تم تقديم الشكوى بنجاح، سيتم مراجعتها قريباً'
        ], 201);
    }

    /**
     * معالجة الشكوى (للأدمن)
     */
    public function resolve(ResolveComplaintRequest $request, $id)
    {
        $complaint = Complaint::find($id);

        if (!$complaint) {
            return response()->json([
                'success' => false,
                'message' => 'Complaint not found'
            ], 404);
        }

        if ($complaint->status === Complaint::STATUS_RESOLVED) {
            return response()->json([
                'success' => false,
                'message' => 'هذه الشكوى تمت معالجتها مسبقاً'
            ], 400);
        }

        DB::beginTransaction();

        try {
            // تغيير حالة الشكوى
            $complaint->markAsResolved($request->cause);

            // تطبيق الإجراء العقابي على السائق
            $actionResult = $this->applyPenalty($complaint->driverId, $request->cause, $request->penalty_days ?? null);

            // إرسال إشعار للسائق
            $this->notifyDriverAboutPenalty($complaint->driverId, $request->cause, $request->action_note);

            DB::commit();

            return response()->json([
                'success' => true,
                'data' => [
                    'complaint' => $complaint,
                    'penalty' => $actionResult
                ],
                'message' => 'تمت معالجة الشكوى وتطبيق الإجراء المناسب'
            ]);

        } catch (\Exception $e) {
            DB::rollBack();

            return response()->json([
                'success' => false,
                'message' => 'حدث خطأ أثناء معالجة الشكوى',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * تطبيق العقوبة على السائق
     */
    private function applyPenalty($driverId, $cause, $penaltyDays = null)
    {
        $driver = Driver::find($driverId);

        if (!$driver) {
            return ['success' => false, 'message' => 'السائق غير موجود'];
        }

        $user = User::find($driver->userId);
        $result = ['action' => $cause, 'applied' => true];

        switch ($cause) {
            case 'warning':
                // تسجيل تحذير للسائق
                $result['message'] = 'تم تسجيل تحذير للسائق';
                $this->logDriverWarning($driverId, 'تحذير بسبب شكوى');
                break;

            case 'temporary_ban':
                // حظر مؤقت
                $banUntil = now()->addDays($penaltyDays);
                $user->banned = true;
                $user->expireDate = $banUntil;
                $user->save();
                $result['message'] = "تم حظر السائق مؤقتاً حتى {$banUntil->format('Y-m-d')}";
                $result['ban_until'] = $banUntil;
                break;

            case 'permanent_ban':
                // حظر دائم
                $user->banned = true;
                $user->expireDate = null;
                $user->save();
                $result['message'] = 'تم حظر السائق بشكل دائم';
                break;

            case 'dismissed':
                // الشكوى غير مبررة
                $result['message'] = 'تم إلغاء الشكوى لعدم وجود مبرر';
                break;
        }

        return $result;
    }

    /**
     * تسجيل تحذير للسائق
     */
    private function logDriverWarning($driverId, $reason)
    {
        // يمكن إنشاء جدول منفصل لتسجيل التحذيرات
        // DriverWarning::create(['driverId' => $driverId, 'reason' => $reason]);
    }

    /**
     * إشعار الأدمن بوجود شكوى جديدة
     */
    private function notifyAdminNewComplaint($complaint)
    {
        // إرسال إشعار عبر WebSocket أو Firebase
        // event(new NewComplaintEvent($complaint));
    }

    /**
     * إشعار السائق بالعقوبة
     */
    private function notifyDriverAboutPenalty($driverId, $cause, $note = null)
    {
        $driver = Driver::find($driverId);

        if ($driver) {
            $user = User::find($driver->userId);
            // إرسال إشعار للسائق
            // Notification::send($user, new PenaltyNotification($cause, $note));
        }
    }

    /**
     * عرض شكاوى السائق
     */
    public function getDriverComplaints($driverId)
    {
        $complaints = Complaint::where('driverId', $driverId)
            ->with(['request' => function($q) {
                $q->with('user');
            }])
            ->orderBy('created_at', 'desc')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $complaints,
            'message' => 'Driver complaints fetched successfully'
        ]);
    }

    /**
     * عرض شكاوى الرحلة (الزبون صاحب الرحلة أو الأدمن)
     */
    public function getRequestComplaints(Request $httpRequest, $requestId)
    {
        $rideRequest = RequestModel::find($requestId);

        if (! $rideRequest) {
            return response()->json([
                'success' => false,
                'message' => 'الرحلة غير موجودة',
            ], 404);
        }

        $auth = $httpRequest->user();
        if (! $auth) {
            return response()->json([
                'success' => false,
                'message' => 'يجب تسجيل الدخول',
            ], 401);
        }

        $isOwner = $auth->roll === 'Customer'
            && (int) $rideRequest->userId === (int) $auth->id;
        $isAdmin = $auth->roll === 'Admin';

        if (! $isOwner && ! $isAdmin) {
            return response()->json([
                'success' => false,
                'message' => 'غير مصرّح',
            ], 403);
        }

        $complaints = Complaint::where('requestId', $requestId)
            ->with('driver.user')
            ->get();

        return response()->json([
            'success' => true,
            'data' => $complaints,
            'message' => 'Request complaints fetched successfully',
        ]);
    }

    /**
     * حذف شكوى (للأدمن)
     */
    public function destroy($id)
    {
        $complaint = Complaint::find($id);

        if (!$complaint) {
            return response()->json([
                'success' => false,
                'message' => 'Complaint not found'
            ], 404);
        }

        $complaint->delete();

        return response()->json([
            'success' => true,
            'message' => 'Complaint deleted successfully'
        ]);
    }

    /**
     * استعادة شكوى محذوفة
     */
    public function restore($id)
    {
        $complaint = Complaint::withTrashed()->find($id);

        if (!$complaint) {
            return response()->json([
                'success' => false,
                'message' => 'Complaint not found'
            ], 404);
        }

        $complaint->restore();

        return response()->json([
            'success' => true,
            'data' => $complaint,
            'message' => 'Complaint restored successfully'
        ]);
    }

    /**
     * إحصائيات الشكاوى
     */
    public function statistics(Request $request)
    {
        $fromDate = $request->get('from_date', now()->subMonth());
        $toDate = $request->get('to_date', now());

        $statistics = [
            'total' => Complaint::count(),
            'pending' => Complaint::where('status', Complaint::STATUS_PENDING)->count(),
            'resolved' => Complaint::where('status', Complaint::STATUS_RESOLVED)->count(),
            'this_month' => Complaint::whereMonth('created_at', now()->month)->count(),
            'resolution_rate' => $this->calculateResolutionRate(),
            'top_drivers' => $this->getTopComplainedDrivers(),
            'common_causes' => $this->getCommonCauses(),
        ];

        return response()->json([
            'success' => true,
            'data' => $statistics,
            'message' => 'Statistics fetched successfully'
        ]);
    }

    /**
     * حساب نسبة الحل
     */
    private function calculateResolutionRate()
    {
        $total = Complaint::count();
        if ($total == 0) return 0;

        $resolved = Complaint::where('status', Complaint::STATUS_RESOLVED)->count();
        return round(($resolved / $total) * 100, 2);
    }

    /**
     * أكثر السائقين تعرضاً للشكاوى
     */
    private function getTopComplainedDrivers()
    {
        return Complaint::select('driverId', DB::raw('count(*) as complaints_count'))
            ->with('driver.user')
            ->groupBy('driverId')
            ->orderBy('complaints_count', 'desc')
            ->limit(5)
            ->get();
    }

    /**
     * أكثر الأسباب شيوعاً
     */
    private function getCommonCauses()
    {
        return Complaint::whereNotNull('cause')
            ->select('cause', DB::raw('count(*) as count'))
            ->groupBy('cause')
            ->get();
    }
}
