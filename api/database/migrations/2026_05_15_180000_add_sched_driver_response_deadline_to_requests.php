<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'sched_driver_response_deadline_at')) {
                $table->timestamp('sched_driver_response_deadline_at')
                    ->nullable()
                    ->after('sched_driver_deferred_at');
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (Schema::hasColumn('requests', 'sched_driver_response_deadline_at')) {
                $table->dropColumn('sched_driver_response_deadline_at');
            }
        });
    }
};
