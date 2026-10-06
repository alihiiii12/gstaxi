<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // MariaDB/MySQL: extend roll enum with Employee
        DB::statement("ALTER TABLE `users` MODIFY `roll` ENUM('Admin','Driver','Customer','Employee') NOT NULL");

        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'permissions')) {
                $table->json('permissions')->nullable()->after('roll');
            }
        });

        Schema::table('discounts', function (Blueprint $table) {
            if (! Schema::hasColumn('discounts', 'valid_from')) {
                $table->dateTime('valid_from')->nullable()->after('target_phones');
            }
            if (! Schema::hasColumn('discounts', 'valid_until')) {
                $table->dateTime('valid_until')->nullable()->after('valid_from');
            }
        });

        Schema::create('service_areas', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->boolean('active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->timestamps();
        });

        $now = now();
        DB::table('service_areas')->insert([
            ['name' => 'دمشق — وسط المدينة', 'active' => true, 'sort_order' => 10, 'created_at' => $now, 'updated_at' => $now],
            ['name' => 'ريف دمشق — جسرين والنواعير', 'active' => true, 'sort_order' => 20, 'created_at' => $now, 'updated_at' => $now],
            ['name' => 'ريف دمشق — داريا والمعضمية', 'active' => true, 'sort_order' => 30, 'created_at' => $now, 'updated_at' => $now],
            ['name' => 'ريف دمشق — حرستا والقطيفة', 'active' => true, 'sort_order' => 40, 'created_at' => $now, 'updated_at' => $now],
            ['name' => 'ريف دمشق — جرمانا والحميدية', 'active' => true, 'sort_order' => 50, 'created_at' => $now, 'updated_at' => $now],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('service_areas');

        Schema::table('discounts', function (Blueprint $table) {
            if (Schema::hasColumn('discounts', 'valid_until')) {
                $table->dropColumn('valid_until');
            }
            if (Schema::hasColumn('discounts', 'valid_from')) {
                $table->dropColumn('valid_from');
            }
        });

        Schema::table('users', function (Blueprint $table) {
            if (Schema::hasColumn('users', 'permissions')) {
                $table->dropColumn('permissions');
            }
        });

        DB::statement("ALTER TABLE `users` MODIFY `roll` ENUM('Admin','Driver','Customer') NOT NULL");
    }
};
