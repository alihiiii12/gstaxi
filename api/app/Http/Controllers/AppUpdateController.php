<?php

namespace App\Http\Controllers;

use App\Services\AppUpdatePolicy;
use Illuminate\Http\Request;

class AppUpdateController extends Controller
{
    /** عام — يستدعيه التطبيق قبل/أثناء الدخول */
    public function info(Request $request)
    {
        $cfg = AppUpdatePolicy::config();
        $clientBuild = AppUpdatePolicy::clientBuildFromRequest($request);
        $platform = AppUpdatePolicy::clientPlatformFromRequest($request);
        $block = AppUpdatePolicy::evaluateClient($clientBuild, $platform);
        $downloadUrl = AppUpdatePolicy::downloadUrlForPlatform($platform);

        return response()->json([
            'success' => true,
            'data' => [
                'min_build' => $cfg['min_build'],
                'download_url' => $downloadUrl,
                'ios_download_url' => $cfg['ios_download_url'],
                'android_download_url' => $cfg['download_url'],
                'message' => $cfg['message'],
                'block_old_login' => $cfg['block_old_login'],
                'client_build' => $clientBuild,
                'client_platform' => $platform,
                'update_required' => $block !== null,
            ],
        ]);
    }
}
