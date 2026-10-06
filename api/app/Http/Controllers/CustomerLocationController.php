<?php

namespace App\Http\Controllers;

use App\Services\CustomerPresenceService;
use Illuminate\Http\Request;

class CustomerLocationController extends Controller
{
    /** تحديث موقع الزبون وهو يستخدم التطبيق (لخريطة الزبائن في لوحة التحكم). */
    public function updateLocation(Request $request)
    {
        $user = $request->user();
        if (! $user || ($user->roll ?? '') !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        CustomerPresenceService::touch(
            (int) $user->id,
            (float) $data['latitude'],
            (float) $data['longitude'],
        );

        return response()->json(['success' => true]);
    }

    public function goOffline(Request $request)
    {
        $user = $request->user();
        if (! $user || ($user->roll ?? '') !== 'Customer') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        CustomerPresenceService::clear((int) $user->id);

        return response()->json(['success' => true]);
    }
}
