# GS TAXI — لوحة الإدارة (ويب)

تطبيق **React** منفصل عن تطبيق Flutter؛ يدخل **الموظف/المسؤول** من المتصفح فقط، بينما **الراكب والسائق** يبقيان على التطبيق.

## المتطلبات

- Node 18+
- نفس خادم **Laravel API** المستخدم في التطبيق

## الإعداد

```bash
cd admin-web
cp .env.example .env
npm install
npm run dev
```

يفتح عادة على `http://localhost:5173`

### الاتصال بالباك (Laravel) للاختبار

1. شغّل **Apache + MySQL** في XAMPP.
2. تأكد أن الـ API يعمل في المتصفح، مثلاً:
   `http://localhost/SyriaTaxi-main/public/api/login`  
   (قد يظهر JSON وليس صفحة 404).
3. في `.env` اترك الوضع الافتراضي:
   - `VITE_API_BASE_URL=/api`
   - `VITE_LARAVEL_ORIGIN=http://localhost/SyriaTaxi-main/public`  
   غيّر `SyriaTaxi-main` إن كان اسم مجلدك مختلفاً تحت `htdocs`.
4. `npm run dev` — الطلبات من اللوحة تمر عبر Vite إلى Laravel (لا حاجة لضبط CORS في التطوير).

إن أردت الاتصال **مباشرة** بنفس IP الهاتف (`192.168.x.x`)، عطّل `/api` وضع العنوان الكامل في `VITE_API_BASE_URL` كما في `.env.example`.

## تسجيل الدخول

- نفس **رقم الهاتف + كلمة المرور** كما في تطبيق الإدارة.
- يُخزَّن الـ token في `localStorage` (متوافق مع مفاتيح التطبيق: `token`, `user_roll`, `staff_permissions`, `user_id`).

## CORS على Laravel

اسمح لأصل الواجهة (مثل `http://localhost:5173`) في `config/cors.php` أو Sanctum stateful domains حتى تعمل طلبات `Authorization: Bearer`.

## البناء للإنتاج

```bash
npm run build
```

ثم ارفع مجلد `dist` على أي استضافة ثابتة أو خادم ويب، مع ضبط `VITE_API_BASE_URL` وقت البناء:

```bash
set VITE_API_BASE_URL=https://api.example.com/api && npm run build
```

## الصفحات المنقولة

- لوحة التحكم، السائقون، الخصومات، SOS، الطلبات (+ تفاصيل)، الزبائن، الآراء/الشكاوى، الموظفون (عرض)، تغيير كلمة المرور، تصدير CSV، تقرير مالي PDF.
- صفحات تحتاج تعقيداً إضافياً (خريطة تفاعلية، مناطق بمضلعات، تسجيل سائق بصور multipart، فئات السيارة، العداد الحر): تظهر رسالة توجيه؛ يمكن إكمالها لاحقاً بنفس الـ API الموجود في `lib/core/network/api_endpoints.dart`.
