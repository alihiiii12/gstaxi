<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('service_areas', function (Blueprint $table) {
            if (! Schema::hasColumn('service_areas', 'south_lat')) {
                $table->decimal('south_lat', 10, 7)->nullable()->after('sort_order');
            }
            if (! Schema::hasColumn('service_areas', 'north_lat')) {
                $table->decimal('north_lat', 10, 7)->nullable()->after('south_lat');
            }
            if (! Schema::hasColumn('service_areas', 'west_lng')) {
                $table->decimal('west_lng', 11, 7)->nullable()->after('north_lat');
            }
            if (! Schema::hasColumn('service_areas', 'east_lng')) {
                $table->decimal('east_lng', 11, 7)->nullable()->after('west_lng');
            }
        });

        if (Schema::hasTable('service_areas')) {
            DB::table('service_areas')->whereNull('south_lat')->update([
                'south_lat' => 33.4200000,
                'north_lat' => 33.5800000,
                'west_lng' => 36.1500000,
                'east_lng' => 36.4200000,
            ]);
        }

        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'service_area_id')) {
                $table->unsignedBigInteger('service_area_id')->nullable()->after('carTypeId');
            }
        });

        try {
            Schema::table('requests', function (Blueprint $table) {
                $table->foreign('service_area_id')
                    ->references('id')
                    ->on('service_areas')
                    ->nullOnDelete();
            });
        } catch (\Throwable $e) {
        }

        if (! Schema::hasTable('customer_notifications')) {
            Schema::create('customer_notifications', function (Blueprint $table) {
                $table->id();
                $table->unsignedInteger('user_id');
                $table->string('title');
                $table->text('body')->nullable();
                $table->string('kind', 32)->default('general');
                $table->string('reference_type', 32)->nullable();
                $table->unsignedBigInteger('reference_id')->nullable();
                $table->timestamp('read_at')->nullable();
                $table->timestamps();
                $table->index(['user_id', 'read_at']);

                $table->foreign('user_id')
                    ->references('id')
                    ->on('users')
                    ->cascadeOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_notifications');

        Schema::table('requests', function (Blueprint $table) {
            if (Schema::hasColumn('requests', 'service_area_id')) {
                try {
                    $table->dropForeign(['service_area_id']);
                } catch (\Throwable $e) {
                }
                $table->dropColumn('service_area_id');
            }
        });

        Schema::table('service_areas', function (Blueprint $table) {
            foreach (['south_lat', 'north_lat', 'west_lng', 'east_lng'] as $col) {
                if (Schema::hasColumn('service_areas', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
