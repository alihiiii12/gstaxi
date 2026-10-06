<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('discounts', 'max_discount')) {
            Schema::table('discounts', function (Blueprint $table) {
                $table->decimal('max_discount', 14, 2)->nullable()->after('type');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('discounts', 'max_discount')) {
            Schema::table('discounts', function (Blueprint $table) {
                $table->dropColumn('max_discount');
            });
        }
    }
};
