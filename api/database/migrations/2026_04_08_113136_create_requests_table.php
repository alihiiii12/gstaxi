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
        Schema::create('requests', function (Blueprint $table) {
            $table->increments('id');
            $table->integer('userId')->unsigned();
            $table->integer('driverId')->unsigned()->nullable();
            $table->integer('carTypeId')->unsigned();
            $table->enum('type',['Schedual','Immediate']);
            $table->enum('status',['Pending','Running','Finished','Removed','Reserved']);
            $table->integer('startLocationId')->unsigned();
            $table->integer('destLocationId')->unsigned();
            $table->dateTime('requestDate');
            $table->text('locationDesc')->nullable();
            $table->decimal('predectedCost', 10, 2)->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('requests');
    }
};
