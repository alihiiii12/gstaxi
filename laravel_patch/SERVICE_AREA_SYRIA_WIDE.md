# منطقة الخدمة — تغطية سوريا كاملة

**طُبّق على المسار المحلي:** `C:\xampp\htdocs\SyriaTaxi-main` — `StoreRequestRequest` (`serviceAreaId` اختياري)، و`RequestController@store` (بدون `containsPickup`؛ `service_area_id` قد يكون `null`).

تطبيق الزبون لا يرسل `serviceAreaId` بعد الآن. لتفادي أخطاء التحقق (422) أو قيود جغرافية، طبّق على مشروع **Laravel** (`SyriaTaxi-main` أو نسختك) التالي.

## 1) التحقق من الطلب `store` (أو ما يعادله)

- اجعل **`service_area_id`** (أو `serviceAreaId`) **اختيارياً** في قواعد `validate()`:

  ```php
  'service_area_id' => 'nullable|integer|exists:service_areas,id',
  // أو إن كان المفتاح قديماً serviceAreaId حسب الـ API
  ```

- **احذف** أي شرط يرفض الطلب إذا كانت النقطة خارج مضلّع/مربّع `service_areas`، إلا إن أردت تقييداً طوعياً لاحقاً.

## 2) قاعدة البيانات

- في جدول الطلبات (`requests` أو ما شابه): إن كان العمود **`NOT NULL`** بدون قيمة افتراضية، غيّره إلى **`nullable`**:

  ```php
  Schema::table('requests', function (Blueprint $table) {
      $table->unsignedBigInteger('service_area_id')->nullable()->change();
  });
  ```

  (يحتاج `doctrine/dbal` إن استخدمت `change()`.)

## 3) إنشاء الطلب في الكود

عند عدم إرسال `serviceAreaId` من التطبيق:

- اضبط `$model->service_area_id = null` أو اتركه غير مُعيَّن إذا كان الافتراضي `null`.

## 4) مناطق الإدارة (اختياري)

يمكن الإبقاء على جدول `service_areas` لأغراض **تقسيم إداري أو تقارير** فقط، دون ربط إجباري بالراكب.

---

**المرجع في Flutter:** شاشة `AdminAreasScreen` توضح للمسؤول أن الخدمة لسوريا بالكامل وأن المناطق اختيارية.
