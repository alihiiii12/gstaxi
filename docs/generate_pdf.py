# -*- coding: utf-8 -*-
"""Generate Syria Taxi app guide PDF from HTML."""
import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(ROOT, "syriataxi-app-guide.html")
PDF_EN = os.path.join(ROOT, "SyriaTaxi-App-Guide.pdf")
PDF_AR = os.path.join(ROOT, "الية-عمل-تطبيق-سوريا-تاكسي.pdf")

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

browser = CHROME if os.path.isfile(CHROME) else EDGE
uri = "file:///" + HTML.replace("\\", "/")

subprocess.run(
    [
        browser,
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={PDF_EN}",
        uri,
    ],
    check=True,
    cwd=ROOT,
)

shutil.copy2(PDF_EN, PDF_AR)
print(f"Created: {PDF_EN}")
print(f"Created: {PDF_AR}")
