<?php

namespace App\Http\Controllers;

use App\Models\DriverNotification;
use Illuminate\Http\Request;

class DriverNotificationController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $limit = min((int) $request->query('limit', 50), 100);

        $rows = DriverNotification::query()
            ->where('user_id', $user->id)
            ->orderByDesc('id')
            ->limit($limit)
            ->get()
            ->map(function (DriverNotification $n) {
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
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $count = DriverNotification::query()
            ->where('user_id', $user->id)
            ->whereNull('read_at')
            ->count();

        return response()->json([
            'success' => true,
            'count' => $count,
        ]);
    }

    public function markRead(Request $request, int $id)
    {
        $user = $request->user();
        if (! $user || $user->roll !== 'Driver') {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $row = DriverNotification::query()
            ->where('user_id', $user->id)
            ->whereKey($id)
            ->first();

        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Not found'], 404);
        }

        $row->read_at = now();
        $row->save();

        return response()->json(['success' => true, 'data' => $row->fresh()]);
    }
}
