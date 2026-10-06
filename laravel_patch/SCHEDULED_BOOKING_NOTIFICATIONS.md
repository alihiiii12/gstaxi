# الحجز المسبق — تذكيرات، «هل أنت جاهز؟»، إلغاء تلقائي، تأجيل السائق

يُفترض أن واجهات Flutter تستدعي المسارات أدناه وأن الإشعارات تُخزَّن في جدول `notifications` (أو ما يعادله) مع عمود **`data` JSON** يحتوي على **`kind`** و **`request_id`**.

## أنواع الإشعارات (`data.kind`)

| `kind` | المستلم | الوصف |
|--------|---------|--------|
| `sched_t30` | Customer + Driver | تذكير قبل الموعد بـ **30 دقيقة** |
| `sched_t5_ready` | Customer | «هل أنت جاهز؟» قبل الموعد بـ **5 دقائق** — يتطلب رداً خلال **15 دقيقة** |
| `sched_accepted` | Customer | قبول الحجز المسبق بالموعد |
| `sched_rejected` | Customer | رفض السائق → إلغاء الطلب |
| `sched_no_ready_cancelled` | Customer + Driver | إلغاء تلقائي لعدم الرد على «جاهز؟» خلال 15 دقيقة |
| `sched_driver_busy` | Customer | السائق اختار «ليس الآن» — خيار إلغاء أو انتظار 15 دقيقة |
| `sched_passenger_ready` | Driver | الراكب أجاب «جاهز» — «ابدأ الرحلة» أو «ليس الآن» (defer) |

---

## مسارات API (Sanctum)

```
POST /api/requests/{id}/scheduled-passenger-ready
Body: { "ready": true|false }

POST /api/requests/{id}/scheduled-passenger-wait-or-cancel
Body: { "action": "wait" | "cancel" }

POST /api/requests/{id}/scheduled-driver-response
Body: { "action": "start" | "defer" }
```

### سلوك مقترح للخادم

1. **`scheduled-passenger-ready`**
   - `ready: true` → إشعار للسائق `sched_passenger_ready`، تسجيل وقت الرد، إلغاء مهلة الـ 15 دقيقة.
   - `ready: false` («ليس الآن») → إما إلغاء فوري أو تسجيل «غير جاهز» حسب سياساتكم.

2. **`scheduled-passenger-wait-or-cancel`** (بعد `sched_driver_busy`)
   - `cancel` → إلغاء الطلب وإشعار السائق.
   - `wait` → جدولة إعادة إرسال `sched_passenger_ready` (أو إشعار مماثل) للسائق بعد **15 دقيقة**؛ عندها يجب أن يختار السائق **بدء** أو **إلغاء** الطلب.

3. **`scheduled-driver-response`**
   - `start` → يضبط `sched_driver_started_at` ويبقي الحالة **`Reserved`** (لا قفز إلى Running). بعدها السائق يرى «وصلت للراكب» كالطلب الفوري.
   - `defer` → إشعار للراكب `sched_driver_busy` مع نص «السائق مشغول قليلاً» وربطه بـ `wait/cancel`.

---

## جدولة Artisan (كل دقيقة `schedule`)

1. **تذكير 30 دقيقة**  
   طلبات `type = Schedual`، حالة مقبولة (مثلاً `Reserved` مع `driverId`)، `requestDate` بين الآن+25د و الآن+35د، ولم يُرسل `sched_t30` بعد (`reminder_30_sent_at` null).

2. **سؤال الجاهزية (5 دقائق)**  
   نفس الطلبات، `requestDate` بين الآن و الآن+6د (نافذة «قبل 5 دقائق»)، ولم يُرسل `sched_t5_ready` بعد. عند الإرسال:
   - ضبط `passenger_ready_prompt_at = now()`
   - ضبط `passenger_ready_deadline_at = now() + 15 minutes`

3. **إلغاء عدم الرد**  
   حيث `passenger_ready_prompt_at` ليس null، `passenger_ready_response_at` null، و`now() > passenger_ready_deadline_at` → إلغاء الطلب، إشعار `sched_no_ready_cancelled`.

4. **إعادة المحاولة بعد انتظار الراكب**  
   حقل مثل `driver_retry_at` ≤ الآن و`customer_chose_wait = true` → إعادة إشعار السائق ومسح العلامة.

---

## هجرة مقترحة (أعمدة على `requests`)

- `reminder_30_sent_at` (nullable datetime)
- `ready_prompt_sent_at` (nullable datetime)
- `passenger_ready_deadline_at` (nullable datetime)
- `passenger_ready_at` (nullable datetime) — عند `ready: true`
- `driver_busy_notified_at` / `customer_wait_retry_at` (للتأجيل وإعادة الإرسال بعد 15 د)
- `sched_driver_started_at` — بعد ضغط السائق «ابدأ الرحلة» من إشعار `sched_passenger_ready`

---

## إشعارات السائق (HTTP)

أضف مطابقاً لمسار الزبون:

- `GET /api/driver/notifications`
- `GET /api/driver/notifications/unread-count`
- `POST /api/driver/notifications/{id}/read`

نفس شكل صف الإشعار مع `data.kind` و `request_id`.

---

## رفض السائق للحجز المسبق

في مسار الرفض الحالي: إن كان الطلب `Schedual` → `Removed`/ملغى + إشعار للراكب `sched_rejected`.

---

بعد دمج الخادم، اختبر: إنشاء حجز مسبق → قبول سائق → ضبط `requestDate` في المستقبل للاختبار السريع أو استخدام `Carbon::now()->addMinutes(...)`.

---

## Windows (XAMPP) — تشغيل الجدولة كل دقيقة

بدون `schedule:run` كل دقيقة **لن يصل** سؤال «هل أنت جاهز؟» ولا تذكير T-30.

1. انسخ `laravel_patch/run-scheduler.bat` إلى مجلد ثابت (أو شغّله من المشروع بعد تعديل `BACKEND`).
2. افتح **Task Scheduler** → Create Task:
   - Trigger: **Daily**, repeat every **1 minute** for 1 day, indefinitely.
   - Action: Start program → `C:\xampp\htdocs\myapp-backend\..\..\..\path\to\run-scheduler.bat` (أو `php.exe` مع arguments: `artisan schedule:run` و Start in: مجلد `myapp-backend`).
3. تأكد أن `APP_TIMEZONE=Asia/Damascus` في `.env`.
4. تحقق: `php artisan schedule:list` ثم شغّل `run-scheduler.bat` يدوياً مرة — يجب أن يظهر سطر في `scheduler-log.txt`.
