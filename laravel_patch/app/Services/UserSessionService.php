<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Http\Exceptions\HttpResponseException;

/**
 * جلسة واحدة لكل حساب — لا دخول من جهازين مختلفين في نفس الوقت.
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

    public static function assertCanLogin(User $user, ?string $deviceId): void
    {
        $name = self::deviceTokenName($deviceId);
        $tokens = $user->tokens()->get(['name']);
        if ($tokens->isEmpty()) {
            return;
        }

        if ($name === self::LEGACY_TOKEN_NAME) {
            if ($tokens->isNotEmpty()) {
                self::throwConflict();
            }

            return;
        }

        foreach ($tokens as $token) {
            $existing = (string) $token->name;
            if ($existing === $name || $existing === self::LEGACY_TOKEN_NAME) {
                continue;
            }
            if (str_starts_with($existing, self::TOKEN_PREFIX)) {
                self::throwConflict();
            }
        }
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

    public static function createToken(User $user, ?string $deviceId): string
    {
        self::assertCanLogin($user, $deviceId);
        self::revokeForDevice($user, $deviceId);

        return $user->createToken(self::deviceTokenName($deviceId))->plainTextToken;
    }

    private static function throwConflict(): void
    {
        throw new HttpResponseException(response()->json([
            'success' => false,
            'state' => false,
            'message' => 'هذا الحساب مستخدم على جهاز آخر. سجّل الخروج من ذلك الجهاز أولاً.',
            'code' => 'session_active_elsewhere',
        ], 409));
    }
}

