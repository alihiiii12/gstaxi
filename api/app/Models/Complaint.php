<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Complaint extends Model
{
    use HasFactory, SoftDeletes;

    protected $table = 'complaints';

    protected $primaryKey = 'id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'requestId',
        'driverId',
        'detail',
        'rating',
        'status',
        'cause'
    ];

    protected $casts = [
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
    ];

    // ثوابت الحالات
    const STATUS_PENDING = 'Pending';
    const STATUS_RESOLVED = 'Resolved';

    // العلاقات
    public function request()
    {
        return $this->belongsTo(RequestModel::class, 'requestId');
    }

    public function driver()
    {
        return $this->belongsTo(Driver::class, 'driverId');
    }

    // Scope للحالات المعلقة
    public function scopePending($query)
    {
        return $query->where('status', self::STATUS_PENDING);
    }

    // Scope للحالات المحلولة
    public function scopeResolved($query)
    {
        return $query->where('status', self::STATUS_RESOLVED);
    }

    // تغيير الحالة إلى محلولة
    public function markAsResolved($cause = null)
    {
        $this->status = self::STATUS_RESOLVED;
        if ($cause) {
            $this->cause = $cause;
        }
        return $this->save();
    }
}
