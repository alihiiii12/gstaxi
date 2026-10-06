<?php

namespace App\Models;

use DateTimeInterface;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Carbon;

class RequestModel extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'requests';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'userId',
        'carTypeId',
        'service_area_id',
        'zone_multiplier',
        'pickup_zone_name',
        'dest_zone_name',
        'type',
        'status',
        'startLocationId',
        'destLocationId',
        'requestDate',
        'locationDesc',
        'waypoints',
        'driverId',
        'predectedCost',
        'trip_started_at',
        'accepted_at',
        'arrived_at',
        'trip_ended_at',
        'accept_lat',
        'accept_lng',
        'actual_start_lat',
        'actual_start_lng',
        'actual_end_lat',
        'actual_end_lng',
        'driver_to_pickup_km',
        'estimated_distance_km',
        'estimated_duration_minutes',
        'discountId',
        'discountCode',
        'discountType',
        'discountValue',
        'reminder_sent',
        'cancel_reason',
        'driver_cancel_apology',
        'driver_cancelled_at',
        'sched_t30_sent_at',
        'sched_at_time_sent_at',
        'sched_ready_sent_at',
        'sched_ready_deadline_at',
        'sched_ready_answered_at',
        'sched_driver_retry_at',
        'sched_driver_deferred_at',
        'sched_driver_response_deadline_at',
        'sched_driver_started_at',
        'billing_kind',
        'is_app_request',
        'free_meter_had_movement',
        'free_meter_counts_for_revenue',
        'payment_method',
        'wallet_paid_amount',
        'cash_due_amount',
        'payment_settled_at',
        'guest_first_name',
        'guest_last_name',
        'guest_phone',
    ];

    protected $casts = [
        'requestDate' => 'datetime',
        'predectedCost' => 'decimal:2',
        'estimated_duration_minutes' => 'decimal:2',
        'trip_started_at' => 'datetime',
        'accepted_at' => 'datetime',
        'arrived_at' => 'datetime',
        'trip_ended_at' => 'datetime',
        'accept_lat' => 'float',
        'accept_lng' => 'float',
        'actual_start_lat' => 'float',
        'actual_start_lng' => 'float',
        'actual_end_lat' => 'float',
        'actual_end_lng' => 'float',
        'driver_to_pickup_km' => 'decimal:3',
        'estimated_distance_km' => 'decimal:3',
        'discountValue' => 'decimal:2',
        'reminder_sent' => 'boolean',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
        'sched_t30_sent_at' => 'datetime',
        'sched_at_time_sent_at' => 'datetime',
        'sched_ready_sent_at' => 'datetime',
        'sched_ready_deadline_at' => 'datetime',
        'sched_ready_answered_at' => 'datetime',
        'sched_driver_retry_at' => 'datetime',
        'sched_driver_deferred_at' => 'datetime',
        'sched_driver_response_deadline_at' => 'datetime',
        'sched_driver_started_at' => 'datetime',
        'driver_cancelled_at' => 'datetime',
        'is_app_request' => 'boolean',
        'free_meter_had_movement' => 'boolean',
        'free_meter_counts_for_revenue' => 'boolean',
        'waypoints' => 'array',
        'wallet_paid_amount' => 'decimal:2',
        'cash_due_amount' => 'decimal:2',
        'payment_settled_at' => 'datetime',
    ];

    // ثوابت أنواع الطلب
    const TYPE_SCHEDULE = 'Schedual';
    const TYPE_IMMEDIATE = 'Immediate';

    // ثوابت حالات الطلب
    const STATUS_PENDING = 'Pending';
    const STATUS_RUNNING = 'Running';
    const STATUS_FINISHED = 'Finished';
    const STATUS_REMOVED = 'Removed';
    const STATUS_RESERVED = 'Reserved'; // حالة إضافية للحجز المسبق
    const STATUS_DRIVER_ARRIVED = 'DriverArrived';
    const STATUS_AWAITING_DESTINATION = 'AwaitingDestination';

    /** نافذة «انطلق للراكب» قبل موعد الحجز المسبق؛ قبلها السائق حرّ لطلبات فورية/عداد حر. */
    public const SCHED_GO_WINDOW_MINUTES = 30;

    /** دقائق بعد الموعد دون انطلاق السائق قبل إلغاء الحجز تلقائياً. */
    public const SCHED_NO_GO_CANCEL_AFTER_MINUTES = 20;

    protected $appends = ['sched_go_window_open', 'request_date_ms'];

    /** حجز مسبق مقبول لم ينطلق السائق إليه بعد. */
    public static function scheduledAwaitingGo(self $req): bool
    {
        return $req->type === self::TYPE_SCHEDULE
            && self::normalizeTripStatus($req->status) === self::STATUS_RESERVED
            && $req->sched_driver_started_at === null;
    }

    public static function schedGoWindowOpen(self $req): bool
    {
        if (! self::scheduledAwaitingGo($req)) {
            return false;
        }
        if (! $req->requestDate) {
            return true;
        }

        return now()->gte($req->requestDate->copy()->subMinutes(self::SCHED_GO_WINDOW_MINUTES));
    }

    public function getSchedGoWindowOpenAttribute(): bool
    {
        return self::schedGoWindowOpen($this);
    }

    public function getRequestDateMsAttribute(): ?int
    {
        return $this->requestDate ? $this->requestDate->getTimestamp() * 1000 : null;
    }

    /**
     * طلبات تشغل السائق فعلياً (تمنع استقبال فوري جديد وتشغيل العداد الحر).
     * الحجز المسبق المقبول لا يشغله إلا بعد الانطلاق أو داخل نافذة الـ 30 دقيقة.
     */
    public function scopeOccupyingDriver($query)
    {
        return $query
            ->whereIn('status', [
                self::STATUS_PENDING,
                self::STATUS_RESERVED,
                self::STATUS_DRIVER_ARRIVED,
                self::STATUS_AWAITING_DESTINATION,
                self::STATUS_RUNNING,
            ])
            ->where(function ($w) {
                $w->whereNull('type')
                    ->orWhere('type', '!=', self::TYPE_SCHEDULE)
                    ->orWhereIn('status', [
                        self::STATUS_DRIVER_ARRIVED,
                        self::STATUS_AWAITING_DESTINATION,
                        self::STATUS_RUNNING,
                    ])
                    ->orWhere(function ($r) {
                        $r->where('status', self::STATUS_RESERVED)
                            ->where(function ($x) {
                                $x->whereNotNull('sched_driver_started_at')
                                    ->orWhereNull('requestDate')
                                    ->orWhere('requestDate', '<=', now()->addMinutes(self::SCHED_GO_WINDOW_MINUTES));
                            });
                    });
            });
    }

    public static function normalizeTripStatus(?string $status): string
    {
        $raw = trim((string) $status);
        if ($raw === '') {
            return '';
        }
        $key = strtolower(str_replace(['_', ' ', '-'], '', $raw));
        $map = [
            'pending' => self::STATUS_PENDING,
            'reserved' => self::STATUS_RESERVED,
            'driverarrived' => self::STATUS_DRIVER_ARRIVED,
            'awaitingdestination' => self::STATUS_AWAITING_DESTINATION,
            'running' => self::STATUS_RUNNING,
            'finished' => self::STATUS_FINISHED,
            'removed' => self::STATUS_REMOVED,
        ];

        return $map[$key] ?? $raw;
    }

    /** السائق يمكنه بدء الرحلة (ما عدا المنتهية/الملغاة/الجارية فعلياً). */
    public static function canDriverStartTrip(self $req): bool
    {
        $s = self::normalizeTripStatus($req->status);
        if (in_array($s, [self::STATUS_FINISHED, self::STATUS_REMOVED], true)) {
            return false;
        }
        if ($s === self::STATUS_RUNNING && $req->trip_started_at !== null) {
            return false;
        }
        if ($req->type === self::TYPE_SCHEDULE
            && $req->sched_driver_started_at === null
            && $s === self::STATUS_RESERVED) {
            return false;
        }
        // حجز مسبق: لا بدء فعلي قبل فتح نافذة الانطلاق (30 د قبل الموعد).
        if ($req->type === self::TYPE_SCHEDULE && $req->requestDate) {
            $earliest = $req->requestDate->copy()->subMinutes(self::SCHED_GO_WINDOW_MINUTES);
            if (now()->lt($earliest)) {
                return false;
            }
        }

        return (int) $req->driverId > 0;
    }

    /** إلغاء/إنهاء قبل بدء الرحلة فعلياً (حتى لو علقت الحالة). */
    public static function canAbortTrip(self $req): bool
    {
        $s = self::normalizeTripStatus($req->status);
        if (in_array($s, [self::STATUS_FINISHED, self::STATUS_REMOVED], true)) {
            return false;
        }
        if ($s === self::STATUS_RUNNING && $req->trip_started_at !== null) {
            return false;
        }

        return true;
    }

    /** طلب أُنشئ من لوحة الإدارة وإُرسل لسائق محدد */
    public static function isAdminDispatched(self $req): bool
    {
        $desc = trim((string) ($req->locationDesc ?? ''));
        if ($desc === '') {
            return false;
        }

        return str_contains($desc, 'لوحة الإدارة')
            || str_contains($desc, 'admin_dispatch');
    }

    /** طلب عبر تطبيق الزبون — التسعير عادةً حسب المسار/الوجهة. */
    public const BILLING_KIND_APP_REQUEST = 'app_request';

    /** رحلة بعداد حر — التكلفة النهائية من السائق/العداد. */
    public const BILLING_KIND_FREE_METER = 'free_meter';

    /** زبون غير مسجّل أُدخل يدوياً من لوحة الإدارة (الطلب مربوط بالحساب النظامي). */
    public function hasGuestCustomer(): bool
    {
        return trim((string) ($this->guest_phone ?? '')) !== ''
            || trim((string) ($this->guest_first_name ?? '')) !== ''
            || trim((string) ($this->guest_last_name ?? '')) !== '';
    }

    public function toArray()
    {
        $arr = parent::toArray();
        if ($this->hasGuestCustomer()) {
            $arr['is_guest_customer'] = true;
            if (isset($arr['user']) && is_array($arr['user'])) {
                $arr['user']['firstName'] = (string) ($this->guest_first_name ?? '');
                $arr['user']['lastName'] = (string) ($this->guest_last_name ?? '');
                $arr['user']['number'] = $this->guest_phone;
            }
        }

        return $arr;
    }

    protected function serializeDate(DateTimeInterface $date): string
    {
        return Carbon::instance($date)
            ->timezone(config('app.timezone', 'Asia/Damascus'))
            ->format('Y-m-d H:i:s');
    }

    // العلاقات
    public function user()
    {
        return $this->belongsTo(User::class, 'userId');
    }

    public function driver()
    {
        return $this->belongsTo(Driver::class, 'driverId');
    }

    public function carType()
    {
        return $this->belongsTo(CarType::class, 'carTypeId');
    }

    public function startLocation()
    {
        return $this->belongsTo(Location::class, 'startLocationId');
    }

    public function destLocation()
    {
        return $this->belongsTo(Location::class, 'destLocationId');
    }

    public function history()
    {
        return $this->hasOne(RequestHistory::class, 'requestId');
    }

    public function discount()
    {
        return $this->belongsTo(Discount::class, 'discountId');
    }

    public function serviceArea()
    {
        return $this->belongsTo(ServiceArea::class, 'service_area_id');
    }

    public function driverOffers()
    {
        return $this->hasMany(RequestDriverOffer::class, 'request_id');
    }

    public function complaints()
    {
        return $this->hasMany(Complaint::class, 'requestId');
    }

    // Scope للحجوزات المسبقة
    public function scopeScheduled($query)
    {
        return $query->where('type', self::TYPE_SCHEDULE);
    }

    // Scope للطلبات الفورية
    public function scopeImmediate($query)
    {
        return $query->where('type', self::TYPE_IMMEDIATE);
    }

    /**
     * هل تُحسب تكلفة هذه الرحلة ضمن إجمالي الإيراد في لوحة التقارير؟
     * رحلات العداد الحر التي توقفت على السعر الافتتاحي فقط (بدون حركة) تُستثنى.
     */
    public static function countsTowardPlatformRevenue(?self $row): bool
    {
        if (! $row) {
            return false;
        }
        if ($row->billing_kind !== self::BILLING_KIND_FREE_METER) {
            return true;
        }
        if ($row->free_meter_counts_for_revenue === null) {
            return true;
        }

        return (bool) $row->free_meter_counts_for_revenue;
    }

    // Scope للطلبات المنتظرة
    public function scopePending($query)
    {
        return $query->where('status', self::STATUS_PENDING);
    }
}
