<?php

namespace App\Http\Controllers;

use App\Services\UserSessionService;

use App\Http\Requests\AddEmployeeRequest;
use App\Http\Requests\CreateUserRequest;
use App\Http\Requests\CustomerRegisterRequest;
use App\Http\Requests\LoginRequest;
use App\Models\Driver;
use App\Models\RequestModel;
use App\Models\User;
use App\Services\DriverSubscriptionService;
use App\Services\PhoneOtpService;
use App\Services\AppUpdatePolicy;
use Illuminate\Http\Request;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Redis;

class UserController extends Controller
{
    public function __construct(private readonly PhoneOtpService $otp)
    {
    }

    /**
     * Display a listing of the resource.
     */
    public function index()
    {
        //
    }

    public function sos()  {
        
    }

    public function login(LoginRequest $request)
    {
        try {
            $client = strtolower(trim((string) $request->header('X-Client', '')));
            // لوحة الويب لا تخضع لفرض تحديث التطبيق.
            if ($client !== 'web-admin') {
                $updateBlock = AppUpdatePolicy::evaluateClient(
                    AppUpdatePolicy::clientBuildFromRequest($request),
                    AppUpdatePolicy::clientPlatformFromRequest($request)
                );
                if ($updateBlock !== null) {
                    return response()->json([
                        'success' => false,
                        'state' => false,
                        'message' => $updateBlock['message'],
                        'code' => 'update_required',
                        'update_required' => true,
                        'download_url' => $updateBlock['download_url'],
                        'min_build' => $updateBlock['min_build'],
                    ], 426);
                }
            }

            $passwordNeedChange = false;

            $number = trim((string) $request->input('number'));
            $normalized = $this->otp->normalizeNumber($number);
            $user = User::query()
                ->where('number', $number)
                ->when($normalized !== $number, fn ($q) => $q->orWhere('number', $normalized))
                ->first();

            $storedHash = $user ? (string) $user->getAuthPassword() : '';
            if ($user === null || $storedHash === '' || ! Hash::check($request['password'], $storedHash)) {
                return response()->json([
                    'success' => false,
                    'state' => false,
                    'message' => 'رقم الهاتف أو كلمة المرور غير صحيحة',
                ], 401);
            }

            if ($request['password'] == 'Syriataxi@1') {
                $passwordNeedChange = true;
            }

            $driverRow = Driver::where('userId', $user->id)->first();
            $carNumber = $driverRow?->carNumber;
            $type = $driverRow?->type;
            $driverId = $driverRow?->id;
            $transTypeId = $driverRow?->transTypeId;

            if ($user->banned && $user->roll === 'Driver' && $user->expireDate && $user->expireDate->lt(now()->startOfDay())) {
                $user->banned = false;
                $user->save();
            }

            if ($user->banned) {
                return response()->json([
                    'success' => false,
                    'state' => false,
                    'message' => 'هذا الحساب محظور',
                ], 403);
            }

            // أدمن/موظف: الدخول من لوحة الويب فقط — يُرفض التطبيق (قديم/جديد).
            if ($user->isBackofficeStaff()) {
                $client = strtolower(trim((string) $request->header('X-Client', '')));
                if ($client !== 'web-admin') {
                    return response()->json([
                        'success' => false,
                        'state' => false,
                        'message' => 'لوحة التحكم متاحة عبر الويب فقط. لا يمكن الدخول من التطبيق.',
                        'code' => 'staff_web_only',
                    ], 403);
                }
            }

            if ($user->roll === 'Customer' && $user->phone_verified_at === null) {
                if ($this->otp->bypassEnabled()) {
                    $user->phone_verified_at = now();
                    $user->save();
                } else {
                    return response()->json([
                        'success' => false,
                        'state' => false,
                        'message' => 'يرجى تأكيد رقم الهاتف عبر رمز التحقق أولاً',
                        'code' => 'phone_not_verified',
                    ], 403);
                }
            }

            if ($driverRow) {
                try {
                    $blockMsg = DriverSubscriptionService::loginBlockedMessage($driverRow);
                    if ($blockMsg !== null) {
                        return response()->json([
                            'success' => false,
                            'state' => false,
                            'message' => $blockMsg,
                            'code' => 'subscription_blocked',
                        ], 403);
                    }
                } catch (\Throwable $e) {
                    \Illuminate\Support\Facades\Log::warning('login subscription check: '.$e->getMessage());
                }
            }

            if ($request->filled('fcm_token')) {
                $user->fcm_token = mb_substr((string) $request->input('fcm_token'), 0, 2048);
                $user->save();
            }

            // لوحة الويب: مسح الجلسات القديمة (هذا الحساب غالباً يجمع توكنات كثيرة)
            if ($user->isBackofficeStaff()) {
                try {
                    $user->tokens()->delete();
                } catch (\Throwable $e) {
                    \Illuminate\Support\Facades\Log::warning('login staff token purge: '.$e->getMessage());
                }
            }

            $deviceId = $request->input('device_id');
            $token = UserSessionService::createToken($user, is_string($deviceId) ? $deviceId : null);

            $perms = [];
            if ($user->isBackofficeStaff()) {
                try {
                    $rawPerms = $user->permissions;
                    if (is_array($rawPerms)) {
                        $perms = $rawPerms;
                    } elseif (is_string($rawPerms) && $rawPerms !== '') {
                        $decoded = json_decode($rawPerms, true);
                        $perms = is_array($decoded) ? $decoded : [];
                    }
                } catch (\Throwable $e) {
                    \Illuminate\Support\Facades\Log::warning('login permissions reset user '.$user->id.': '.$e->getMessage());
                    try {
                        User::whereKey($user->id)->update(['permissions' => null]);
                        $user->refresh();
                    } catch (\Throwable $e2) {
                    }
                    $perms = [];
                }
            }

            return response()->json([
                'success' => true,
                'state' => true,
                'message' => 'تم تسجيل الدخول بنجاح',
                'user' => [
                    'id' => $user->id,
                    'number' => $user->number,
                    'firstName' => $user->firstName,
                    'lastName' => $user->lastName,
                    'roll' => $user->roll,
                    'permissions' => $user->isBackofficeStaff() ? $perms : [],
                    'carNumber' => $carNumber,
                    'typeCar' => $type,
                    'driverId' => $driverId,
                    'transTypeId' => $transTypeId,
                    'changePasswordNeeded' => $passwordNeedChange,
                ],
                'token' => $token,
            ]);
        } catch (HttpResponseException $e) {
            throw $e;
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::error('login failed: '.$e->getMessage(), [
                'trace' => $e->getTraceAsString(),
            ]);

            $hint = 'خطأ في الخادم أثناء تسجيل الدخول. راجع سجل Laravel أو نفّذ migrate.';
            $msg = $e->getMessage();
            if (str_contains($msg, 'personal_access_tokens')) {
                $hint = 'جدول personal_access_tokens غير موجود — نفّذ: php artisan migrate --force';
            } elseif (str_contains($msg, 'fcm_token')) {
                $hint = 'عمود fcm_token غير موجود — نفّذ: php artisan migrate --force';
            }

            return response()->json([
                'success' => false,
                'state' => false,
                'message' => $hint,
                'debug' => config('app.debug') ? $e->getMessage() : null,
            ], 500);
        }
    }
    /**
     * Store a newly created resource in storage.
     */
    public function register(CreateUserRequest $request)
    {
        $validated = $request->validated();
        $number = $this->otp->normalizeNumber($validated['number']);
        $unified = 'إن كان الرقم مؤهلاً سيصلك رمز التحقق برسالة نصية.';

        // VUL-08 + دور ثابت Customer
        if (User::where('number', $number)->exists()) {
            return response()->json([
                'success' => true,
                'state' => true,
                'message' => $unified,
            ], 200);
        }

        $user = User::create([
            'number' => $number,
            'firstName' => $validated['firstName'],
            'lastName' => $validated['lastName'],
            'password' => Hash::make($validated['password']),
            'roll' => 'Customer',
            'phone_verified_at' => $this->otp->bypassEnabled() ? now() : null,
        ]);

        try {
            $this->otp->send($number, PhoneOtpService::PURPOSE_REGISTER);
        } catch (\RuntimeException $e) {
            if ($e->getMessage() === 'OTP_DELIVERY_FAILED') {
                return response()->json([
                    'success' => false,
                    'state' => false,
                    'message' => 'تعذر إرسال رمز التحقق. حاول مجدداً بعد قليل.',
                ], 503);
            }
            throw $e;
        }

        return response()->json([
            'success' => true,
            'state' => true,
            'message' => $this->otp->bypassEnabled()
                ? 'تم إنشاء الحساب. أدخل الرمز 0000 في التطبيق للمتابعة.'
                : $unified,
            'data' => [
                'id' => $user->id,
                'number' => $user->number,
            ],
        ], 201);
    }

    /**
     * تسجيل زبون من التطبيق — الدور Customer افتراضياً + إرسال OTP.
     */
    public function registerCustomer(CustomerRegisterRequest $request)
    {
        $validated = $request->validated();
        $number = $this->otp->normalizeNumber($validated['number']);

        [$firstName, $lastName] = $this->resolveNameParts($request, $validated);

        // VUL-08: رسالة موحّدة — لا تكشف إن كان الرقم مسجّلاً مسبقاً.
        $unifiedMessage = $this->otp->bypassEnabled()
            ? 'تم إنشاء الحساب. أدخل الرمز 0000 للمتابعة.'
            : 'إن كان الرقم مؤهلاً سيصلك رمز التحقق برسالة نصية.';
        $existing = User::where('number', $number)->first();

        if ($existing) {
            if ($existing->phone_verified_at === null && $existing->roll === 'Customer') {
                if ($this->otp->bypassEnabled()) {
                    $existing->phone_verified_at = now();
                    $existing->save();
                }
                try {
                    $this->otp->send($number, PhoneOtpService::PURPOSE_REGISTER);
                } catch (\RuntimeException $e) {
                    if ($e->getMessage() === 'OTP_DELIVERY_FAILED') {
                        return response()->json([
                            'state' => false,
                            'success' => false,
                            'message' => 'تعذر إرسال رمز التحقق. حاول مجدداً بعد قليل.',
                        ], 503);
                    }
                    throw $e;
                }
            }

            return response()->json([
                'state' => true,
                'success' => true,
                'message' => $unifiedMessage,
                'data' => $this->otp->buildOtpApiPayload($number, $this->otp->bypassEnabled() ? $this->otp->fallbackCode() : ''),
            ], 200);
        }

        $user = User::create([
            'number' => $number,
            'firstName' => $firstName,
            'lastName' => $lastName,
            'password' => $validated['password'],
            'roll' => 'Customer',
            'phone_verified_at' => $this->otp->bypassEnabled() ? now() : null,
        ]);

        try {
            $this->otp->send($number, PhoneOtpService::PURPOSE_REGISTER);
        } catch (\RuntimeException $e) {
            if ($e->getMessage() === 'OTP_DELIVERY_FAILED') {
                return response()->json([
                    'state' => false,
                    'success' => false,
                    'message' => 'تعذر إرسال رمز التحقق. حاول مجدداً بعد قليل.',
                    'data' => ['id' => $user->id],
                ], 503);
            }
            throw $e;
        }

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => $unifiedMessage,
            'data' => array_merge(
                $this->otp->buildOtpApiPayload($number, $this->otp->bypassEnabled() ? $this->otp->fallbackCode() : ''),
                ['id' => $user->id],
            ),
        ], 201);
    }

    public function resendConfirmationCode(Request $request)
    {
        $validated = $request->validate([
            'number' => 'required|string|min:10|max:14',
            'purpose' => 'nullable|in:register,reset_password',
        ]);

        $number = $this->otp->normalizeNumber($validated['number']);
        $purpose = $validated['purpose'] ?? PhoneOtpService::PURPOSE_REGISTER;

        $user = User::where('number', $number)->first();
        if (! $user) {
            return response()->json([
                'state' => true,
                'success' => true,
                'message' => 'إن وُجد الحساب سيصلك الرمز قريباً',
            ]);
        }

        if ($purpose === PhoneOtpService::PURPOSE_REGISTER && $user->phone_verified_at !== null) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'الحساب مُفعَّل مسبقاً — سجّل الدخول',
            ], 400);
        }

        try {
            $code = $this->otp->send($number, $purpose);
        } catch (\RuntimeException $e) {
            if ($e->getMessage() === 'OTP_DELIVERY_FAILED') {
                return response()->json([
                    'state' => false,
                    'success' => false,
                    'message' => 'تعذر إرسال رمز التحقق. حاول مجدداً بعد قليل.',
                ], 503);
            }
            throw $e;
        }

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => $this->otp->bypassEnabled()
                ? 'أدخل الرمز 0000 للمتابعة'
                : 'تم إرسال رمز التحقق (سوريا +963)',
            'data' => $this->otp->buildOtpApiPayload($number, $code),
        ]);
    }

    public function confirmAccount(Request $request)
    {
        $validated = $request->validate([
            'number' => 'required|string|min:10|max:14',
            'code' => 'required|string|size:4',
        ]);

        $number = $this->otp->normalizeNumber($validated['number']);
        $user = User::where('number', $number)->first();
        if (! $user) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'الحساب غير موجود',
            ], 404);
        }

        // قبول 0000 فقط عند OTP_BYPASS=true (عبر PhoneOtpService::verify)
        if (! $this->otp->verify($number, PhoneOtpService::PURPOSE_REGISTER, $validated['code'])) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'رمز التحقق غير صحيح أو منتهي',
            ], 422);
        }

        $user->phone_verified_at = now();

        if ($request->filled('fcm_token')) {
            $user->fcm_token = mb_substr((string) $request->input('fcm_token'), 0, 2048);
        }
        $user->save();

        $deviceId = $request->input('device_id');
        $token = UserSessionService::createToken($user, is_string($deviceId) ? $deviceId : null);

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => 'تم تأكيد الحساب',
            'user' => [
                'id' => $user->id,
                'number' => $user->number,
                'firstName' => $user->firstName,
                'lastName' => $user->lastName,
                'roll' => $user->roll,
                'permissions' => $user->isBackofficeStaff()
                    ? ($user->permissions ?? [])
                    : [],
                'carNumber' => null,
                'typeCar' => null,
                'driverId' => null,
                'transTypeId' => null,
                'changePasswordNeeded' => false,
            ],
            'token' => $token,
        ]);
    }

    public function forgotPassword(Request $request)
    {
        $validated = $request->validate([
            'number' => 'required|string|min:10|max:14',
        ]);

        $number = $this->otp->normalizeNumber($validated['number']);
        $user = User::where('number', $number)->first();
        $code = '';
        if ($user) {
            try {
                $code = $this->otp->send($number, PhoneOtpService::PURPOSE_RESET_PASSWORD);
            } catch (\RuntimeException $e) {
                if ($e->getMessage() === 'OTP_DELIVERY_FAILED') {
                    return response()->json([
                        'state' => false,
                        'success' => false,
                        'message' => 'تعذر إرسال رمز التحقق. حاول مجدداً بعد قليل.',
                    ], 503);
                }
                throw $e;
            }
        }

        $payload = $code !== ''
            ? $this->otp->buildOtpApiPayload($number, $code)
            : [
                'number' => $number,
                'country' => PhoneOtpService::COUNTRY_ISO,
                'dial_code' => PhoneOtpService::DIAL_CODE,
            ];

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => 'إن وُجد الحساب سيصلك رمز التحقق (سوريا +963)',
            'data' => $payload,
        ]);
    }

    /** تحقق من الرمز لاستعادة كلمة المرور — يُرجع reset_token */
    public function confirmForgetPassword(Request $request)
    {
        $validated = $request->validate([
            'number' => 'required|string|min:10|max:14',
            'code' => 'required|string|size:4',
        ]);

        $number = $this->otp->normalizeNumber($validated['number']);
        $user = User::where('number', $number)->first();
        if (! $user) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'الحساب غير موجود',
            ], 404);
        }

        if (! $this->otp->verify($number, PhoneOtpService::PURPOSE_RESET_PASSWORD, $validated['code'])) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'رمز التحقق غير صحيح أو منتهي',
            ], 422);
        }

        $resetToken = $this->otp->issueResetToken($number);

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => 'تم التحقق — عيّن كلمة المرور الجديدة',
            'data' => [
                'reset_token' => $resetToken,
                'number' => $number,
            ],
        ]);
    }

    public function resetPasswordAfterOtp(Request $request)
    {
        $validated = $request->validate([
            'number' => 'required|string|min:10|max:14',
            'reset_token' => 'required|string|min:20',
            'password' => 'required|string|min:6|confirmed',
        ]);

        $number = $this->otp->normalizeNumber($validated['number']);
        if (! $this->otp->verifyResetToken($number, $validated['reset_token'])) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'انتهت صلاحية الجلسة — أعد طلب الرمز',
            ], 422);
        }

        $user = User::where('number', $number)->first();
        if (! $user) {
            return response()->json([
                'state' => false,
                'success' => false,
                'message' => 'الحساب غير موجود',
            ], 404);
        }

        $user->password = $validated['password'];
        if ($user->phone_verified_at === null) {
            $user->phone_verified_at = now();
        }
        $user->save();

        return response()->json([
            'state' => true,
            'success' => true,
            'message' => 'تم تغيير كلمة المرور — سجّل الدخول',
        ]);
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array{0: string, 1: string}
     */
    private function resolveNameParts(Request $request, array $validated): array
    {
        if ($request->filled('fullName')) {
            $parts = preg_split('/\s+/u', trim((string) $request->input('fullName')), -1, PREG_SPLIT_NO_EMPTY) ?: [];
            $first = $parts[0] ?? 'زبون';
            $last = count($parts) > 1 ? implode(' ', array_slice($parts, 1)) : '';

            return [$first, $last];
        }

        return [
            (string) ($validated['firstName'] ?? 'زبون'),
            (string) ($validated['lastName'] ?? ''),
        ];
    }

    /**
     * Display the specified resource.
     */
    public function logout(Request $request)
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'state' => false,
                'message' => 'User not authenticated',
            ], 401);
        }

        if ($user->roll === 'Driver') {
            $driver = Driver::where('userId', $user->id)->first();
            if ($driver) {
                Redis::zrem('drivers', (string) $driver->id);
            }
        }

        $user->currentAccessToken()->delete();

        $user->fcm_token = null;
        $user->save();

        return response()->json([
            'success' => true,
            'message' => 'Logged out successfully',
        ], 200);
    }


    /**
     * Update the specified resource in storage.
     */
    public function update(Request $request)
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'state' => false,
                'message' => 'User not found'
            ], 404);
        }

        // VUL-01: لا نقبل roll/banned/permissions من العميل — قائمة بيضاء فقط.
        $validated = $request->validate([
            'firstName' => 'sometimes|string|max:255',
            'lastName' => 'sometimes|string|max:255',
            'password' => 'sometimes|string|min:6',
            'fcm_token' => 'nullable|string|max:4096',
        ]);

        if (isset($validated['password'])) {
            $validated['password'] = Hash::make($validated['password']);
        }

        $user->fill($validated);
        $user->save();

        return response()->json([
            'state' => true,
            'message' => 'User updated successfully',
            'data' => $user->fresh(),
        ]);
    }

    /**
     * حفظ/تحديث رمز FCM للمستخدم الحالي (بعد منح الأذونات في التطبيق).
     */
    public function updateFcmToken(Request $request)
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['state' => false, 'message' => 'User not authenticated'], 401);
        }

        $validated = $request->validate([
            'fcm_token' => 'required|string|max:4096',
        ]);

        $user->fcm_token = mb_substr($validated['fcm_token'], 0, 2048);
        $user->save();

        return response()->json([
            'success' => true,
            'message' => 'FCM token saved',
        ]);
    }

    public function addEmployee(AddEmployeeRequest $request)
    {
        $actor = $request->user();
        if (! $actor || ! $actor->isBackofficeStaff() || $actor->roll !== 'Admin') {
            return response()->json([
                'state' => false,
                'message' => 'Unauthorized',
            ], 403);
        }

        User::create([
            'number' => $request['number'],
            'firstName' => $request['firstName'],
            'lastName' => $request['lastName'],
            'password' => Hash::make('Syriataxi@1'),
            'roll' => 'Employee',
        ]);

        return response()->json([
            'state' => true,
            'message' => 'Employee created',
            // لا تُرجع كلمة المرور الافتراضية في الاستجابة (VUL hardening)
        ], 201);
    }

    /**
     * Remove the specified resource from storage.
     */
    public function getProfile(Request $request)
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'state' => false,
                'message' => 'User not authenticated'
            ], 401);
        }

        $driver = Driver::where('userId', $user->id)->first();

        $responseData = [
            'state' => true,
            'name' => $user->firstName . ' ' . $user->lastName,
            'number' => $user->number,
            'carNumber' => null,
            'cartype' => null
        ];

        if ($driver) {
            $responseData['carNumber'] = $driver->carNumber;
            $responseData['cartype'] = $driver->type;
        }

        return response()->json($responseData);
    }

    /** حذف الحساب من التطبيق (زبون/سائق) — مطلوب App Store. */
    public function deleteMyAccount(Request $request)
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json([
                'success' => false,
                'state' => false,
                'message' => 'غير مسجل الدخول',
            ], 401);
        }

        if ($user->isBackofficeStaff()) {
            return response()->json([
                'success' => false,
                'state' => false,
                'message' => 'حسابات لوحة التحكم تُدار من الويب فقط',
            ], 403);
        }

        $activeStatuses = [
            RequestModel::STATUS_PENDING,
            RequestModel::STATUS_RUNNING,
            RequestModel::STATUS_RESERVED,
            RequestModel::STATUS_DRIVER_ARRIVED,
            RequestModel::STATUS_AWAITING_DESTINATION,
        ];

        $hasActiveTrip = RequestModel::query()
            ->where('userId', $user->id)
            ->whereIn('status', $activeStatuses)
            ->exists();

        $driver = Driver::where('userId', $user->id)->first();
        if ($driver !== null) {
            $hasActiveTrip = $hasActiveTrip || RequestModel::query()
                ->where('driverId', $driver->id)
                ->whereIn('status', $activeStatuses)
                ->exists();
        }

        if ($hasActiveTrip) {
            return response()->json([
                'success' => false,
                'state' => false,
                'message' => 'لا يمكن حذف الحساب أثناء وجود رحلة نشطة',
            ], 409);
        }

        if ($driver !== null) {
            $driver->forceDelete();
        }

        try {
            $user->tokens()->delete();
        } catch (\Throwable $e) {
        }

        try {
            \App\Services\CustomerPresenceService::clear((int) $user->id);
        } catch (\Throwable $e) {
        }

        $user->forceDelete();

        return response()->json([
            'success' => true,
            'state' => true,
            'message' => 'تم حذف الحساب',
        ]);
    }
}
