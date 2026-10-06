<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('pricing_zones')) {
            Schema::create('pricing_zones', function (Blueprint $table) {
                $table->id();
                $table->string('name', 80);
                /** [[lat, lng], ...] */
                $table->json('polygon');
                $table->string('color', 16)->default('#1a2f75');
                $table->boolean('is_active')->default(true);
                $table->integer('sort_order')->default(0);
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('pricing_zone_rules')) {
            Schema::create('pricing_zone_rules', function (Blueprint $table) {
                $table->id();
                /** 0 = خارج كل المناطق (الريف) */
                $table->unsignedBigInteger('from_zone_id')->default(0);
                $table->unsignedBigInteger('to_zone_id')->default(0);
                $table->decimal('multiplier', 6, 3)->default(1);
                $table->timestamps();
                $table->unique(['from_zone_id', 'to_zone_id']);
            });
        }

        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'zone_multiplier')) {
                $table->decimal('zone_multiplier', 6, 3)->nullable();
            }
            if (! Schema::hasColumn('requests', 'pickup_zone_name')) {
                $table->string('pickup_zone_name', 80)->nullable();
            }
            if (! Schema::hasColumn('requests', 'dest_zone_name')) {
                $table->string('dest_zone_name', 80)->nullable();
            }
        });

        if (DB::table('pricing_zones')->count() === 0) {
            $file = database_path('data/damascus_city_polygon.json');
            $polygon = is_readable($file) ? json_decode((string) file_get_contents($file), true) : null;
            if (is_array($polygon) && count($polygon) >= 3) {
                $cityId = DB::table('pricing_zones')->insertGetId([
                    'name' => 'مدينة دمشق',
                    'polygon' => json_encode($polygon),
                    'color' => '#1a2f75',
                    'is_active' => true,
                    'sort_order' => 0,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                $rows = [
                    [$cityId, $cityId, 1.0],
                    [$cityId, 0, 1.5],
                    [0, $cityId, 1.0],
                    [0, 0, 1.0],
                ];
                foreach ($rows as [$from, $to, $m]) {
                    DB::table('pricing_zone_rules')->insert([
                        'from_zone_id' => $from,
                        'to_zone_id' => $to,
                        'multiplier' => $m,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }
        }
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            foreach (['zone_multiplier', 'pickup_zone_name', 'dest_zone_name'] as $c) {
                if (Schema::hasColumn('requests', $c)) {
                    $table->dropColumn($c);
                }
            }
        });
        Schema::dropIfExists('pricing_zone_rules');
        Schema::dropIfExists('pricing_zones');
    }
};
