<?php

/**
 * توحيد إيراد «آخر 30 يوماً» مع تفاصيل الرحلات (لوحة التحكم + تقارير).
 *
 * 1) TripRevenueService + dashboard-summary:
 *    - رحلات status = 'Finished' فقط.
 *    - تاريخ الإيراد: requests.updated_at (وقت الإنهاء)، وليس requestHistories.updated_at.
 *    - المبلغ: requestHistories.finalCost (ثم predectedCost احتياطاً).
 *    - requests_finished_today = عدد Finished في نفس نطاق اليوم.
 *
 * 2) إن كان تقرير financial?format=json يعيد قائمة رحلات:
 *    - فلتر الصفوف بنفس قاعدة (1) قبل المجاميع.
 *    - لا تجمع حقول تقديرية (amount/cost) إن كانت تعادل سعراً قبل الإكمال.
 *
 * الواجهة admin-web تعرض الآن تفاصيل الإيراد من admin/requests?status=Finished فقط،
 * وتعرض في الشريط السفلي نفس رقم لوحة التحكم (revenue_last_30_days).
 */
