<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'accepted_at')) {
                $table->timestamp('accepted_at')->nullable()->after('trip_started_at');
            }
            if (! Schema::hasColumn('requests', 'arrived_at')) {
                $table->timestamp('arrived_at')->nullable()->after('accepted_at');
            }
            if (! Schema::hasColumn('requests', 'trip_ended_at')) {
                $table->timestamp('trip_ended_at')->nullable()->after('arrived_at');
            }
            if (! Schema::hasColumn('requests', 'accept_lat')) {
                $table->decimal('accept_lat', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'accept_lng')) {
                $table->decimal('accept_lng', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'actual_start_lat')) {
                $table->decimal('actual_start_lat', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'actual_start_lng')) {
                $table->decimal('actual_start_lng', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'actual_end_lat')) {
                $table->decimal('actual_end_lat', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'actual_end_lng')) {
                $table->decimal('actual_end_lng', 10, 7)->nullable();
            }
            if (! Schema::hasColumn('requests', 'driver_to_pickup_km')) {
                $table->decimal('driver_to_pickup_km', 8, 3)->nullable();
            }
            if (! Schema::hasColumn('requests', 'estimated_distance_km')) {
                $table->decimal('estimated_distance_km', 8, 3)->nullable();
            }
        });

        Schema::table('requestHistories', function (Blueprint $table) {
            if (! Schema::hasColumn('requestHistories', 'driver_customer_rating')) {
                $table->unsignedTinyInteger('driver_customer_rating')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            foreach ([
                'accepted_at', 'arrived_at', 'trip_ended_at',
                'accept_lat', 'accept_lng',
                'actual_start_lat', 'actual_start_lng',
                'actual_end_lat', 'actual_end_lng',
                'driver_to_pickup_km', 'estimated_distance_km',
            ] as $col) {
                if (Schema::hasColumn('requests', $col)) {
                    $table->dropColumn($col);
                }
            }
        });

        if (Schema::hasColumn('requestHistories', 'driver_customer_rating')) {
            Schema::table('requestHistories', function (Blueprint $table) {
                $table->dropColumn('driver_customer_rating');
            });
        }
    }
};
