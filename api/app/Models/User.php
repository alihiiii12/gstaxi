<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;  // مهم للتوكنات
use Illuminate\Database\Eloquent\SoftDeletes;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, SoftDeletes;

    protected static function booted(): void
    {
        static::creating(function (User $user) {
            if (filled($user->number)) {
                static::releaseNumberFromDeleted((string) $user->number);
            }
        });
    }

    /**
     * حساب محذوف (soft delete) يبقى حاجزاً للرقم بسبب users_number_unique — نحرّر الرقم
     * مع إبقاء السجل وتاريخه، كي يستطيع صاحب الرقم التسجيل من جديد.
     */
    public static function releaseNumberFromDeleted(string $number): void
    {
        static::onlyTrashed()
            ->where('number', $number)
            ->get()
            ->each(fn (User $old) => $old->forceFill(['number' => 'del'.$old->id])->saveQuietly());
    }

    /**
     * The attributes that are mass assignable.
     *
     * @var array<int, string>
     */
    protected $fillable = [
        'number',        // رقم الهاتف (فريد)
        'firstName',     // الاسم الأول
        'lastName',      // الاسم الأخير
        'password',      // كلمة المرور
        'roll',          // الدور: Admin, Driver, Customer, Employee
        'permissions',   // صلاحيات للموظف (JSON)
        'banned',        // حالة الحظر
        'expireDate',    // تاريخ انتهاء الصلاحية
        'phone_verified_at',
        'fcm_token',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var array<int, string>
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * The attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'permissions' => 'array',
            'banned' => 'boolean',
            'expireDate' => 'datetime',
            'phone_verified_at' => 'datetime',
            'created_at' => 'datetime',
            'updated_at' => 'datetime',
            'deleted_at' => 'datetime',
        ];
    }

    /**
     * Get the user's full name.
     */
    public function getFullNameAttribute(): string
    {
        return $this->firstName . ' ' . $this->lastName;
    }

    /**
     * Check if user is admin.
     */
    public function isAdmin(): bool
    {
        return $this->roll === 'Admin';
    }

    /**
     * Check if user is driver.
     */
    public function isDriver(): bool
    {
        return $this->roll == 'Driver';
    }

    /**
     * Check if user is customer.
     */
    public function isCustomer(): bool
    {
        return $this->roll == 'Customer';
    }

    /**
     * لوحة الإدارة: مسؤول أو موظف.
     */
    public function isBackofficeStaff(): bool
    {
        return in_array($this->roll, ['Admin', 'Employee'], true);
    }

    /**
     * للمسؤول: كل الصلاحيات. للموظف: من عمود permissions فقط.
     */
    public function hasStaffPermission(string $permission): bool
    {
        if ($this->roll === 'Admin') {
            return true;
        }

        if ($this->roll !== 'Employee') {
            return false;
        }

        $perms = is_array($this->permissions) ? $this->permissions : [];

        if (in_array($permission, $perms, true)) {
            return true;
        }

        // صلاحية الكتابة تتضمن عادةً قراءة نفس المجال
        $implies = [
            'areas.read' => 'areas.write',
            'drivers.read' => 'drivers.write',
            'requests.read' => 'requests.write',
            'customers.read' => 'customers.wallet',
        ];

        if (isset($implies[$permission]) && in_array($implies[$permission], $perms, true)) {
            return true;
        }

        return false;
    }

    /**
     * Check if user is banned.
     */
    public function isBanned(): bool
    {
        return $this->banned == true;
    }

    /**
     * Get the driver record associated with the user.
     */
    public function driver()
    {
        return $this->hasOne(Driver::class, 'userId');
    }

    /**
     * Get the requests for the user.
     */
    public function requests()
    {
        return $this->hasMany(RequestModel::class, 'userId');
    }

    /**
     * Get the rates for the user.
     */
    public function rates()
    {
        return $this->hasMany(Rate::class, 'userId');
    }

    /**
     * Get the complaints for the user.
     */
    public function complaints()
    {
        return $this->hasMany(Complaint::class, 'userId');
    }

    /**
     * Get the used discounts for the user.
     */
    public function usedDiscounts()
    {
        return $this->hasMany(UsedDiscount::class, 'userId');
    }
}
