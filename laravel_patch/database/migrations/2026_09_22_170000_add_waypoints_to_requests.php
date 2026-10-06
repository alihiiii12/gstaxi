<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('requests')) {
            return;
        }
        if (! Schema::hasColumn('requests', 'waypoints')) {
            Schema::table('requests', function (Blueprint $table) {
                $table->json('waypoints')->nullable()->after('locationDesc');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('requests') && Schema::hasColumn('requests', 'waypoints')) {
            Schema::table('requests', function (Blueprint $table) {
                $table->dropColumn('waypoints');
            });
        }
    }
};
