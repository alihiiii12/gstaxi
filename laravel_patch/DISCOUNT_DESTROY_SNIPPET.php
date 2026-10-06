<?php

/**
 * حذف كوبون نهائياً — يستدعيه admin-web و Flutter عبر:
 *   DELETE {api}/discounts/destroy/{id}
 * مع ترويسة Authorization: Bearer … (نفس مجموعة حماية discounts الأخرى).
 *
 * 1) routes/api.php (ضمن نفس مجموعة مسارات الخصومات للإدارة):
 *
 *    Route::delete('/discounts/destroy/{id}', [DiscountController::class, 'destroy'])
 *        ->middleware('auth:sanctum'); // أو الصلاحية التي تستخدمها لمخزن الكوبونات
 *
 * 2) في DiscountController (أو اسم المتحكم الفعلي عندك):
 *
 *    public function destroy(int $id): JsonResponse
 *    {
 *        $discount = Discount::query()->findOrFail($id);
 *        $discount->delete(); // أو forceDelete() إن كان الجدول يستخدم SoftDeletes
 *
 *        return response()->json([
 *            'success' => true,
 *            'message' => 'تم حذف الكوبون',
 *        ]);
 *    }
 *
 * إن وُجدت علاقات (طلبات مرتبطة بـ discount_id) استخدم onDelete('set null')
 * أو احظر الحذف برسالة واضحة بدل Foreign key exception.
 */
