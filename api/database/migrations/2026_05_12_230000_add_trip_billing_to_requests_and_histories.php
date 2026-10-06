<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'billing_kind')) {
                $table->string('billing_kind', 32)->nullable()->after('discountValue');
            }
            if (! Schema::hasColumn('requests', 'is_app_request')) {
                $table->boolean('is_app_request')->nullable()->after('billing_kind');
            }
            if (! Schema::hasColumn('requests', 'free_meter_had_movement')) {
                $table->boolean('free_meter_had_movement')->nullable()->after('is_app_request');
            }
            if (! Schema::hasColumn('requests', 'free_meter_counts_for_revenue')) {
                $table->boolean('free_meter_counts_for_revenue')->nullable()->after('free_meter_had_movement');
            }
        });

        Schema::table('requestHistories', function (Blueprint $table) {
            if (! Schema::hasColumn('requestHistories', 'distanceTraveledKm')) {
                $table->decimal('distanceTraveledKm', 10, 3)->nullable()->after('finalCost');
            }
        });
    }

    public function down(): void
    {
        Schema::table('requestHistories', function (Blueprint $table) {
            if (Schema::hasColumn('requestHistories', 'distanceTraveledKm')) {
                $table->dropColumn('distanceTraveledKm');
            }
        });

        Schema::table('requests', function (Blueprint $table) {
            foreach (['free_meter_counts_for_revenue', 'free_meter_had_movement', 'is_app_request', 'billing_kind'] as $col) {
                if (Schema::hasColumn('requests', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
