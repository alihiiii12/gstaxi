<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * ترتيب ظهور الفئة عند الزبون + شارة الأيقونة (economy|suv|premium).
     */
    public function up(): void
    {
        Schema::table('carTypes', function (Blueprint $table) {
            if (! Schema::hasColumn('carTypes', 'sort_order')) {
                $table->unsignedSmallInteger('sort_order')->default(0)->after('openPrice');
            }
            if (! Schema::hasColumn('carTypes', 'customer_badge')) {
                $table->string('customer_badge', 32)->nullable()->after('sort_order');
            }
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('carTypes', function (Blueprint $table) {
            if (Schema::hasColumn('carTypes', 'customer_badge')) {
                $table->dropColumn('customer_badge');
            }
            if (Schema::hasColumn('carTypes', 'sort_order')) {
                $table->dropColumn('sort_order');
            }
        });
    }
};
