#!/usr/bin/env python3
"""Generate GS Taxi website QR with centered company logo."""

from pathlib import Path

import qrcode
from PIL import Image, ImageDraw
from qrcode.constants import ERROR_CORRECT_H

ROOT = Path(__file__).resolve().parents[1]
# الموقع الرسمي على Hostinger (index.html يتجنب 403 على /site/)
URL = "https://gstaxi.online/site/index.html"
LOGO = ROOT / "website" / "images" / "logo.png"
OUT = ROOT / "website" / "images" / "qr-site-logo.png"


def main() -> None:
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_H,
        box_size=12,
        border=2,
    )
    qr.add_data(URL)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#0e1116", back_color="white").convert("RGBA")

    logo = Image.open(LOGO).convert("RGBA")
    qr_w, qr_h = img.size
    logo_size = int(min(qr_w, qr_h) * 0.28)
    logo = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)

    pad = int(logo_size * 0.12)
    bg_size = logo_size + pad * 2
    bg = Image.new("RGBA", (bg_size, bg_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(bg)
    radius = int(bg_size * 0.22)
    draw.rounded_rectangle(
        (0, 0, bg_size - 1, bg_size - 1),
        radius=radius,
        fill=(255, 255, 255, 255),
    )
    draw.rounded_rectangle(
        (2, 2, bg_size - 3, bg_size - 3),
        radius=radius,
        outline=(230, 180, 34, 255),
        width=4,
    )
    bg.paste(logo, (pad, pad), logo)

    pos = ((qr_w - bg_size) // 2, (qr_h - bg_size) // 2)
    img.paste(bg, pos, bg)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "PNG")
    print(f"saved {OUT} size={img.size} url={URL}")


if __name__ == "__main__":
    main()
