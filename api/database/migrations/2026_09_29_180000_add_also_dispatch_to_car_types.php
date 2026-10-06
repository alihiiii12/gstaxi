<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('carTypes', 'also_dispatch_to')) {
            Schema::table('carTypes', function (Blueprint $table) {
                $table->json('also_dispatch_to')->nullable()->after('customer_badge');
            });
        }

        $economy = DB::table('carTypes')->whereNull('deleted_at')
            ->where(fn ($q) => $q->where('customer_badge', 'economy')->orWhere('name', 'اقتصادية'))
            ->orderBy('id')->value('id');
        $ac = DB::table('carTypes')->whereNull('deleted_at')
            ->where(fn ($q) => $q->where('name', 'مكيفة')->orWhere('customer_badge', 'premium'))
            ->orderBy('id')->value('id');

        if ($economy && $ac && (int) $economy !== (int) $ac) {
            DB::table('carTypes')->where('id', $economy)->update([
                'also_dispatch_to' => json_encode([(int) $ac]),
            ]);
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('carTypes', 'also_dispatch_to')) {
            Schema::table('carTypes', function (Blueprint $table) {
                $table->dropColumn('also_dispatch_to');
            });
        }
    }
};
