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
            if (! Schema::hasColumn('drivers', 'subscription_starts_at')) {
                $table->timestamp('subscription_starts_at')->nullable()->after('subscription_ends_at');
            }
        });

        DB::statement("
            UPDATE drivers
            SET subscription_starts_at = COALESCE(
                DATE_SUB(subscription_ends_at, INTERVAL 30 DAY),
                created_at,
                NOW()
            )
            WHERE subscription_starts_at IS NULL
        ");
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            if (Schema::hasColumn('drivers', 'subscription_starts_at')) {
                $table->dropColumn('subscription_starts_at');
            }
        });
    }
};
