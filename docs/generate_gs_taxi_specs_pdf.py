# -*- coding: utf-8 -*-
"""Generate GS Taxi technical specifications PDF (Arabic)."""
from pathlib import Path

from fpdf import FPDF

OUT = Path(__file__).resolve().parent / "GS_Taxi_المواصفات_الفنية.pdf"
FONT = Path(r"C:\Windows\Fonts\tahoma.ttf")
FONT_B = Path(r"C:\Windows\Fonts\tahomabd.ttf")


class Pdf(FPDF):
    def footer(self):
        self.set_y(-15)
        self.set_font("Tahoma", size=9)
        self.set_text_color(100, 100, 100)
        self.cell(0, 10, f"GS Taxi — صفحة {self.page_no()}", align="C")


def section_title(pdf: Pdf, text: str):
    pdf.ln(4)
    pdf.set_font("TahomaB", size=13)
    pdf.set_text_color(20, 20, 20)
    pdf.multi_cell(0, 8, text, align="R")
    pdf.set_draw_color(230, 180, 34)
    pdf.line(15, pdf.get_y(), 195, pdf.get_y())
    pdf.ln(3)


def field(pdf: Pdf, label: str, value: str):
    pdf.set_font("TahomaB", size=11)
    pdf.set_text_color(60, 60, 60)
    pdf.multi_cell(0, 7, label, align="R")
    pdf.set_font("Tahoma", size=11)
    pdf.set_text_color(0, 0, 0)
    pdf.multi_cell(0, 7, value, align="R")
    pdf.ln(2)


def main():
    pdf = Pdf()
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.add_page()
    pdf.add_font("Tahoma", "", str(FONT))
    pdf.add_font("TahomaB", "", str(FONT_B))
    pdf.set_font("TahomaB", size=18)
    pdf.set_text_color(14, 17, 22)
    pdf.multi_cell(0, 10, "GS Taxi — المواصفات الفنية والأرشفة", align="C")
    pdf.set_font("Tahoma", size=11)
    pdf.set_text_color(80, 80, 80)
    pdf.multi_cell(
        0,
        7,
        "نموذج للتقديم إلى هيئة تنظيم الاتصالات والتقنية — تطبيق GS Taxi",
        align="C",
    )
    pdf.ln(6)

    section_title(pdf, "المواصفات الفنية")

    field(
        pdf,
        "1) الاستضافة — نوعها ومكانها:",
        "استضافة VPS (خادم افتراضي خاص) من شركة Waves Internet — دمشق، سوريا.\n"
        "الخدمة: Advanced VPS مع IP حقيقي (2).\n"
        "مدة الاشتراك: من 01-08-2026 إلى 31-07-2027.\n"
        "النطاق: gstaxi.online (تسجيل/تجديد ضمن الاشتراك).",
    )
    field(pdf, "2) نظام التشغيل:", "Ubuntu Server 24.04 LTS (Linux)")
    field(pdf, "3) نوع قاعدة البيانات:", "MySQL — قاعدة بيانات علائقية (Relational Database)")
    field(
        pdf,
        "4) بيئة البرمجة (Backend / API):",
        "PHP 8.x — Laravel — Nginx + PHP-FPM — Composer",
    )
    field(
        pdf,
        "5) بيئة برمجة التطبيق (Mobile App):",
        "Flutter / Dart — Android (Google Play — AAB) — iOS (App Store) عند التوفر",
    )
    field(
        pdf,
        "6) مواصفات السيرفر (حسب فاتورة Waves):",
        "المعالج: 4 Core CPU\n"
        "الذاكرة: 12 GB RAM\n"
        "التخزين: 200 GB HDD\n"
        "الشبكة: 2 IP حقيقي — حركة بيانات 500 GB/شهر\n"
        "الوصول: SSH (مفاتيح وصول) — بدون لوحة تحكم من المزود",
    )

    section_title(pdf, "الأرشفة")

    field(
        pdf,
        "الداتا التي يتم أرشفتها هي:",
        "بيانات المستخدمين (ركاب وسائقين) — بيانات الرحلات والطلبات — "
        "سجلات الدفع والفواتير — الشكاوى والإشعارات — سجلات النظام عند الحاجة.",
    )
    field(pdf, "نسخة احتياطية بشكل دوري كل:", "يومياً (Daily backup) مع نسخ إضافية أسبوعية عند الحاجة.")
    field(
        pdf,
        "مكان حفظ النسخة الاحتياطية:",
        "على السيرفر (مجلد backups محلي) و/أو نسخة خارجية (تخزين سحابي أو سيرفر ثانٍ).",
    )
    field(pdf, "برنامج قواعد البيانات:", "MySQL 8.x (أو MariaDB 10.x)")

    section_title(pdf, "التعهد")

    pdf.set_font("TahomaB", size=12)
    pdf.multi_cell(
        0,
        8,
        "أتعهد بالاحتفاظ بالبيانات لمدة سنة واحدة على الأقل أونلاين.",
        align="R",
    )
    pdf.ln(8)

    section_title(pdf, "بيانات الشركة والمزود")

    field(
        pdf,
        "الشركة:",
        "GS Taxi / GS Taxi APP",
    )
    field(
        pdf,
        "المزود:",
        "Waves Internet — www.wavesnet.sy — info@wavesnet.sy — +963 11 373 9730/31",
    )
    field(
        pdf,
        "الغرض:",
        "تشغيل تطبيق GS Taxi (طلب تكسي، تتبع، دفع، إشعارات)",
    )
    field(
        pdf,
        "التواصل:",
        "taxi2026.sy@gmail.com — 0944767773",
    )
    field(
        pdf,
        "العنوان:",
        "المزة شرقية، بعد أفران الاحتياطية بـ 300م، بناء مسعود — دمشق",
    )

    pdf.ln(12)
    pdf.set_font("Tahoma", size=11)
    pdf.cell(95, 8, "التوقيع: ____________________", align="R")
    pdf.ln(8)
    pdf.cell(95, 8, "الاسم: الأستاذ علاء الغفير — المدير التنفيذي", align="R")
    pdf.ln(8)
    pdf.cell(95, 8, "التاريخ: ____ / ____ / 2026", align="R")

    pdf.output(str(OUT))
    print(OUT)


if __name__ == "__main__":
    main()
