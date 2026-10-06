<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('drivers')) {
            return;
        }
        if (! Schema::hasColumn('drivers', 'receive_radius_km')) {
            Schema::table('drivers', function (Blueprint $table) {
                $table->unsignedTinyInteger('receive_radius_km')->default(1)->after('transTypeId');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('drivers') && Schema::hasColumn('drivers', 'receive_radius_km')) {
            Schema::table('drivers', function (Blueprint $table) {
                $table->dropColumn('receive_radius_km');
            });
        }
    }
};
