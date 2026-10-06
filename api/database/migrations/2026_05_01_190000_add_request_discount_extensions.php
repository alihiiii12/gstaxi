<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            $table->boolean('reminder_sent')->default(false)->after('predectedCost');
            $table->string('cancel_reason')->nullable()->after('reminder_sent');
        });

        Schema::table('discounts', function (Blueprint $table) {
            $table->json('target_phones')->nullable()->after('type');
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            $table->dropColumn(['reminder_sent', 'cancel_reason']);
        });

        Schema::table('discounts', function (Blueprint $table) {
            $table->dropColumn('target_phones');
        });
    }
};
