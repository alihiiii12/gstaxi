<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('requestHistories', function (Blueprint $table) {
            $table->increments('id');
            $table->integer('requestId')->unsigned();
            $table->integer('driverId')->unsigned();
            $table->decimal('finalCost', 10, 2);
            $table->integer('descountId')->unsigned()->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('requestHistories');
    }
};
