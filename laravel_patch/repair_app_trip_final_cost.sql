-- إصلاح رحلات طلب التطبيق التي خُزِّن لها finalCost أعلى من predectedCost
-- (بسبب إعادة الحساب بمدة الرحلة الفعلية عند الإنهاء).
UPDATE requestHistories rh
INNER JOIN requests r ON r.id = rh.requestId
SET rh.finalCost = r.predectedCost
WHERE r.status = 'Finished'
  AND r.predectedCost > 0
  AND (r.is_app_request = 1 OR r.billing_kind IS NULL OR r.billing_kind = 'app_request')
  AND rh.finalCost > r.predectedCost * 1.2;
