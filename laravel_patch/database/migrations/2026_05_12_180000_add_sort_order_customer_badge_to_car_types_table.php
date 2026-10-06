<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * أضف إلى مشروع Laravel ثم: php artisan migrate
 *
 * بعد الهجرة، في نموذج CarType أضف إلى $fillable:
 *   'sort_order', 'customer_badge',
 *
 * وفي Form Request لمسارات car-types/store و car-types/update:
 *   'sort_order' => ['nullable', 'integer', 'min:0', 'max:65535'],
 *   'customer_badge' => ['nullable', 'string', 'max:32', 'in:economy,suv,premium'],
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('car_types')) {
            return;
        }

        Schema::table('car_types', function (Blueprint $table) {
            if (!Schema::hasColumn('car_types', 'sort_order')) {
                $table->unsignedSmallInteger('sort_order')->default(0);
            }
            if (!Schema::hasColumn('car_types', 'customer_badge')) {
                $table->string('customer_badge', 32)->nullable();
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('car_types')) {
            return;
        }

        Schema::table('car_types', function (Blueprint $table) {
            if (Schema::hasColumn('car_types', 'customer_badge')) {
                $table->dropColumn('customer_badge');
            }
            if (Schema::hasColumn('car_types', 'sort_order')) {
                $table->dropColumn('sort_order');
            }
        });
    }
};
