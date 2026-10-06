<?php

namespace App\Http\Controllers;

use App\Models\Discount;
use App\Models\UsedDiscount;
use App\Models\RequestModel;
use App\Models\User;
use App\Http\Requests\UpdateDiscountRequest;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class DiscountController extends Controller
{
    /**
     * View a list of all discounts
     */
    public function index(Request $request)
    {
        $u = $request->user();
        if ($u && $u->roll === 'Employee' && ! $u->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $query = Discount::query();

        if ($request->has('code')) {
            $query->where('code', 'like', '%' . $request->code . '%');
        }

        if ($request->has('type')) {
            $query->where('type', $request->type);
        }

        if ($request->has('min_amount')) {
            $query->where('amount', '>=', $request->min_amount);
        }

        if ($request->has('max_amount')) {
            $query->where('amount', '<=', $request->max_amount);
        }

        $sortBy = $request->get('sort_by', 'id');
        $sortOrder = $request->get('sort_order', 'desc');
        $query->orderBy($sortBy, $sortOrder);

        if ($request->has('with_trashed') && $request->with_trashed) {
            $query->withTrashed();
        }

        $discounts = $query->paginate($request->get('per_page', 15));

        foreach ($discounts as $discount) {
            $discount->usage_count = UsedDiscount::usageCount($discount->id);
        }

        return response()->json([
            'success' => true,
            'data' => $discounts,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Show a specific discount
     */
    public function show($id)
    {
        $discount = Discount::find($id);

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount not found'
            ], 404);
        }

        $discount->usage_count = UsedDiscount::usageCount($discount->id);

        return response()->json([
            'success' => true,
            'data' => $discount,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Search for a discount using the code
     */
    public function findByCode($code)
    {
        $discount = Discount::where('code', $code)->first();

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount code not found'
            ], 404);
        }

        $discount->usage_count = UsedDiscount::usageCount($discount->id);

        return response()->json([
            'success' => true,
            'data' => $discount,
            'message' => 'Discount found successfully'
        ]);
    }

    /**
     * Add a new discount (for admins)
     */
    public function store(Request $request)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $isPercent = $request->input('type', Discount::TYPE_PERCENTAGE) === Discount::TYPE_PERCENTAGE;
        $data = $request->validate([
            'code' => 'required|string|max:64|unique:discounts,code',
            'type' => 'nullable|string|in:Percentage,Fixed',
            'amount' => $isPercent ? 'required|numeric|gt:0|max:100' : 'required|numeric|gt:0',
            'max_discount' => $isPercent ? 'required|numeric|gt:0' : 'nullable|numeric',
            'max_uses_per_user' => 'nullable|integer|min:1|max:10000',
            'unlimited_uses' => 'sometimes|boolean',
            'target_phones' => 'nullable|array',
            'target_phones.*' => 'string|max:32',
            'target_all' => 'sometimes|boolean',
            'valid_from' => 'nullable|date',
            'valid_until' => 'nullable|date|after_or_equal:valid_from',
        ]);

        $targetAll = filter_var($request->input('target_all', false), FILTER_VALIDATE_BOOLEAN);
        $phones = $data['target_phones'] ?? null;
        if ($targetAll || $phones === null || (is_array($phones) && count($phones) === 0)) {
            $phones = null;
        } else {
            $phones = array_values(array_unique(array_filter(array_map(
                static fn ($p) => preg_replace('/\s+/', '', (string) $p),
                $phones
            ))));
            if ($phones === []) {
                $phones = null;
            }
        }

        $type = $data['type'] ?? Discount::TYPE_PERCENTAGE;
        $discount = Discount::create([
            'code' => $data['code'],
            'amount' => $data['amount'],
            'type' => $type,
            'max_discount' => $type === Discount::TYPE_PERCENTAGE ? $data['max_discount'] : null,
            'max_uses_per_user' => filter_var($request->input('unlimited_uses', false), FILTER_VALIDATE_BOOLEAN)
                ? null
                : (int) ($data['max_uses_per_user'] ?? 1),
            'target_phones' => $phones,
            'valid_from' => $data['valid_from'] ?? null,
            'valid_until' => $data['valid_until'] ?? null,
        ]);

        return response()->json([
            'success' => true,
            'data' => $discount,
            'message' => 'Discount code added successfully',
        ], 201);
    }

    /**
     * Update discount data
     */
    public function update(UpdateDiscountRequest $request, $id)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $discount = Discount::find($id);

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount not found'
            ], 404);
        }
        if ($request->has('code')) {
            $discount->code = $request->code;
        }
        if ($request->has('min_amount')) {
            $discount->amount = $request->min_amount;
        }
        if ($request->has('type')) {
            $discount->type = $request->type;
        }
        if ($request->has('target_phones')) {
            $discount->target_phones = $request->target_phones;
        }
        if ($request->has('valid_from')) {
            $discount->valid_from = $request->valid_from;
        }
        if ($request->has('valid_until')) {
            $discount->valid_until = $request->valid_until;
        }
        if ($request->has('unlimited_uses') || $request->has('max_uses_per_user')) {
            $request->validate(['max_uses_per_user' => 'nullable|integer|min:1|max:10000']);
            $discount->max_uses_per_user = filter_var($request->input('unlimited_uses', false), FILTER_VALIDATE_BOOLEAN)
                ? null
                : (int) ($request->input('max_uses_per_user') ?: 1);
        }
        $discount->save();
        return response()->json([
            'success' => true,
            'data' => $discount->fresh(),
            'message' => 'Discount code updated successfully'
        ]);
    }

    /**
     * Validate and apply discount code (for users)
     */
    public function validateAndApply(Request $request)
    {
        $request->validate([
            'code' => 'required|string',
            'userId' => 'required|integer|exists:users,id',
            'originalPrice' => 'required|numeric|min:0'
        ]);

        // Search for the code
        $discount = Discount::where('code', $request->code)->first();

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid discount code',
                'code' => 'INVALID_CODE'
            ], 404);
        }

        if (! $discount->isActiveNow()) {
            return response()->json([
                'success' => false,
                'message' => 'انتهت صلاحية هذا الكوبون أو لم يبدأ بعد',
                'code' => 'DISCOUNT_EXPIRED',
            ], 400);
        }

        $phones = $discount->target_phones;
        if (is_array($phones) && count($phones) > 0) {
            $u = User::find($request->userId);
            if (! $u || ! in_array($u->number, $phones, true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'هذا الكوبون غير مخصص لرقم حسابك',
                    'code' => 'PHONE_NOT_ELIGIBLE',
                ], 403);
            }
        }

        if ($limitMsg = $discount->usageLimitErrorFor((int) $request->userId)) {
            return response()->json([
                'success' => false,
                'message' => $limitMsg,
                'code' => 'ALREADY_USED'
            ], 400);
        }

        // Calculate new price after discount
        $originalPrice = (float) $request->originalPrice;
        $discountAmount = $discount->calculateDiscount($originalPrice);
        $newPrice = max(0, $originalPrice - $discountAmount);

        return response()->json([
            'success' => true,
            'data' => [
                'discount' => $discount,
                'original_price' => $originalPrice,
                'discount_amount' => round($discountAmount, 2),
                'new_price' => round($newPrice, 2),
                'saved_amount' => round($discountAmount, 2)
            ],
            'message' => 'Discount code applied successfully'
        ]);
    }

    /**
     * Confirm discount code usage after trip completion
     */
    public function confirmUsage(Request $request)
    {
        $request->validate([
            'requestId' => 'required|integer|exists:requests,id',
            'userId' => 'required|integer|exists:users,id',
            'discountId' => 'required|integer|exists:discounts,id'
        ]);

        $existing = UsedDiscount::where('requestId', $request->requestId)->first();

        if ($existing) {
            return response()->json([
                'success' => false,
                'message' => 'A discount code has already been used for this trip'
            ], 400);
        }

        $limitMsg = Discount::find($request->discountId)?->usageLimitErrorFor((int) $request->userId);
        if ($limitMsg) {
            return response()->json([
                'success' => false,
                'message' => $limitMsg
            ], 400);
        }

        // Register code usage
        $usedDiscount = UsedDiscount::create([
            'requestId' => $request->requestId,
            'userId' => $request->userId,
            'discountId' => $request->discountId
        ]);

        // Update the trip record with discount
        $rideRequest = RequestModel::find($request->requestId);
        if ($rideRequest && $rideRequest->history) {
            $rideRequest->history->descountId = $request->discountId;
            $rideRequest->history->save();
        }

        return response()->json([
            'success' => true,
            'data' => $usedDiscount,
            'message' => 'Discount code successfully applied to the trip'
        ]);
    }

    /**
     * Delete a discount (Soft Delete)
     */
    public function destroy(Request $request, $id)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $discount = Discount::find($id);

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount not found'
            ], 404);
        }

        $discount->delete();

        return response()->json([
            'success' => true,
            'message' => 'Discount deleted successfully'
        ]);
    }

    /**
     * Restore a deleted discount
     */
    public function restore(Request $request, $id)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $discount = Discount::withTrashed()->find($id);

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount not found'
            ], 404);
        }

        if (!$discount->trashed()) {
            return response()->json([
                'success' => false,
                'message' => 'Discount is not deleted'
            ], 400);
        }

        $discount->restore();

        return response()->json([
            'success' => true,
            'data' => $discount,
            'message' => 'Discount restored successfully'
        ]);
    }

    /**
     * Permanently delete a discount
     */
    public function forceDelete(Request $request, $id)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $discount = Discount::withTrashed()->find($id);

        if (!$discount) {
            return response()->json([
                'success' => false,
                'message' => 'Discount not found'
            ], 404);
        }

        $discount->forceDelete();

        return response()->json([
            'success' => true,
            'message' => 'Discount deleted permanently'
        ]);
    }

    /**
     * View only deleted discounts
     */
    public function trashed(Request $request)
    {
        if (! $request->user() || ! $request->user()->hasStaffPermission('discounts.write')) {
            return response()->json([
                'success' => false,
                'message' => 'Forbidden',
            ], 403);
        }

        $discounts = Discount::onlyTrashed()->paginate(15);

        return response()->json([
            'success' => true,
            'data' => $discounts,
            'message' => 'Data fetched successfully'
        ]);
    }

    /**
     * Discount usage statistics
     */
    public function statistics()
    {
        $totalDiscounts = Discount::count();
        $totalUsed = UsedDiscount::consumed()->count();

        $mostUsedDiscount = Discount::withCount(['usedDiscounts' => fn ($q) => $q->consumed()])
            ->orderBy('used_discounts_count', 'desc')
            ->first();

        $totalSavedAmount = DB::table('usedDiscounts as ud')
            ->join('discounts as d', 'ud.discountId', '=', 'd.id')
            ->join('requestHistories as rh', 'ud.requestId', '=', 'rh.requestId')
            ->sum(DB::raw('CASE
                WHEN d.type = "Percentage" THEN
                    CASE WHEN d.max_discount IS NOT NULL AND d.max_discount > 0
                        THEN LEAST(rh.finalCost * d.amount / 100, d.max_discount)
                        ELSE rh.finalCost * d.amount / 100 END
                ELSE LEAST(d.amount, rh.finalCost)
            END'));

        return response()->json([
            'success' => true,
            'data' => [
                'total_discounts' => $totalDiscounts,
                'total_used' => $totalUsed,
                'usage_rate' => $totalDiscounts > 0 ? round(($totalUsed / $totalDiscounts) * 100, 2) : 0,
                'most_used_discount' => $mostUsedDiscount,
                'total_saved_amount' => round($totalSavedAmount, 2)
            ],
            'message' => 'Statistics fetched successfully'
        ]);
    }
}
