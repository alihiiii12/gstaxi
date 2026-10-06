(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const loginView = $("#login-view");
  const dashView = $("#dash-view");
  const flash = $("#flash");
  let content = null;

  function showFlash(msg, ok = true) {
    if (!flash) return;
    flash.textContent = msg;
    flash.style.color = ok ? "#166534" : "#b91c1c";
  }

  async function api(action, body, isForm = false) {
    const opts = { method: "POST", credentials: "same-origin" };
    if (isForm) {
      body.append("action", action);
      opts.body = body;
    } else {
      const fd = new FormData();
      fd.append("action", action);
      if (body) {
        Object.entries(body).forEach(([k, v]) => fd.append(k, v ?? ""));
      }
      opts.body = fd;
    }
    const res = await fetch("api.php?action=" + encodeURIComponent(action), opts);
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data.success === false) {
      throw new Error(data.message || "فشل الطلب");
    }
    return data;
  }

  async function check() {
    const res = await fetch("api.php?action=me", { credentials: "same-origin" });
    const data = await res.json();
    if (data.logged_in) {
      loginView.classList.add("hidden");
      dashView.classList.remove("hidden");
      await load();
    } else {
      loginView.classList.remove("hidden");
      dashView.classList.add("hidden");
    }
  }

  async function load() {
    const res = await fetch("api.php?action=content&t=" + Date.now(), {
      credentials: "same-origin",
      cache: "no-store",
    });
    const json = await res.json();
    content = json.data || json;
    render();
  }

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  function mediaSrc(src) {
    if (!src) return "";
    if (/^https?:\/\//i.test(src) || src.startsWith("data:") || src.startsWith("/")) {
      return src;
    }
    return "../" + src.replace(/^\.\//, "");
  }

  function render() {
    const c = content || {};
    $("#carousel-list").innerHTML = (c.carousel || [])
      .map(
        (row) => `
      <form class="thumb-edit item-edit" data-action="update_carousel" data-id="${esc(row.id)}">
        <img src="${esc(mediaSrc(row.src))}" alt="" />
        <label>استبدال الصورة <input type="file" name="image" accept="image/*" /></label>
        <label>أو رابط صورة جديد <input type="url" name="url" placeholder="اتركه فارغاً للإبقاء على الصورة" /></label>
        <label>سطر صغير <input name="kicker" value="${esc(row.kicker || "")}" /></label>
        <label>العنوان <input name="title" value="${esc(row.title || "")}" /></label>
        <label>الوصف <textarea name="lead" rows="2">${esc(row.lead || "")}</textarea></label>
        <div class="row">
          <button type="submit">حفظ التعديل</button>
        </div>
      </form>`,
      )
      .join("");

    const heroForm = $("#hero-form");
    if (heroForm) {
      heroForm.kicker.value = c.hero?.kicker || "";
      heroForm.title.value = c.hero?.title || "";
      heroForm.lead.value = c.hero?.lead || "";
    }

    $("#news-list").innerHTML = (c.news || [])
      .map(
        (row) => `
      <form class="edit-card item-edit" data-action="update_news" data-id="${esc(row.id)}">
        <img src="${esc(mediaSrc(row.image))}" alt="" />
        <label>العنوان <input name="title" required value="${esc(row.title || "")}" /></label>
        <label>التاريخ <input name="date" value="${esc(row.date || "")}" /></label>
        <label>النص <textarea name="text" required rows="3">${esc(row.text || "")}</textarea></label>
        <label>استبدال الصورة <input type="file" name="image" accept="image/*" /></label>
        <label>أو رابط صورة جديد <input type="url" name="image_url" /></label>
        <div class="row">
          <button type="submit">حفظ التعديل</button>
          <button type="button" class="danger" data-del-news="${esc(row.id)}">حذف</button>
        </div>
      </form>`,
      )
      .join("");

    $("#ads-list").innerHTML = (c.ads || [])
      .map(
        (row) => `
      <form class="edit-card item-edit" data-action="update_ad" data-id="${esc(row.id)}">
        <label>الوسم <input name="tag" value="${esc(row.tag || "")}" /></label>
        <label>العنوان <input name="title" required value="${esc(row.title || "")}" /></label>
        <label>النص <textarea name="text" required rows="3">${esc(row.text || "")}</textarea></label>
        <label>التاريخ / المدة <input name="date" value="${esc(row.date || "")}" /></label>
        <div class="row">
          <button type="submit">حفظ التعديل</button>
          <button type="button" class="danger" data-del-ad="${esc(row.id)}">حذف</button>
        </div>
      </form>`,
      )
      .join("");

    const f = $("#links-form");
    if (f) {
      f.play.value = c.stores?.play || "";
      f.apple.value = c.stores?.apple || "";
      f.apk.value = c.stores?.apk || "";
      f.instagram.value = c.social?.instagram || "";
      f.facebook.value = c.social?.facebook || "";
      f.whatsapp.value = c.social?.whatsapp || "";
      f.telegram.value = c.social?.telegram || "";
    }
  }

  $("#login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    $("#login-err").textContent = "";
    try {
      const fd = new FormData(e.target);
      await api("login", { password: fd.get("password") });
      await check();
    } catch (err) {
      $("#login-err").textContent = err.message;
    }
  });

  $("#logout-btn").addEventListener("click", async () => {
    await api("logout");
    await check();
  });

  document.querySelectorAll(".tabs button").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tabs button").forEach((b) => b.classList.remove("is-on"));
      btn.classList.add("is-on");
      document.querySelectorAll(".panel").forEach((p) => p.classList.add("hidden"));
      $("#tab-" + btn.dataset.tab).classList.remove("hidden");
    });
  });

  $("#hero-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await api("save_hero", new FormData(e.target), true);
      await load();
      showFlash("تم حفظ نص الواجهة");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  $("#carousel-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await api("add_carousel", new FormData(e.target), true);
      e.target.reset();
      await load();
      showFlash("تمت إضافة صورة الكاروسيل");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  $("#news-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await api("add_news", new FormData(e.target), true);
      e.target.reset();
      await load();
      showFlash("تم نشر الخبر");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  $("#ad-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await api("add_ad", new FormData(e.target), true);
      e.target.reset();
      await load();
      showFlash("تم إضافة الإعلان");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  $("#links-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      await api("save_links", new FormData(e.target), true);
      await load();
      showFlash("تم حفظ الروابط");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  document.addEventListener("submit", async (e) => {
    const form = e.target;
    if (!(form instanceof HTMLFormElement) || !form.classList.contains("item-edit")) return;
    e.preventDefault();
    try {
      const action = form.dataset.action || "update_carousel";
      const fd = new FormData(form);
      fd.append("id", form.dataset.id || "");
      await api(action, fd, true);
      await load();
      showFlash("تم حفظ التعديل");
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  document.addEventListener("click", async (e) => {
    const t = e.target;
    if (!(t instanceof HTMLElement)) return;
    try {
      if (t.dataset.delNews) {
        await api("delete_news", { id: t.dataset.delNews });
        await load();
      }
      if (t.dataset.delAd) {
        await api("delete_ad", { id: t.dataset.delAd });
        await load();
      }
    } catch (err) {
      showFlash(err.message, false);
    }
  });

  void check();
})();
