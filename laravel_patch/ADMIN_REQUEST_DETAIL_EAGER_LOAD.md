# تفاصيل الطلب في لوحة الإدارة — تحميل العلاقات

في `AdminRequestController` (أو المتحكم الذي يخدم `GET /api/admin/requests/{id}`) تأكد من:

```php
$request = RequestModel::with([
    'user',
    'driver.user',
    'startLocation',
    'destLocation',
    'history',
    'serviceArea',
])->findOrFail($id);
```

بدون ذلك تظهر فقط `userId` و`startLocationId` في JSON.
