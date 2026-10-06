<?php require __DIR__.'/config.php'; ?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>لوحة إدارة الموقع | GS Taxi</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <link rel="stylesheet" href="admin.css?v=<?= (int) @filemtime(__DIR__.'/admin.css') ?>" />
  </head>
  <body>
    <div id="login-view" class="login-wrap hidden">
      <form id="login-form" class="login-card">
        <h1>لوحة إدارة الموقع</h1>
        <p>أدخل كلمة المرور لإدارة الكاروسيل والأخبار والإعلانات.</p>
        <input type="password" name="password" required placeholder="كلمة المرور" />
        <button type="submit">دخول</button>
        <p id="login-err" class="err"></p>
      </form>
    </div>

    <div id="dash-view" class="hidden">
      <header class="top">
        <strong>GS Taxi — إدارة الموقع <small style="opacity:.65;font-weight:500">v4</small></strong>
        <div class="top-actions">
          <a href="../index.html" target="_blank" rel="noopener">عرض الموقع</a>
          <button type="button" id="logout-btn">خروج</button>
        </div>
      </header>
      <nav class="tabs">
        <button type="button" data-tab="carousel" class="is-on">الكاروسيل</button>
        <button type="button" data-tab="news">الأخبار</button>
        <button type="button" data-tab="ads">الإعلانات</button>
        <button type="button" data-tab="links">الروابط والأيقونات</button>
      </nav>

      <main class="pad">
        <section id="tab-carousel" class="panel">
          <h2>نص الواجهة فوق الكاروسيل</h2>
          <form id="hero-form" class="card form">
            <label>السطر الصغير <input name="kicker" /></label>
            <label>العنوان الكبير <input name="title" /></label>
            <label>الوصف <textarea name="lead" rows="3"></textarea></label>
            <p class="hint">يُستخدم إن لم تكتب نصاً خاصاً للشريحة.</p>
            <button type="submit">حفظ النص</button>
          </form>

          <h2>صور الكاروسيل</h2>
          <form id="carousel-form" class="card form">
            <label>رفع صورة
              <input type="file" name="image" accept="image/*" />
            </label>
            <label>أو رابط صورة
              <input type="url" name="url" placeholder="https://..." />
            </label>
            <label>سطر صغير لهذه الشريحة <input name="kicker" /></label>
            <label>عنوان الشريحة <input name="title" /></label>
            <label>وصف الشريحة <textarea name="lead" rows="2"></textarea></label>
            <button type="submit">إضافة للعرض</button>
          </form>
          <div id="carousel-list" class="thumbs"></div>
        </section>

        <section id="tab-news" class="panel hidden">
          <h2>خبر جديد مع صورة</h2>
          <form id="news-form" class="card form">
            <label>العنوان <input name="title" required /></label>
            <label>التاريخ <input name="date" placeholder="أغسطس 2026" /></label>
            <label>النص <textarea name="text" required rows="3"></textarea></label>
            <label>صورة الخبر <input type="file" name="image" accept="image/*" /></label>
            <label>أو رابط الصورة <input type="url" name="image_url" /></label>
            <button type="submit">نشر الخبر</button>
          </form>
          <h2>الأخبار الحالية — يمكن تعديل أي خبر</h2>
          <div id="news-list" class="stack"></div>
        </section>

        <section id="tab-ads" class="panel hidden">
          <h2>إعلان جديد</h2>
          <form id="ad-form" class="card form">
            <label>الوسم <input name="tag" placeholder="عرض" /></label>
            <label>العنوان <input name="title" required /></label>
            <label>النص <textarea name="text" required rows="3"></textarea></label>
            <label>التاريخ / المدة <input name="date" placeholder="حتى نهاية الشهر" /></label>
            <button type="submit">إضافة الإعلان</button>
          </form>
          <h2>الإعلانات الحالية — يمكن تعديل أي إعلان</h2>
          <div id="ads-list" class="stack"></div>
        </section>

        <section id="tab-links" class="panel hidden">
          <h2>روابط التطبيق والتواصل</h2>
          <form id="links-form" class="card form">
            <h3>متاجر التطبيق</h3>
            <label>Google Play <input name="play" type="url" /></label>
            <label>App Store <input name="apple" type="url" /></label>
            <label>رابط APK <input name="apk" type="url" /></label>
            <h3>وسائل التواصل</h3>
            <label>إنستغرام <input name="instagram" type="url" /></label>
            <label>فيسبوك <input name="facebook" type="url" /></label>
            <label>واتساب <input name="whatsapp" type="url" placeholder="https://wa.me/963..." /></label>
            <label>تلغرام <input name="telegram" type="url" placeholder="https://t.me/..." /></label>
            <button type="submit">حفظ الروابط</button>
          </form>
        </section>
        <p id="flash" class="flash"></p>
      </main>
    </div>
    <script src="admin.js?v=<?= (int) @filemtime(__DIR__.'/admin.js') ?>"></script>
  </body>
</html>
