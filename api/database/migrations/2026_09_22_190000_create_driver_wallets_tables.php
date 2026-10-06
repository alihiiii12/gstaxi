<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('driver_wallets')) {
            Schema::create('driver_wallets', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('driver_id')->unique();
                $table->decimal('balance', 14, 2)->default(0);
                $table->string('currency', 8)->default('SYP');
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('driver_wallet_transactions')) {
            Schema::create('driver_wallet_transactions', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('driver_wallet_id');
                $table->unsignedBigInteger('driver_id')->index();
                $table->string('type', 40); // reward | coupon_compensation | admin_withdraw | admin_adjust
                $table->decimal('amount', 14, 2); // موجب إضافة، سالب سحب
                $table->decimal('balance_after', 14, 2);
                $table->unsignedBigInteger('request_id')->nullable()->index();
                $table->unsignedBigInteger('discount_id')->nullable();
                $table->string('note', 500)->nullable();
                $table->unsignedBigInteger('created_by_user_id')->nullable();
                $table->timestamps();

                $table->index(['driver_id', 'created_at']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('driver_wallet_transactions');
        Schema::dropIfExists('driver_wallets');
    }
};
