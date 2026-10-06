<?php

namespace App\Services;

use App\Models\User;

/**
 * جلسة واحدة لكل حساب بعد كل تسجيل دخول ناجح:
 * كلمة المرور الصحيحة تُلغي أي جلسة قديمة (بما فيها بعد حذف التطبيق دون تسجيل خروج)
 * وتنشئ جلسة جديدة لهذا الجهاز فقط.
 *
 * يُخزَّن معرّف الجهاز في اسم توكن Sanctum: device:{id}
 */
class UserSessionService
{
    public const TOKEN_PREFIX = 'device:';

    public const LEGACY_TOKEN_NAME = 'auth_token';

    public static function deviceTokenName(?string $deviceId): string
    {
        $id = trim((string) $deviceId);
        if ($id === '') {
            return self::LEGACY_TOKEN_NAME;
        }

        return self::TOKEN_PREFIX.mb_substr($id, 0, 120);
    }

    /** إلغاء كل جلسات الحساب (مثال: تسجيل الخروج الشامل). */
    public static function revokeAll(User $user): void
    {
        $user->tokens()->delete();
    }

    public static function revokeForDevice(User $user, ?string $deviceId): void
    {
        $name = self::deviceTokenName($deviceId);
        if (str_starts_with($name, self::TOKEN_PREFIX)) {
            $user->tokens()
                ->where(function ($query) use ($name) {
                    $query->where('name', $name)
                        ->orWhere('name', self::LEGACY_TOKEN_NAME);
                })
                ->delete();

            return;
        }

        $user->tokens()->delete();
    }

    /**
     * بعد التحقق من كلمة المرور: استبدال أي جلسة سابقة بجلسة هذا الجهاز.
     * يحل مشكلة إعادة التثبيت دون تسجيل خروج، ويُبقي الحساب على جهاز واحد فعّال.
     */
    public static function createToken(User $user, ?string $deviceId): string
    {
        $user->tokens()->delete();

        return $user->createToken(self::deviceTokenName($deviceId))->plainTextToken;
    }
}
