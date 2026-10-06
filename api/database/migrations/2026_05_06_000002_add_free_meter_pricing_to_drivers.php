<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->decimal('freeOpenPrice', 10, 2)->nullable()->after('type');
            $table->decimal('freeKMPrice', 10, 2)->nullable()->after('freeOpenPrice');
            $table->decimal('freeTimePrice', 10, 2)->nullable()->after('freeKMPrice');
        });
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->dropColumn(['freeOpenPrice', 'freeKMPrice', 'freeTimePrice']);
        });
    }
};

