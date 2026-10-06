<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            if (! Schema::hasColumn('drivers', 'subscription_ends_at')) {
                $table->timestamp('subscription_ends_at')->nullable()->after('updated_at');
            }
            if (! Schema::hasColumn('drivers', 'subscription_blocked')) {
                $table->boolean('subscription_blocked')->default(false)->after('subscription_ends_at');
            }
            if (! Schema::hasColumn('drivers', 'subscription_reminder_sent_at')) {
                $table->timestamp('subscription_reminder_sent_at')->nullable()->after('subscription_blocked');
            }
        });

        // اشتراك 30 يوم من تاريخ إضافة السائق (created_at)
        DB::statement("
            UPDATE drivers
            SET subscription_ends_at = DATE_ADD(COALESCE(created_at, NOW()), INTERVAL 30 DAY),
                subscription_blocked = CASE
                    WHEN DATE_ADD(COALESCE(created_at, NOW()), INTERVAL 30 DAY) < NOW() THEN 1
                    ELSE 0
                END
            WHERE subscription_ends_at IS NULL
        ");
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $cols = ['subscription_reminder_sent_at', 'subscription_blocked', 'subscription_ends_at'];
            foreach ($cols as $col) {
                if (Schema::hasColumn('drivers', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
