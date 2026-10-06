<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('discounts', 'max_uses_per_user')) {
            Schema::table('discounts', function (Blueprint $table) {
                /** null = غير محدود */
                $table->unsignedInteger('max_uses_per_user')->nullable()->default(1)->after('max_discount');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('discounts', 'max_uses_per_user')) {
            Schema::table('discounts', function (Blueprint $table) {
                $table->dropColumn('max_uses_per_user');
            });
        }
    }
};
