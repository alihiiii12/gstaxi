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
        Schema::create('usedDiscounts', function (Blueprint $table) {
            $table->increments('id');
            $table->integer('requestId')->unsigned();
            $table->integer('userId')->unsigned();
            $table->integer('discountId')->unsigned();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('usedDiscounts');
    }
};
