<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('customer_wallets')) {
            Schema::create('customer_wallets', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('user_id')->unique();
                $table->decimal('balance', 14, 2)->default(0);
                $table->string('currency', 8)->default('SYP');
                $table->timestamps();
            });
        }

        if (! Schema::hasTable('customer_wallet_transactions')) {
            Schema::create('customer_wallet_transactions', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('customer_wallet_id');
                $table->unsignedBigInteger('user_id')->index();
                $table->string('type', 40); // admin_topup | admin_deduct | admin_adjust | trip_payment
                $table->decimal('amount', 14, 2); // موجب إضافة، سالب خصم
                $table->decimal('balance_after', 14, 2);
                $table->unsignedBigInteger('request_id')->nullable()->index();
                $table->string('note', 500)->nullable();
                $table->unsignedBigInteger('created_by_user_id')->nullable();
                $table->timestamps();

                $table->index(['user_id', 'created_at']);
            });
        }

        Schema::table('requests', function (Blueprint $table) {
            if (! Schema::hasColumn('requests', 'payment_method')) {
                $table->string('payment_method', 12)->nullable(); // cash | wallet | mixed
            }
            if (! Schema::hasColumn('requests', 'wallet_paid_amount')) {
                $table->decimal('wallet_paid_amount', 14, 2)->nullable();
            }
            if (! Schema::hasColumn('requests', 'cash_due_amount')) {
                $table->decimal('cash_due_amount', 14, 2)->nullable();
            }
            if (! Schema::hasColumn('requests', 'payment_settled_at')) {
                $table->timestamp('payment_settled_at')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('requests', function (Blueprint $table) {
            foreach (['payment_method', 'wallet_paid_amount', 'cash_due_amount', 'payment_settled_at'] as $col) {
                if (Schema::hasColumn('requests', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
        Schema::dropIfExists('customer_wallet_transactions');
        Schema::dropIfExists('customer_wallets');
    }
};
