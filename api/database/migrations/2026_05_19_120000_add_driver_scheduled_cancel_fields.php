<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'driver_cancel_apology')) {
                $table->text('driver_cancel_apology')->nullable()->after('cancel_reason');
            }
            if (! Schema::hasColumn('requests', 'driver_cancelled_at')) {
                $table->timestamp('driver_cancelled_at')->nullable()->after('driver_cancel_apology');
            }
        });

        Schema::table('drivers', function (Blueprint $table) {
            if (! Schema::hasColumn('drivers', 'scheduled_cancel_strikes')) {
                $table->unsignedSmallInteger('scheduled_cancel_strikes')->default(0);
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (Schema::hasColumn('requests', 'driver_cancelled_at')) {
                $table->dropColumn('driver_cancelled_at');
            }
            if (Schema::hasColumn('requests', 'driver_cancel_apology')) {
                $table->dropColumn('driver_cancel_apology');
            }
        });

        Schema::table('drivers', function (Blueprint $table) {
            if (Schema::hasColumn('drivers', 'scheduled_cancel_strikes')) {
                $table->dropColumn('scheduled_cancel_strikes');
            }
        });
    }
};
