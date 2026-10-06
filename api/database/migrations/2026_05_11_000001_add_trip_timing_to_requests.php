<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            $table->timestamp('trip_started_at')->nullable()->after('predectedCost');
            $table->decimal('estimated_duration_minutes', 10, 2)->nullable()->after('trip_started_at');
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            $table->dropColumn(['trip_started_at', 'estimated_duration_minutes']);
        });
    }
};
