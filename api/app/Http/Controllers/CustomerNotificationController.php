<?php

namespace App\Http\Controllers;

use App\Models\CustomerNotification;
use Illuminate\Http\Request;

class CustomerNotificationController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $rows = CustomerNotification::query()
            ->where('user_id', $user->id)
            ->orderByDesc('id')
            ->limit(50)
            ->get()
            ->map(function (CustomerNotification $n) {
                $arr = $n->toArray();
                $arr['data'] = $n->payload ?: [
                    'kind' => $n->kind,
                    'request_id' => $n->reference_id,
                ];

                return $arr;
            });

        return response()->json([
            'success' => true,
            'data' => $rows,
        ]);
    }

    public function unreadCount(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $n = CustomerNotification::query()
            ->where('user_id', $user->id)
            ->whereNull('read_at')
            ->count();

        try {
            \App\Services\CustomerPresenceService::markOnline((int) $user->id);
        } catch (\Throwable $e) {
        }

        return response()->json([
            'success' => true,
            'data' => ['count' => $n],
        ]);
    }

    public function markRead(Request $request, int $id)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Customer') {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $row = CustomerNotification::query()
            ->where('user_id', $user->id)
            ->whereKey($id)
            ->first();

        if (! $row) {
            return response()->json([
                'success' => false,
                'message' => 'Not found',
            ], 404);
        }

        $row->read_at = now();
        $row->save();

        return response()->json([
            'success' => true,
            'data' => $row->fresh(),
        ]);
    }
}
