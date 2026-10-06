<?php

namespace App\Http\Controllers;

use App\Models\ServiceArea;

class ServiceAreaPublicController extends Controller
{
    /** مناطق الخدمة النشطة للزبون عند الحجز */
    public function active()
    {
        $rows = ServiceArea::query()
            ->where('active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get([
                'id',
                'name',
                'south_lat',
                'north_lat',
                'west_lng',
                'east_lng',
            ]);

        return response()->json([
            'success' => true,
            'data' => $rows,
        ]);
    }
}
