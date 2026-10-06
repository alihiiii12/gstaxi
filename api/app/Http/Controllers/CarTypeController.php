<?php

namespace App\Http\Controllers;

use App\Models\CarType;
use App\Http\Requests\StoreCarTypeRequest;
use App\Models\Driver;
use Illuminate\Http\Request;

class CarTypeController extends Controller
{
    private function ensureCarTypesWrite(Request $request): bool
    {
        return $request->user() && $request->user()->hasStaffPermission('drivers.write');
    }

    /**
     * View a list of all car types     */
    public function index(Request $request)
    {
        $query = CarType::query();

        if ($request->has('name')) {
            $search = $request->name;
            $query->where('name', 'like', "%$search%");
        }

        // «العداد الحر» ليس فئة تسعير لطلب التطبيق — لا يُعرَض في واجهة الفئات.
        $query->where('name', '<>', 'العداد الحر');
        $sortBy = $request->get('sort_by', 'sort_order');
        $sortOrder = $request->get('sort_direction', 'asc');
        $query->orderBy($sortBy, $sortOrder)->orderBy('id', 'asc');

        if ($request->has('with_trashed') && $request->with_trashed) {
            $query->withTrashed();
        }

        //$carTypes = $query->paginate($request->get('per_page', 15));
        $carTypes = $query->get();

        return response()->json([
            'success' => true,
            'carTypes' => $carTypes,
            'message' => 'Data fetched successfully'
        ]);
    }



    public function show($id)
    {
        $carType = CarType::find($id);

        if (!$carType) {
            return response()->json([
                'success' => false,
                'message' => 'Data not found'
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $carType,
            'message' => 'Data fetched successfully'
        ]);
    }



    /**
     *Add a new car type
     */
    public function store(StoreCarTypeRequest $request)
    {
        if (! $this->ensureCarTypesWrite($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $carType = CarType::create($request->validated());

        return response()->json([
            'success' => true,
            'data' => $carType,
            'message' => 'Data added successfully'
        ]);
    }

    public function update(Request $request)
    {
        if (! $this->ensureCarTypesWrite($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $carType = CarType::find($request->id);
        if (!$carType) {
            return response()->json([
                'success' => false,
                'message' => 'Data not found'
            ], 404);
        }

        $request->validate([
            'sort_order' => 'sometimes|integer|min:0|max:65535',
            'customer_badge' => 'sometimes|nullable|string|max:32|in:economy,suv,premium',
            'also_dispatch_to' => 'sometimes|nullable|array',
            'also_dispatch_to.*' => 'integer|exists:carTypes,id',
        ]);

        if ($request->has('also_dispatch_to')) {
            $ids = collect((array) $request->input('also_dispatch_to', []))
                ->map(fn ($x) => (int) $x)
                ->filter(fn ($x) => $x > 0 && $x !== (int) $carType->id)
                ->unique()
                ->values()
                ->all();
            $carType->also_dispatch_to = $ids ?: null;
        }

        if ($request->has('name')) {
            $newName = trim((string) $request->name);
            if ($newName === 'العداد الحر') {
                return response()->json([
                    'success' => false,
                    'message' => 'لا يمكن تسمية فئة تسعير «العداد الحر» — العداد الحر منفصل عن فئات طلب التطبيق.',
                ], 422);
            }
            $carType->name = $request->name;
        }

        if ($request->has('timePrice')) {
            $carType->timePrice = $request->timePrice;
        }

        if ($request->has('KMPrice')) {
            $carType->KMPrice = $request->KMPrice;
        }

        if ($request->has('openPrice')) {
            $carType->openPrice = $request->openPrice;
        }

        if ($request->has('sort_order')) {
            $carType->sort_order = (int) $request->input('sort_order');
        }

        if ($request->has('customer_badge')) {
            $badge = $request->input('customer_badge');
            $carType->customer_badge = $badge === null || $badge === ''
                ? null
                : (string) $badge;
        }

        $carType->save();

        return response()->json([
            'success' => true,
            'data' => $carType->fresh(),
            'message' => 'Data updated successfully'
        ]);
    }


    public function destroy(Request $request, $id)
    {
        if (! $this->ensureCarTypesWrite($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $carType = CarType::find($id);

        if (!$carType) {
            return response()->json([
                'success' => false,
                'message' => 'Data not found'
            ], 404);
        }

        if (trim((string) $carType->name) === 'العداد الحر') {
            return response()->json([
                'success' => false,
                'message' => '«العداد الحر» ليس فئة تسعير لطلب التطبيق — لا يُحذف من هنا.',
            ], 400);
        }

        $carType->delete();

        return response()->json([
            'success' => true,
            'message' => 'Data deleted successfully'
        ]);
    }


    public function restore(Request $request, $id)
    {
        if (! $this->ensureCarTypesWrite($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $carType = CarType::withTrashed()->find($id);

        if (!$carType) {
            return response()->json([
                'success' => false,
                'message' => 'Data not found'
            ], 404);
        }

        if (!$carType->trashed()) {
            return response()->json([
                'success' => false,
                'message' => 'Data is not deleted'
            ], 400);
        }

        $carType->restore();

        return response()->json([
            'success' => true,
            'data' => $carType,
            'message' => 'Data restored successfully'
        ]);
    }


    public function forceDelete(Request $request, $id)
    {
        if (! $this->ensureCarTypesWrite($request)) {
            return response()->json(['success' => false, 'message' => 'Forbidden'], 403);
        }

        $carType = CarType::withTrashed()->find($id);

        if (!$carType) {
            return response()->json([
                'success' => false,
                'message' => 'Data not found'
            ], 404);
        }

        if (trim((string) $carType->name) === 'العداد الحر') {
            return response()->json([
                'success' => false,
                'message' => '«العداد الحر» ليس فئة تسعير لطلب التطبيق — لا يُحذف من هنا.',
            ], 400);
        }

        $checkDriver = Driver::where('transTypeId', $id)->first();
        if ($checkDriver != null) {
            return response()->json([
                'state' => false,
                'message' => 'لا يمكن حذف فئة يوجد سائقين بها'
            ], 400);
        }
        $carType->forceDelete();

        return response()->json([
            'success' => true,
            'message' => 'Data deleted permanently'
        ]);
    }

    /**
     * Display only deleted car models     */
    public function trashed()
    {
        $carTypes = CarType::onlyTrashed()->paginate(15);

        return response()->json([
            'success' => true,
            'data' => $carTypes,
            'message' => 'Data fetched successfully'
        ]);
    }
}
