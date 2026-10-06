<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Allow creating immediate request without destination until customer confirms.
        DB::statement('ALTER TABLE `requests` MODIFY `destLocationId` INT UNSIGNED NULL');

        // Expand status enum to support "driver arrived" and "awaiting destination".
        DB::statement(
            "ALTER TABLE `requests` MODIFY `status` ENUM(
                'Pending',
                'Running',
                'Finished',
                'Removed',
                'Reserved',
                'DriverArrived',
                'AwaitingDestination'
            ) NOT NULL"
        );
    }

    public function down(): void
    {
        // Revert enum (drop new statuses) and restore non-null destination.
        DB::statement(
            "ALTER TABLE `requests` MODIFY `status` ENUM(
                'Pending',
                'Running',
                'Finished',
                'Removed',
                'Reserved'
            ) NOT NULL"
        );

        DB::statement('ALTER TABLE `requests` MODIFY `destLocationId` INT UNSIGNED NOT NULL');
    }
};

