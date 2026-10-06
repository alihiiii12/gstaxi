<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('request_driver_offers', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('request_id');
            $table->unsignedInteger('driver_id');
            $table->timestamps();

            $table->unique(['request_id', 'driver_id']);
            $table->index('request_id');
            $table->index('driver_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('request_driver_offers');
    }
};
