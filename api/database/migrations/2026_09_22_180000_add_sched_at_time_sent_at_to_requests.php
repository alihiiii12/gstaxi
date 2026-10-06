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
        if (! Schema::hasColumn('requests', 'sched_at_time_sent_at')) {
            Schema::table('requests', function (Blueprint $table) {
                $table->timestamp('sched_at_time_sent_at')->nullable()->after('sched_t30_sent_at');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('requests') && Schema::hasColumn('requests', 'sched_at_time_sent_at')) {
            Schema::table('requests', function (Blueprint $table) {
                $table->dropColumn('sched_at_time_sent_at');
            });
        }
    }
};
