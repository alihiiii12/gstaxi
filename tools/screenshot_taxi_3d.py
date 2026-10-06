"""Screenshot textured 3D taxi views via model-viewer + Playwright."""
import asyncio
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from playwright.async_api import async_playwright

root = Path(r'c:\Users\hp\StudioProjects\syriataxi\assets\images\markers')
html = root / '_viewer.html'


def postprocess(png_bytes: bytes, out: Path):
    img = Image.open(__import__('io').BytesIO(png_bytes)).convert('RGBA')
    arr = np.array(img)
    rgb = arr[..., :3].astype(np.int16)
    # black studio bg -> transparent
    mask = (rgb[..., 0] < 22) & (rgb[..., 1] < 22) & (rgb[..., 2] < 22)
    arr[mask, 3] = 0
    img = Image.fromarray(arr, 'RGBA')
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    side = int(max(w, h) * 1.30)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    s_arr = np.array(img)
    s_arr[..., :3] = 0
    s_arr[..., 3] = (s_arr[..., 3] * 0.28).astype(np.uint8)
    shadow = Image.fromarray(s_arr, 'RGBA').filter(ImageFilter.GaussianBlur(5))
    ox, oy = (side - w) // 2, (side - h) // 2
    canvas.paste(shadow, (ox + 2, oy + 6), shadow)
    canvas.paste(img, (ox, oy), img)
    canvas = canvas.resize((256, 256), Image.Resampling.LANCZOS)
    canvas.save(out, 'PNG')
    print('saved', out)


async def main():
    views = {
        # front 3/4 — app start
        'taxi_3d_idle.png': '40deg 68deg 110%',
        # rear — trip start (behind car)
        'taxi_3d_rear.png': '180deg 72deg 110%',
        # rear 3/4 alternate
        'taxi_3d_rear_34.png': '155deg 70deg 110%',
    }

    url = 'http://127.0.0.1:8765/_viewer.html'
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={'width': 512, 'height': 512})
        page.on('console', lambda msg: print('console', msg.type, msg.text))
        page.on('pageerror', lambda err: print('pageerror', err))
        await page.goto(url, wait_until='domcontentloaded', timeout=120000)
        try:
            await page.wait_for_function('window.__ready === true', timeout=180000)
        except Exception as e:
            ready = await page.evaluate('window.__ready')
            print('ready?', ready, e)
            # still try screenshot of whatever is visible
        await asyncio.sleep(2.0)

        for name, orbit in views.items():
            await page.evaluate('(o) => window.setOrbit(o)', orbit)
            await asyncio.sleep(1.5)
            png = await page.locator('model-viewer').screenshot(omit_background=True)
            postprocess(png, root / name)

        await browser.close()
    print('done')


if __name__ == '__main__':
    asyncio.run(main())
