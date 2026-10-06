(() => {
  const ICONS = {
    play: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#EA4335" d="M3.6 2.2 13.4 12 3.6 21.8A2 2 0 0 1 3 20.3V3.7a2 2 0 0 1 .6-1.5z"/><path fill="#4285F4" d="m13.4 12 3.2-3.2 4.4 2.5c.9.5.9 1.9 0 2.4l-4.4 2.5L13.4 12z"/><path fill="#FBBC04" d="M16.6 15.3 13.4 12 3.6 21.8c.4.5 1 .8 1.7.8.4 0 .8-.1 1.2-.3l10.1-7z"/><path fill="#34A853" d="M16.6 8.7 6.5 2.7A2.5 2.5 0 0 0 3.6 2.2L13.4 12l3.2-3.3z"/></svg>`,
    apple: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M16.7 12.9c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.2-2.8.9-3.5.9s-1.8-.8-3-.8c-1.6 0-3 1-3.8 2.5-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.3 2.9 2.3 1.1 0 1.6-.8 3-.8s1.8.8 3 .8 2.1-1.2 2.8-2.3c.9-1.2 1.2-2.4 1.2-2.5-.1 0-2.4-1-2.4-4.1zm-2.2-6.5c.6-.8 1.1-1.9 1-3-1 .1-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.8 1.1.1 2.1-.5 2.8-1.3z"/></svg>`,
    apk: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M17.6 9.5 19 8.1a.8.8 0 1 0-1.1-1.1l-1.5 1.4A7.9 7.9 0 0 0 12 7.2c-1.6 0-3.1.5-4.4 1.2L6.1 7a.8.8 0 1 0-1.1 1.1l1.4 1.4A7.8 7.8 0 0 0 4 15.2h16a7.8 7.8 0 0 0-2.4-5.7zM8.6 13a1 1 0 1 1 0-2 1 1 0 0 1 0 2zm6.8 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2zM7.3 17.2c.4 2.2 2.3 3.8 4.7 3.8s4.3-1.6 4.7-3.8H7.3z"/></svg>`,
    ig: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 7.2A4.8 4.8 0 1 0 16.8 12 4.8 4.8 0 0 0 12 7.2zm0 7.9A3.1 3.1 0 1 1 15.1 12 3.1 3.1 0 0 1 12 15.1zm6.4-8.2a1.1 1.1 0 1 1-1.1-1.1 1.1 1.1 0 0 1 1.1 1.1zM12 4.4c-2.1 0-2.3 0-3.2.1-2.1.1-3.2 1.2-3.3 3.3-.1.8 0 1.1-.1 3.2s0 2.3.1 3.2c.1 2.1 1.2 3.2 3.3 3.3.8.1 1.1.1 3.2.1s2.3 0 3.2-.1c2.1-.1 3.2-1.2 3.3-3.3.1-.8.1-1.1.1-3.2s0-2.3-.1-3.2c-.1-2.1-1.2-3.2-3.3-3.3-.8-.1-1.1-.1-3.2-.1zm0-1.9c2.1 0 2.4 0 3.3.1 2.8.1 4.5 1.8 4.6 4.6.1.9.1 1.2.1 3.3s0 2.4-.1 3.3c-.1 2.8-1.8 4.5-4.6 4.6-.9.1-1.2.1-3.3.1s-2.4 0-3.3-.1c-2.8-.1-4.5-1.8-4.6-4.6C4.4 14.4 4.4 14.1 4.4 12s0-2.4.1-3.3c.1-2.8 1.8-4.5 4.6-4.6.9-.1 1.2-.1 3.3-.1z"/></svg>`,
    fb: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M13.5 21v-7.2h2.4l.4-2.8h-2.8V9.2c0-.8.2-1.4 1.4-1.4h1.5V5.3c-.3 0-1.2-.1-2.2-.1-2.2 0-3.7 1.3-3.7 3.8v2h-2.5v2.8h2.5V21h3z"/></svg>`,
    wa: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12.04 3.1A8.9 8.9 0 0 0 3.1 12c0 1.57.41 3.1 1.2 4.45L3 21l4.68-1.23A8.9 8.9 0 0 0 12.04 21 8.9 8.9 0 0 0 21 12.04 8.9 8.9 0 0 0 12.04 3.1zm0 16.2a7.4 7.4 0 0 1-3.77-1.04l-.27-.16-2.78.73.74-2.7-.18-.28a7.4 7.4 0 1 1 6.26 4.15zm4.06-5.54c-.22-.11-1.32-.65-1.52-.72s-.35-.11-.5.11-.58.72-.71.87-.26.17-.48.06a6 6 0 0 1-1.77-1.09 6.6 6.6 0 0 1-1.22-1.52c-.13-.22 0-.34.1-.45.1-.1.22-.26.33-.39s.15-.22.22-.37.04-.28-.02-.39c-.06-.11-.5-1.2-.68-1.65s-.36-.38-.5-.39h-.43c-.15 0-.39.06-.59.28s-.78.76-.78 1.85.8 2.15.91 2.3c.11.15 1.57 2.4 3.8 3.36.53.23.95.36 1.27.47.54.17 1.02.14 1.41.09.43-.06 1.32-.54 1.5-1.06s.18-.97.13-1.06c-.05-.1-.2-.15-.42-.26z"/></svg>`,
    tg: `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M19.8 5.2 17.4 17c-.2.8-.7 1-1.3.6l-3.6-2.7-1.7 1.7c-.2.2-.4.4-.8.4l.3-3.7 6.7-6.1c.3-.2 0-.4-.4-.2L7.4 11.3 3.8 10c-.8-.2-.8-.8.2-1.2L18.7 4c.7-.2 1.3.2 1.1 1.2z"/></svg>`,
  };

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  function siteBase() {
    const p = location.pathname;
    if (p.endsWith("/")) return p;
    const last = p.split("/").pop() || "";
    if (last.includes(".")) return p.replace(/\/[^/]+$/, "/");
    return p + "/";
  }

  function mediaSrc(src) {
    if (!src) return "";
    if (/^https?:\/\//i.test(src) || src.startsWith("data:")) return src;
    if (src.startsWith("/")) return src;
    return siteBase() + src.replace(/^\.\//, "").replace(/^\/+/, "");
  }

  function applyHeroText(slide, fallback) {
    const kicker = document.querySelector(".hero-kicker");
    const title = document.querySelector(".hero-title");
    const lead = document.querySelector(".hero-lead");
    const k = (slide && slide.kicker) || fallback.kicker || "";
    const t = (slide && slide.title) || fallback.title || "";
    const l = (slide && slide.lead) || fallback.lead || "";
    if (kicker) kicker.textContent = k;
    if (title) title.textContent = t;
    if (lead) lead.textContent = l;
  }

  function initCarousel(slidesData, fallbackHero) {
    const slides = [...document.querySelectorAll(".carousel-slide")];
    const dotsWrap = document.querySelector(".carousel-dots");
    if (!slides.length || !dotsWrap) return;
    dotsWrap.innerHTML = "";
    let index = 0;
    let timer;
    slides.forEach((_, i) => {
      const b = document.createElement("button");
      b.type = "button";
      b.setAttribute("aria-label", `شريحة ${i + 1}`);
      if (i === 0) b.classList.add("is-active");
      b.addEventListener("click", () => go(i));
      dotsWrap.appendChild(b);
    });
    const dots = [...dotsWrap.querySelectorAll("button")];
    function go(i) {
      slides[index].classList.remove("is-active");
      dots[index].classList.remove("is-active");
      index = i;
      slides[index].classList.add("is-active");
      dots[index].classList.add("is-active");
      applyHeroText(slidesData[i], fallbackHero);
      restart();
    }
    function next() {
      go((index + 1) % slides.length);
    }
    function restart() {
      clearInterval(timer);
      timer = setInterval(next, 5500);
    }
    applyHeroText(slidesData[0], fallbackHero);
    restart();
  }

  function observeReveals() {
    const reveals = document.querySelectorAll(".reveal");
    if ("IntersectionObserver" in window) {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((e) => {
            if (e.isIntersecting) {
              e.target.classList.add("is-visible");
              io.unobserve(e.target);
            }
          });
        },
        { threshold: 0.12 },
      );
      reveals.forEach((el) => io.observe(el));
    } else {
      reveals.forEach((el) => el.classList.add("is-visible"));
    }
  }

  function render(data) {
    const hero = data.hero || {};
    const slidesData = Array.isArray(data.carousel) ? data.carousel : [];
    applyHeroText(slidesData[0], hero);

    const carousel = document.querySelector(".carousel");
    if (carousel && slidesData.length) {
      carousel.innerHTML = slidesData
        .map(
          (row, i) =>
            `<div class="carousel-slide${i === 0 ? " is-active" : ""}"><img src="${esc(mediaSrc(row.src))}" alt="" /></div>`,
        )
        .join("");
    }

    const newsGrid = document.querySelector(".news-grid");
    if (newsGrid && Array.isArray(data.news)) {
      newsGrid.innerHTML = data.news
        .map(
          (row) => `
        <article class="news-item reveal">
          <figure><img src="${esc(mediaSrc(row.image))}" alt="${esc(row.title)}" loading="lazy" /></figure>
          <div>
            <p class="news-meta">${esc(row.date)}</p>
            <h3>${esc(row.title)}</h3>
            <p>${esc(row.text)}</p>
          </div>
        </article>`,
        )
        .join("");
    }

    const adsRail = document.querySelector(".ads-rail");
    if (adsRail && Array.isArray(data.ads)) {
      adsRail.innerHTML = data.ads
        .map(
          (row) => `
        <article class="ad-row reveal">
          <span class="ad-tag">${esc(row.tag || "عرض")}</span>
          <div>
            <h3>${esc(row.title)}</h3>
            <p>${esc(row.text)}</p>
          </div>
          <time class="ad-date">${esc(row.date || "")}</time>
        </article>`,
        )
        .join("");
    }

    const stores = data.stores || {};
    const playUrl =
      "https://play.google.com/store/apps/details?id=com.syriataxi.syriatax";
    const storeWrap = document.querySelector(".store-btns");
    if (storeWrap) {
      storeWrap.innerHTML = `
        <a class="store-btn" href="${esc(playUrl)}" target="_blank" rel="noopener noreferrer">
          <span class="store-ico-wrap">${ICONS.play}</span>
          <span class="store-copy"><small>GET IT ON</small><strong>Google Play</strong></span>
        </a>
        <a class="store-btn" href="${esc(stores.apple || "https://apps.apple.com")}" target="_blank" rel="noopener noreferrer">
          <span class="store-ico-wrap">${ICONS.apple}</span>
          <span class="store-copy"><small>Download on the</small><strong>App Store</strong></span>
        </a>
        <a class="store-btn apk" href="${esc(stores.apk || "https://gstaxi.online/downloads/gstaxi.apk")}">
          <span class="store-ico-wrap">${ICONS.apk}</span>
          <span class="store-copy"><small>تحميل مباشر</small><strong>Android APK</strong></span>
        </a>`;
    }

    const DEFAULTS = {
      instagram: "https://www.instagram.com/gstaxi2026",
      facebook: "https://www.facebook.com/profile.php?id=61568816821576",
      whatsapp: "https://wa.me/963944767773",
      email: "taxi2026.sy@gmail.com",
      phone: "0944767773",
      phoneTel: "+963944767773",
      address: "المزة شرقية، بعد أفران الاحتياطية بـ 300م، بناء مسعود",
    };
    const STALE = [
      "https://instagram.com/gstaxi",
      "https://facebook.com/gstaxi",
      "https://wa.me/963900000000",
      "https://t.me/gstaxi",
      "info@gstaxi.online",
    ];
    function pick(val, fallback) {
      const v = String(val || "").trim();
      if (!v || STALE.includes(v)) return fallback;
      return v;
    }

    const social = data.social || {};
    const contact = data.contact || {};
    const ig = pick(social.instagram, DEFAULTS.instagram);
    const fb = pick(social.facebook, DEFAULTS.facebook);
    const wa = pick(social.whatsapp, DEFAULTS.whatsapp);
    const tg = pick(social.telegram, "");
    const email = pick(contact.email || social.email, DEFAULTS.email);
    const phone = pick(contact.phone, DEFAULTS.phone);
    const phoneTel = pick(contact.phoneTel, DEFAULTS.phoneTel);
    const address = pick(contact.address, DEFAULTS.address);

    const phoneEl = document.querySelector("[data-contact=phone]");
    if (phoneEl) {
      phoneEl.href = "tel:" + phoneTel;
      phoneEl.textContent = phone;
    }
    const waEl = document.querySelector("[data-contact=whatsapp]");
    if (waEl) waEl.href = wa;
    const emailEl = document.querySelector("[data-contact=email]");
    if (emailEl) {
      emailEl.href = "mailto:" + email;
      emailEl.textContent = email;
    }
    const addressEl = document.querySelector("[data-contact=address]");
    if (addressEl) addressEl.textContent = address;
    const mapEl = document.querySelector("[data-contact=map]");
    if (mapEl) mapEl.textContent = "GS Taxi — " + address;

    const socialRow = document.querySelector(".social-row");
    if (socialRow) {
      const parts = [
        `<a class="social-link" href="${esc(ig)}" target="_blank" rel="noopener noreferrer">
          <span class="social-ico ig">${ICONS.ig}</span>
          <span class="social-copy"><small>إنستغرام</small><strong>@gstaxi2026</strong></span>
        </a>`,
        `<a class="social-link" href="${esc(fb)}" target="_blank" rel="noopener noreferrer">
          <span class="social-ico fb">${ICONS.fb}</span>
          <span class="social-copy"><small>فيسبوك</small><strong>GS Taxi</strong></span>
        </a>`,
        `<a class="social-link" href="${esc(wa)}" target="_blank" rel="noopener noreferrer">
          <span class="social-ico wa">${ICONS.wa}</span>
          <span class="social-copy"><small>واتساب</small><strong>${esc(phone)}</strong></span>
        </a>`,
        `<a class="social-link" href="mailto:${esc(email)}">
          <span class="social-ico">@</span>
          <span class="social-copy"><small>البريد</small><strong>${esc(email)}</strong></span>
        </a>`,
      ];
      if (tg) {
        parts.push(`<a class="social-link" href="${esc(tg)}" target="_blank" rel="noopener noreferrer">
          <span class="social-ico tg">${ICONS.tg}</span>
          <span class="social-copy"><small>تلغرام</small><strong>Telegram</strong></span>
        </a>`);
      }
      socialRow.innerHTML = parts.join("");
    }

    initCarousel(slidesData, hero);
    observeReveals();
  }

  fetch("content.php?t=" + Date.now(), { cache: "no-store" })
    .then((r) => {
      if (!r.ok) throw new Error("content.php");
      return r.json();
    })
    .then(render)
    .catch(() =>
      fetch("admin/api.php?action=content&t=" + Date.now(), { cache: "no-store" })
        .then((r) => r.json())
        .then((json) => render(json.data || json)),
    )
    .catch(() => {
      initCarousel([], {});
      observeReveals();
    });
})();
