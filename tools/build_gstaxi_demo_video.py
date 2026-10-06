# -*- coding: utf-8 -*-
"""Build a silent GS Taxi demo MP4: on-screen Arabic titles + soft music bed."""

from __future__ import annotations

import subprocess
from pathlib import Path

import arabic_reshaper
from bidi.algorithm import get_display
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "build" / "gstaxi_demo_video"
FRAMES_DIR = OUT_DIR / "frames"
AUDIO_PATH = OUT_DIR / "music_bed.wav"
CONCAT_PATH = OUT_DIR / "concat.txt"
VIDEO_PATH = ROOT / "build" / "GS_Taxi_App_Demo.mp4"

W, H = 1080, 1920  # vertical
FPS = 30
FONT_PATH = Path(r"C:\Windows\Fonts\DUBAI-BOLD.TTF")
FONT_REG = Path(r"C:\Windows\Fonts\DUBAI-REGULAR.TTF")
if not FONT_PATH.exists():
    FONT_PATH = Path(r"C:\Windows\Fonts\arialbd.ttf")
    FONT_REG = Path(r"C:\Windows\Fonts\arial.ttf")

# (duration_sec, title, subtitle, section)
SHOTS: list[tuple[float, str, str, str]] = [
    (5, "GS Taxi", "طلب تاكسي · بسهولة · في أي وقت", "intro"),
    (4, "GS Taxi", "شرح التطبيق · بدون تعليق صوتي", "intro"),
    # Passenger
    (6, "الراكب", "تسجيل الدخول", "passenger"),
    (7, "الخريطة", "موقعك الحالي على الخريطة", "passenger"),
    (6, "احجز رحلتك", "بضغطة واحدة تبدأ", "passenger"),
    (8, "ابحث عن وجهتك", "داخل سوريا · نتائج فورية", "passenger"),
    (7, "حدد من الخريطة", "حرّك الدبوس إلى المكان", "passenger"),
    (6, "المواقع المفضلة", "اختيار أسرع للوجهات المتكررة", "passenger"),
    (8, "فئة السيارة", "اختر الفئة المناسبة لرحلتك", "passenger"),
    (7, "السعر التقريبي", "اعرف التكلفة قبل الإرسال", "passenger"),
    (7, "كود خصم", "أدخل الكود وشاهد السعر بعد التخفيض", "passenger"),
    (7, "حجز فوري", "إرسال الطلب للسائقين القريبين", "passenger"),
    (6, "بانتظار القبول", "السائقون يستلمون طلبك الآن", "passenger"),
    (7, "تم قبول طلبك", "السائق في الطريق إليك", "passenger"),
    (10, "تتبع مباشر", "شاهد حركة السائق على الخريطة", "passenger"),
    (8, "مراحل الرحلة", "متوجه إليك · وصل · بدأت الرحلة", "passenger"),
    (6, "تواصل مع السائق", "اتصال سريع عند الحاجة", "passenger"),
    (10, "حجز مسبق", "اختر الموعد والسائق المناسب", "passenger"),
    (8, "طلباتي", "فوري · مجدول · أرشيف", "passenger"),
    (6, "قيّم رحلتك", "بعد الانتهاء مباشرة", "passenger"),
    (6, "حسابك", "البيانات · الإعدادات · تسجيل الخروج", "passenger"),
    # Driver
    (5, "GS Taxi", "للسائق", "driver"),
    (6, "دخول السائق", "سجّل وادخل إلى الخريطة", "driver"),
    (7, "خريطتك", "موقعك واتجاهك الحي", "driver"),
    (8, "متصل", "اسحب للبدء · استقبال الطلبات", "driver"),
    (7, "يعمل في الخلفية", "الموقع يستمر وأنت خارج التطبيق", "driver"),
    (7, "طلب فوري جديد", "تظهر بطاقة الطلب فوراً", "driver"),
    (6, "قبول أو تجاهل", "بقرار واحد", "driver"),
    (7, "قائمة الطلبات", "فوري ومجدول في مكان واحد", "driver"),
    (8, "توجّه إلى الراكب", "ابدأ التنقّل نحو نقطة الانطلاق", "driver"),
    (10, "تنقّل حي", "مسار على الخريطة ومتابعة الكاميرا", "driver"),
    (6, "وصلت", "تأكيد الوصول لموقع الراكب", "driver"),
    (7, "بدء الرحلة", "انطلق نحو الوجهة", "driver"),
    (7, "إنهاء الرحلة", "إتمام الأجرة وإغلاق الطلب", "driver"),
    (9, "العداد الحر", "رحلة خارج طلب التطبيق", "driver"),
    (9, "حساب المسافة والوقت", "التكلفة تتحدث أثناء القيادة", "driver"),
    (7, "أثناء العداد الحر", "لا استقبال لطلبات التطبيق", "driver"),
    (7, "SOS", "إبلاغ الإدارة فوراً", "driver"),
    (7, "خرائط أوفلاين", "حمّل مناطق سوريا للعمل بدون نت", "driver"),
    (6, "ملفك وسجلك", "بيانات السائق ورحلاتك", "driver"),
    (6, "غير متصل", "اسحب للإيقاف عند الانتهاء", "driver"),
    # Outro
    (6, "راكب · سائق", "رحلة أوضح مع GS Taxi", "outro"),
    (5, "GS Taxi", "اطلب · اقبل · وصل", "outro"),
    (4, "GS Taxi", "", "outro"),
]


def ar(text: str) -> str:
    if not text:
        return ""
    return get_display(arabic_reshaper.reshape(text))


def section_colors(section: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    if section == "passenger":
        return (17, 33, 91), (255, 193, 7)
    if section == "driver":
        return (10, 24, 64), (76, 175, 80)
    if section == "outro":
        return (8, 16, 48), (255, 213, 79)
    return (12, 20, 55), (255, 193, 7)


def draw_phone(draw: ImageDraw.ImageDraw, accent: tuple[int, int, int]) -> None:
    x0, y0, x1, y1 = 120, 220, W - 120, H - 280
    draw.rounded_rectangle([x0, y0, x1, y1], radius=56, fill=(245, 247, 250))
    draw.rounded_rectangle([x0, y0, x1, y1], radius=56, outline=accent, width=6)
    # status bar
    draw.rounded_rectangle([x0 + 18, y0 + 18, x1 - 18, y0 + 70], radius=16, fill=(17, 33, 91))
    # map area
    draw.rounded_rectangle([x0 + 28, y0 + 90, x1 - 28, y1 - 220], radius=24, fill=(220, 232, 220))
    # fake roads
    for i in range(6):
        yy = y0 + 160 + i * 140
        draw.line([(x0 + 50, yy), (x1 - 50, yy)], fill=(210, 198, 160), width=10)
    for i in range(4):
        xx = x0 + 120 + i * 180
        draw.line([(xx, y0 + 110), (xx, y1 - 240)], fill=(210, 198, 160), width=8)
    # taxi marker
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2 - 40
    draw.ellipse([cx - 28, cy - 28, cx + 28, cy + 28], fill=accent)
    draw.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=(17, 33, 91))
    # bottom panel
    draw.rounded_rectangle([x0 + 28, y1 - 200, x1 - 28, y1 - 40], radius=22, fill=(255, 255, 255))
    draw.rounded_rectangle(
        [x0 + 80, y1 - 150, x1 - 80, y1 - 90], radius=28, fill=accent
    )


def render_slide(
    title: str,
    subtitle: str,
    section: str,
    index: int,
    total: int,
) -> Image.Image:
    bg, accent = section_colors(section)
    img = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(img)

    # soft circles
    for r, a in ((420, 18), (280, 28), (160, 40)):
        overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.ellipse([W // 2 - r, -r // 2, W // 2 + r, r], fill=(*accent, a))
        img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
        draw = ImageDraw.Draw(img)

    brand_font = ImageFont.truetype(str(FONT_PATH), 54)
    title_font = ImageFont.truetype(str(FONT_PATH), 72)
    sub_font = ImageFont.truetype(str(FONT_REG), 44)
    small_font = ImageFont.truetype(str(FONT_REG), 32)

    draw.text((W // 2, 90), ar("GS Taxi"), font=brand_font, fill=accent, anchor="mm")
    draw_phone(draw, accent)

    # title card at bottom third
    panel = [60, H - 420, W - 60, H - 80]
    draw.rounded_rectangle(panel, radius=28, fill=(255, 255, 255))
    draw.text((W // 2, H - 320), ar(title), font=title_font, fill=bg, anchor="mm")
    if subtitle:
        draw.text(
            (W // 2, H - 230),
            ar(subtitle),
            font=sub_font,
            fill=(70, 80, 100),
            anchor="mm",
        )
    draw.text(
        (W // 2, H - 130),
        f"{index}/{total}",
        font=small_font,
        fill=(140, 150, 165),
        anchor="mm",
    )
    return img


def write_music_bed(path: Path, duration_sec: float) -> None:
    """Soft ambient bed via ffmpeg (fast)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    # Dual sine pad + light pulse, no vocals.
    dur = max(1.0, duration_sec)
    af = (
        f"sine=frequency=110:duration={dur},"
        f"volume=0.12[a];"
        f"sine=frequency=165:duration={dur},"
        f"volume=0.08[b];"
        f"sine=frequency=220:duration={dur},"
        f"volume=0.05[c];"
        f"[a][b][c]amix=inputs=3:duration=longest,"
        f"afade=t=in:st=0:d=1.5,"
        f"afade=t=out:st={max(0.1, dur - 2)}:d=2"
    )
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"anullsrc=r=44100:cl=stereo",
        "-t",
        str(dur),
        "-filter_complex",
        af,
        "-c:a",
        "pcm_s16le",
        str(path),
    ]
    # Simpler reliable ambient:
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "lavfi",
        "-i",
        f"sine=frequency=110:sample_rate=44100:duration={dur}",
        "-f",
        "lavfi",
        "-i",
        f"sine=frequency=165:sample_rate=44100:duration={dur}",
        "-filter_complex",
        (
            "[0:a]volume=0.11[a0];[1:a]volume=0.07[a1];"
            "[a0][a1]amix=inputs=2:duration=longest,"
            f"afade=t=in:st=0:d=1.2,afade=t=out:st={max(0.1, dur - 2)}:d=2"
        ),
        "-ac",
        "2",
        str(path),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> None:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    total = len(SHOTS)
    paths: list[tuple[Path, float]] = []
    for i, (dur, title, subtitle, section) in enumerate(SHOTS, start=1):
        p = FRAMES_DIR / f"shot_{i:02d}.png"
        if not p.exists():
            img = render_slide(title, subtitle, section, i, total)
            img.save(p, "PNG")
            print(f"frame {i}/{total}: {title}", flush=True)
        else:
            print(f"reuse {i}/{total}: {title}", flush=True)
        paths.append((p, dur))

    total_dur = sum(d for _, d in paths)
    print(f"music {total_dur:.1f}s…", flush=True)
    write_music_bed(AUDIO_PATH, total_dur + 0.5)

    lines = []
    for p, dur in paths:
        lines.append(f"file '{p.resolve().as_posix()}'")
        lines.append(f"duration {dur}")
    lines.append(f"file '{paths[-1][0].resolve().as_posix()}'")
    CONCAT_PATH.write_text("\n".join(lines), encoding="utf-8")

    VIDEO_PATH.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(CONCAT_PATH),
        "-i",
        str(AUDIO_PATH),
        "-vf",
        f"fps={FPS},format=yuv420p",
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "22",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-shortest",
        "-movflags",
        "+faststart",
        str(VIDEO_PATH),
    ]
    print("encoding…", flush=True)
    subprocess.run(cmd, check=True)
    print(f"DONE: {VIDEO_PATH}", flush=True)
    print(f"duration ≈ {total_dur:.0f}s", flush=True)


if __name__ == "__main__":
    main()
