<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'sched_t30_sent_at')) {
                $table->timestamp('sched_t30_sent_at')->nullable()->after('cancel_reason');
            }
            if (! Schema::hasColumn('requests', 'sched_ready_sent_at')) {
                $table->timestamp('sched_ready_sent_at')->nullable()->after('sched_t30_sent_at');
            }
            if (! Schema::hasColumn('requests', 'sched_ready_deadline_at')) {
                $table->timestamp('sched_ready_deadline_at')->nullable()->after('sched_ready_sent_at');
            }
            if (! Schema::hasColumn('requests', 'sched_ready_answered_at')) {
                $table->timestamp('sched_ready_answered_at')->nullable()->after('sched_ready_deadline_at');
            }
            if (! Schema::hasColumn('requests', 'sched_driver_retry_at')) {
                $table->timestamp('sched_driver_retry_at')->nullable()->after('sched_ready_answered_at');
            }
        });

        if (Schema::hasTable('customer_notifications') && ! Schema::hasColumn('customer_notifications', 'payload')) {
            Schema::table('customer_notifications', function (Blueprint $table) {
                $table->json('payload')->nullable()->after('reference_id');
            });
        }

        if (! Schema::hasTable('driver_notifications')) {
            Schema::create('driver_notifications', function (Blueprint $table) {
                $table->id();
                $table->unsignedInteger('user_id');
                $table->string('title');
                $table->text('body')->nullable();
                $table->string('kind', 48)->default('general');
                $table->string('reference_type', 32)->nullable();
                $table->unsignedBigInteger('reference_id')->nullable();
                $table->json('payload')->nullable();
                $table->timestamp('read_at')->nullable();
                $table->timestamps();
                $table->index(['user_id', 'read_at']);

                $table->foreign('user_id')
                    ->references('id')
                    ->on('users')
                    ->cascadeOnDelete();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('driver_notifications');

        if (Schema::hasColumn('customer_notifications', 'payload')) {
            Schema::table('customer_notifications', function (Blueprint $table) {
                $table->dropColumn('payload');
            });
        }

        Schema::table('requests', function (Blueprint $table) {
            foreach ([
                'sched_driver_retry_at',
                'sched_ready_answered_at',
                'sched_ready_deadline_at',
                'sched_ready_sent_at',
                'sched_t30_sent_at',
            ] as $col) {
                if (Schema::hasColumn('requests', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
