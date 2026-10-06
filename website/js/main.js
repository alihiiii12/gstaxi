(() => {
  const header = document.querySelector(".site-header");
  const toggle = document.querySelector(".nav-toggle");
  const links = document.querySelector(".nav-links");

  const onScroll = () => {
    if (!header) return;
    header.classList.toggle("is-solid", window.scrollY > 40);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  if (toggle && links) {
    toggle.addEventListener("click", () => {
      links.classList.toggle("is-open");
    });
    links.querySelectorAll("a").forEach((a) => {
      a.addEventListener("click", () => links.classList.remove("is-open"));
    });
  }

  const reveals = document.querySelectorAll(".reveal");
  if (!document.querySelector(".carousel") && reveals.length) {
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
        { threshold: 0.15 },
      );
      reveals.forEach((el) => io.observe(el));
    } else {
      reveals.forEach((el) => el.classList.add("is-visible"));
    }
  }

  /* Contact form — mailto fallback */
  const form = document.querySelector("#contact-form");
  if (form) {
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const fd = new FormData(form);
      const name = String(fd.get("name") || "").trim();
      const phone = String(fd.get("phone") || "").trim();
      const subject = String(fd.get("subject") || "رسالة من الموقع").trim();
      const message = String(fd.get("message") || "").trim();
      const body = encodeURIComponent(
        `الاسم: ${name}\nالهاتف: ${phone}\n\n${message}`,
      );
      window.location.href = `mailto:taxi2026.sy@gmail.com?subject=${encodeURIComponent(subject)}&body=${body}`;
    });
  }
})();
