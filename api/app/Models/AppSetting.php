<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppSetting extends Model
{
    protected $table = 'app_settings';

    protected $fillable = [
        'key',
        'value',
    ];

    public static function getDecimal(string $key, float $default = 0.0): float
    {
        $row = static::query()->where('key', $key)->first();
        if ($row === null || $row->value === null || $row->value === '') {
            return $default;
        }

        return (float) $row->value;
    }

    public static function getString(string $key, string $default = ''): string
    {
        $row = static::query()->where('key', $key)->first();
        if ($row === null || $row->value === null || $row->value === '') {
            return $default;
        }

        return (string) $row->value;
    }

    public static function getInt(string $key, int $default = 0): int
    {
        $row = static::query()->where('key', $key)->first();
        if ($row === null || $row->value === null || $row->value === '') {
            return $default;
        }

        return (int) $row->value;
    }

    public static function getBool(string $key, bool $default = false): bool
    {
        $v = strtolower(trim(static::getString($key, $default ? '1' : '0')));

        return in_array($v, ['1', 'true', 'yes', 'on'], true);
    }

    public static function setValue(string $key, string $value): void
    {
        static::query()->updateOrCreate(
            ['key' => $key],
            ['value' => $value]
        );
    }
}
