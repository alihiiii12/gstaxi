<?php

/**
 * إعدادات العداد الحر — الحقول المتوقعة بين الواجهات و Laravel:
 *
 * GET/PUT  /api/admin/free-meter-settings
 *   Body (PUT): { "openPrice": number, "kmPrice": number, "timePrice": number }
 *   Response data: نفس المفاتيح (قيم ≥ 0).
 *
 * GET  /api/drivers/me/free-meter-pricing  (للسائق بعد تسجيل الدخول)
 *   { "state": true, "data": { "openPrice", "kmPrice", "timePrice" } }
 *
 * منطق التطبيق (Flutter DriverController): يبدأ المبلغ بـ openPrice،
 * يزيد عند الحركة: km × kmPrice، وعند التوقف ≥60ث: + timePrice لكل دقيقة كاملة.
 *
 * تأكد أن جدول/سجل الإعدادات يخزّن الثلاثة وأن المسارين أعلاه يقرآن/يكتبان نفس الحقول.
 */
