<?php

namespace App\Services;

use App\Models\AppSetting;

/**
 * سياسة تحديث التطبيق (حد أدنى للإصدار + رابط التحميل).
 */
class AppUpdatePolicy
{
    public const KEY_MIN_BUILD = 'app_min_build';

    public const KEY_DOWNLOAD_URL = 'app_download_url';

    public const KEY_IOS_DOWNLOAD_URL = 'app_ios_download_url';

    public const KEY_MESSAGE = 'app_update_message';

    public const KEY_BLOCK_OLD = 'app_block_old_login';

    public static function defaults(): array
    {
        return [
            'min_build' => 6,
            'download_url' => 'https://gstaxi.online/downloads/gstaxi.apk',
            // حدّث رابط App Store عند توفر المعرّف الحقيقي.
            'ios_download_url' => 'https://apps.apple.com/app/id0000000000',
            'message' => 'نسخة التطبيق قديمة. حدّث التطبيق لمتابعة استخدام GS Taxi.',
            // افتراضياً لا نحظر حتى يُفعَّل من لوحة التحكم بعد نشر نسخة جديدة
            'block_old_login' => false,
        ];
    }

    public static function config(): array
    {
        $d = self::defaults();

        return [
            'min_build' => AppSetting::getInt(self::KEY_MIN_BUILD, $d['min_build']),
            'download_url' => AppSetting::getString(self::KEY_DOWNLOAD_URL, $d['download_url']),
            'ios_download_url' => AppSetting::getString(self::KEY_IOS_DOWNLOAD_URL, $d['ios_download_url']),
            'message' => AppSetting::getString(self::KEY_MESSAGE, $d['message']),
            'block_old_login' => AppSetting::getBool(self::KEY_BLOCK_OLD, $d['block_old_login']),
        ];
    }

    public static function downloadUrlForPlatform(?string $platform): string
    {
        $cfg = self::config();
        $p = strtolower(trim((string) $platform));
        if ($p === 'ios' || $p === 'iphone' || $p === 'ipad') {
            $ios = trim((string) ($cfg['ios_download_url'] ?? ''));
            if ($ios !== '') {
                return $ios;
            }

            return (string) self::defaults()['ios_download_url'];
        }

        return (string) ($cfg['download_url'] ?? self::defaults()['download_url']);
    }

    /**
     * @return array{required:bool,min_build:int,client_build:int|null,download_url:string,message:string}|null
     * null = لا يوجد حظر
     */
    public static function evaluateClient(?int $clientBuild, ?string $platform = null): ?array
    {
        $cfg = self::config();
        if (! $cfg['block_old_login']) {
            return null;
        }

        $min = (int) $cfg['min_build'];
        if ($min <= 0) {
            return null;
        }

        // بدون رأس الإصدار = نسخة قديمة لا تعرف التحديث القسري.
        $build = $clientBuild ?? 0;
        if ($build >= $min) {
            return null;
        }

        $url = self::downloadUrlForPlatform($platform);
        $msg = trim((string) $cfg['message']);
        if ($msg === '') {
            $msg = self::defaults()['message'];
        }
        if ($url !== '') {
            $msg .= "\nرابط التحديث: ".$url;
        }

        return [
            'required' => true,
            'min_build' => $min,
            'client_build' => $clientBuild,
            'download_url' => $url,
            'message' => $msg,
        ];
    }

    public static function clientBuildFromRequest($request): ?int
    {
        $raw = $request->header('X-App-Build')
            ?? $request->header('X-App-Version-Code')
            ?? $request->input('app_build');
        if ($raw === null || $raw === '') {
            return null;
        }
        $n = (int) $raw;

        return $n > 0 ? $n : null;
    }

    public static function clientPlatformFromRequest($request): ?string
    {
        $raw = $request->header('X-App-Platform')
            ?? $request->input('app_platform');
        if ($raw === null || $raw === '') {
            return null;
        }

        return strtolower(trim((string) $raw));
    }
}
