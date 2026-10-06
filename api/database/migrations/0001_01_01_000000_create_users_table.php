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
        Schema::create('users', function (Blueprint $table) {
            $table->increments('id');
            $table->string('number', 14)->unique();
            $table->string('password');
            $table->enum('roll', ['Admin', 'Driver', 'Customer']);
            $table->string('firstName');
            $table->string('lastName');
            $table->boolean('banned')->default(false);
            $table->date('expireDate')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('users');
    }
};
