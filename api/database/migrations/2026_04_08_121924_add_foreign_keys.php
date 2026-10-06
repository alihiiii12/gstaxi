<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // drivers
        Schema::table('drivers', function (Blueprint $table) {
            $table->foreign('userId')
                ->references('id')->on('users')
                ->onDelete('cascade')
                ->onUpdate('restrict');
            $table->foreign('transTypeId')
                ->references('id')->on('carTypes')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // requests
        Schema::table('requests', function (Blueprint $table) {
            $table->foreign('userId')
                ->references('id')->on('users')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('DriverId')
                ->references('id')->on('drivers')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('carTypeId')
                ->references('id')->on('carTypes')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('startLocationId')
                ->references('id')->on('locations')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('destLocationId')
                ->references('id')->on('locations')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // requestHistories
        Schema::table('requestHistories', function (Blueprint $table) {
            $table->foreign('requestId')
                ->references('id')->on('requests')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('driverId')
                ->references('id')->on('drivers')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('descountId')
                ->references('id')->on('discounts')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // usedDiscounts
        Schema::table('usedDiscounts', function (Blueprint $table) {
            $table->foreign('requestId')
                ->references('id')->on('requests')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('userId')
                ->references('id')->on('users')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('discountId')
                ->references('id')->on('discounts')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // rates
        Schema::table('rates', function (Blueprint $table) {
            $table->foreign('userId')
                ->references('id')->on('users')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('driverId')
                ->references('id')->on('drivers')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // complaints
        Schema::table('complaints', function (Blueprint $table) {
            $table->foreign('requestId')
                ->references('id')->on('requests')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('driverId')
                ->references('id')->on('drivers')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });

        // userapiAccesses
        Schema::table('userapiAccesses', function (Blueprint $table) {
            $table->foreign('userId')
                ->references('id')->on('users')
                ->onDelete('cascade')
                ->onUpdate('restrict');

            $table->foreign('apiId')
                ->references('id')->on('apiAccesses')
                ->onDelete('cascade')
                ->onUpdate('restrict');
        });
    }

    public function down(): void
    {
        Schema::table('drivers', function (Blueprint $table) {
            $table->dropForeign(['userId']);
        });

        Schema::table('requests', function (Blueprint $table) {
            $table->dropForeign(['userId']);
            $table->dropForeign(['carTypeId']);
            $table->dropForeign(['startLocationId']);
            $table->dropForeign(['destLocationId']);
        });

        Schema::table('requestHistories', function (Blueprint $table) {
            $table->dropForeign(['requestId']);
            $table->dropForeign(['driverId']);
            $table->dropForeign(['descountId']);
        });

        Schema::table('usedDiscounts', function (Blueprint $table) {
            $table->dropForeign(['requestId']);
            $table->dropForeign(['userId']);
            $table->dropForeign(['discountId']);
        });

        Schema::table('rates', function (Blueprint $table) {
            $table->dropForeign(['userId']);
            $table->dropForeign(['driverId']);
        });

        Schema::table('complaints', function (Blueprint $table) {
            $table->dropForeign(['requestId']);
            $table->dropForeign(['driverId']);
        });

        Schema::table('userapiAccesses', function (Blueprint $table) {
            $table->dropForeign(['userId']);
            $table->dropForeign(['apiId']);
        });
    }
};
