<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            // discounts.id is an unsigned INT (increments)
            if (!Schema::hasColumn('requests', 'discountId')) {
                $table->unsignedInteger('discountId')->nullable()->after('predectedCost');
            }
            if (!Schema::hasColumn('requests', 'discountCode')) {
                $table->string('discountCode')->nullable()->after('discountId');
            }
            if (!Schema::hasColumn('requests', 'discountType')) {
                $table->string('discountType')->nullable()->after('discountCode');
            }
            if (!Schema::hasColumn('requests', 'discountValue')) {
                $table->decimal('discountValue', 10, 2)->nullable()->after('discountType');
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            $cols = [];
            foreach (['discountId', 'discountCode', 'discountType', 'discountValue'] as $c) {
                if (Schema::hasColumn('requests', $c)) $cols[] = $c;
            }
            if (!empty($cols)) {
                $table->dropColumn($cols);
            }
        });
    }
};

