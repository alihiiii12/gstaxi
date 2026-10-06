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
        Schema::create('carTypes', function (Blueprint $table) {
            $table->increments('id');
            $table->string('name');
            $table->decimal('timePrice', 10, 2);
            $table->decimal('KMPrice',10,2);
            $table->decimal('openPrice',10,2);
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('carTypes');
    }
};
