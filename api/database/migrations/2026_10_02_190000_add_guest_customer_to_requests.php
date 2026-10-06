<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'guest_first_name')) {
                $table->string('guest_first_name', 80)->nullable();
            }
            if (! Schema::hasColumn('requests', 'guest_last_name')) {
                $table->string('guest_last_name', 80)->nullable();
            }
            if (! Schema::hasColumn('requests', 'guest_phone')) {
                $table->string('guest_phone', 40)->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            foreach (['guest_first_name', 'guest_last_name', 'guest_phone'] as $col) {
                if (Schema::hasColumn('requests', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
