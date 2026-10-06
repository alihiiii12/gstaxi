<?php

namespace App\Http\Controllers;

use App\Models\Location;
use App\Http\Requests\StoreLocationRequest;
use App\Http\Requests\UpdateLocationRequest;
use Illuminate\Http\Request;

class LocationController extends Controller
{
    /**
     * Display a list of all locations
     */
    public function index(Request $request)
    {
        $query = Location::query();

        // Search by name
        if ($request->has('name')) {
            $query->where('name', 'like', '%' . $request->name . '%');
        }

        // Search by type
        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        // Search by proximity (radius)
        if ($request->has('latitude') && $request->has('longitude')) {
            $distance = $request->get('distance', 1); // distance in kilometers
            $query->nearby($request->latitude, $request->longitude, $distance);
        }

        // Sorting
        $sortBy = $request->get('sort_by', 'id');
        $sortOrder = $request->get('sort_order', 'desc');
        $query->orderBy($sortBy, $sortOrder);

        // Show deleted records
        if ($request->has('with_trashed') && $request->with_trashed) {
            $query->withTrashed();
        }

        $locations = $query->paginate($request->get('per_page', 15));

        return response()->json([
            'success' => true,
            'data' => $locations,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Display a specific location
     */
    public function show($id)
    {
        $location = Location::find($id);

        if (!$location) {
            return response()->json([
                'success' => false,
                'message' => 'Location not found'
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $location,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Search for nearby locations
     */
    public function nearby(Request $request)
    {
        $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'distance' => 'sometimes|numeric|min:0.1|max:50',
            'type' => 'nullable|string',
        ]);

        $distance = $request->get('distance', 1);

        $query = Location::nearby($request->latitude, $request->longitude, $distance);

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        $locations = $query->get();

        return response()->json([
            'success' => true,
            'data' => $locations,
            'count' => $locations->count(),
            'message' => 'Nearby locations fetched successfully'
        ]);
    }

    /**
     * Add a new location
     */
    public function store(StoreLocationRequest $request)
    {
        $location = Location::create($request->validated());

        return response()->json([
            'success' => true,
            'data' => $location,
            'message' => 'Location added successfully'
        ], 201);
    }

    /**
     * Update a location
     */
    public function update(UpdateLocationRequest $request, $id)
    {
        $location = Location::find($id);
        if (!$location) {
            return response()->json([
                'success' => false,
                'message' => 'Location not found'
            ], 404);
        }
        if ($request->has('name')) {
            $location->name = $request->name;
        }
        if ($request->has('type')) {
            $location->type = $request->type;
        }
        if ($request->has('description')) {
            $location->description = $request->description;
        }
        if ($request->has('latitude')) {
            $location->latitude = $request->latitude;
        }
        if ($request->has('longitude')) {
            $location->longitude = $request->longitude;
        }


        $location->save();

        return response()->json([
            'success' => true,
            'data' => $location->fresh(),
            'message' => 'Location updated successfully'
        ]);
    }

    /**
     * Delete a location (Soft Delete)
     */
    public function destroy($id)
    {
        $location = Location::find($id);

        if (!$location) {
            return response()->json([
                'success' => false,
                'message' => 'Location not found'
            ], 404);
        }

        $location->delete();

        return response()->json([
            'success' => true,
            'message' => 'Location deleted successfully'
        ]);
    }

    /**
     * Restore a deleted location
     */
    public function restore($id)
    {
        $location = Location::withTrashed()->find($id);

        if (!$location) {
            return response()->json([
                'success' => false,
                'message' => 'Location not found'
            ], 404);
        }

        if (!$location->trashed()) {
            return response()->json([
                'success' => false,
                'message' => 'Location is not deleted'
            ], 400);
        }

        $location->restore();

        return response()->json([
            'success' => true,
            'data' => $location,
            'message' => 'Location restored successfully'
        ]);
    }

    /**
     * Permanently delete a location
     */
    public function forceDelete($id)
    {
        $location = Location::withTrashed()->find($id);

        if (!$location) {
            return response()->json([
                'success' => false,
                'message' => 'Location not found'
            ], 404);
        }

        $location->forceDelete();

        return response()->json([
            'success' => true,
            'message' => 'Location deleted permanently'
        ]);
    }

    /**
     * Display only deleted locations
     */
    public function trashed()
    {
        $locations = Location::onlyTrashed()->paginate(15);

        return response()->json([
            'success' => true,
            'data' => $locations,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Calculate distance between two locations
     */
    public function calculateDistance(Request $request)
    {
        $request->validate([
            'from_latitude' => 'required|numeric|between:-90,90',
            'from_longitude' => 'required|numeric|between:-180,180',
            'to_latitude' => 'required|numeric|between:-90,90',
            'to_longitude' => 'required|numeric|between:-180,180',
        ]);

        $fromLocation = new Location([
            'latitude' => $request->from_latitude,
            'longitude' => $request->from_longitude
        ]);

        $distance = $fromLocation->distanceTo($request->to_latitude, $request->to_longitude);

        return response()->json([
            'success' => true,
            'data' => [
                'distance_km' => round($distance, 2),
                'from' => [
                    'latitude' => $request->from_latitude,
                    'longitude' => $request->from_longitude
                ],
                'to' => [
                    'latitude' => $request->to_latitude,
                    'longitude' => $request->to_longitude
                ]
            ],
            'message' => 'Distance calculated successfully'
        ]);
    }

    /**
     * Get popular pickup locations
     */
    public function popularPickupLocations()
    {
        $locations = Location::withCount(['requestsAsStart'])
            ->having('requests_as_start_count', '>', 0)
            ->orderBy('requests_as_start_count', 'desc')
            ->take(10)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $locations,
            'message' => 'Popular pickup locations fetched successfully'
        ]);
    }

    /**
     * Get popular dropoff locations
     */
    public function popularDropoffLocations()
    {
        $locations = Location::withCount(['requestsAsDest'])
            ->having('requests_as_dest_count', '>', 0)
            ->orderBy('requests_as_dest_count', 'desc')
            ->take(10)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $locations,
            'message' => 'Popular dropoff locations fetched successfully'
        ]);
    }

    /**
     * Add multiple locations (bulk)
     */
    public function bulkStore(Request $request)
    {
        $request->validate([
            'locations' => 'required|array',
            'locations.*.longitude' => 'required|numeric|between:-180,180',
            'locations.*.latitude' => 'required|numeric|between:-90,90',
            'locations.*.name' => 'nullable|string',
            'locations.*.type' => 'nullable|string',
            'locations.*.description' => 'nullable|string',
        ]);

        $createdLocations = [];

        foreach ($request->locations as $locationData) {
            $createdLocations[] = Location::create($locationData);
        }

        return response()->json([
            'success' => true,
            'data' => $createdLocations,
            'count' => count($createdLocations),
            'message' => 'Locations added successfully'
        ], 201);
    }
}
