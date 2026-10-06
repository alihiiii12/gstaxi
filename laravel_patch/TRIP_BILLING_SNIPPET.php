<?php

/**
 * تمييز رحلة «عداد حر» عن «طلب التطبيق» في JSON الطلب (للوحة والتقارير).
 *
 * يُنصح بإضافة حقول على جدول requests (أو في علاقة history) عند الحفظ:
 *
 * - billing_kind: 'app_request' | 'free_meter'
 *   العداد الحر: لا يُسعَّر بفئة VIP/اقتصادي — فقط إعدادات العداد (فتح+كم+دقيقة).
 * - is_app_request: bool (مرادف سريع)
 * - free_meter_had_movement: bool — هل وُجدت حركة/مسافة بعد الفتح؟
 * - free_meter_counts_for_revenue: bool — false إن وقف السائق على السعر الافتتاحي فقط
 * - distanceTraveledKm على جدول requestHistories عند الإنهاء (للتحقق من الحركة)
 *
 * الواجهات (admin-web + Flutter) تعرض تلقائياً إن وُجدت هذه الحقول؛
 * وإلا تستنتج من userId + أعلام اختيارية كما في util/tripPathLabels.ts
 */
