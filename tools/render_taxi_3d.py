"""Render textured rear taxi marker from 3D AI Studio GLB (software, no OpenGL)."""
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFilter

root = Path(r'c:\Users\hp\StudioProjects\syriataxi\assets\images\markers')
glb_path = root / 'taxi_3d.glb'


def look_at_matrix(eye, target, up=np.array([0.0, 0.0, 1.0])):
    eye = np.asarray(eye, dtype=float)
    target = np.asarray(target, dtype=float)
    f = target - eye
    f /= np.linalg.norm(f) + 1e-9
    up = up / (np.linalg.norm(up) + 1e-9)
    s = np.cross(f, up)
    if np.linalg.norm(s) < 1e-6:
        up = np.array([0.0, 1.0, 0.0])
        s = np.cross(f, up)
    s /= np.linalg.norm(s) + 1e-9
    u = np.cross(s, f)
    return np.stack([s, u, -f], axis=0), eye


def process_studio_thumb():
    src = root / 'taxi_3d_thumb.png'
    img = Image.open(src).convert('RGBA')
    arr = np.array(img)
    rgb = arr[..., :3].astype(np.int16)
    mask = (rgb[..., 0] < 28) & (rgb[..., 1] < 28) & (rgb[..., 2] < 28)
    arr[mask, 3] = 0
    img = Image.fromarray(arr, 'RGBA')
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    w, h = img.size
    side = int(max(w, h) * 1.32)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    s_arr = np.array(img)
    s_arr[..., :3] = 0
    s_arr[..., 3] = (s_arr[..., 3] * 0.30).astype(np.uint8)
    shadow = Image.fromarray(s_arr, 'RGBA').filter(ImageFilter.GaussianBlur(5))
    ox, oy = (side - w) // 2, (side - h) // 2
    canvas.paste(shadow, (ox + 3, oy + 7), shadow)
    canvas.paste(img, (ox, oy), img)
    canvas = canvas.resize((256, 256), Image.Resampling.LANCZOS)
    out = root / 'taxi_3d_idle.png'
    canvas.save(out, 'PNG')
    print('idle', out)


def bake_vertex_colors(mesh: trimesh.Trimesh) -> np.ndarray:
    uv = np.asarray(mesh.visual.uv, dtype=np.float64)
    tex = np.asarray(mesh.visual.material.baseColorTexture.convert('RGBA'))
    h, w = tex.shape[:2]
    u = np.mod(uv[:, 0], 1.0)
    v = np.mod(uv[:, 1], 1.0)
    xs = np.clip((u * (w - 1)).astype(np.int32), 0, w - 1)
    ys = np.clip(((1.0 - v) * (h - 1)).astype(np.int32), 0, h - 1)
    return tex[ys, xs]


def render_textured(mesh, vcol, eye, out_path, size=720, face_stride=18, pad=1.28):
    verts = np.asarray(mesh.vertices, dtype=np.float64)
    faces = np.asarray(mesh.faces, dtype=np.int32)
    center = verts.mean(axis=0)
    R, eye = look_at_matrix(eye, center)
    cam = (verts - eye) @ R.T
    z = np.clip(-cam[:, 2], 1e-3, None)
    x = 1.35 * cam[:, 0] / z
    y = 1.35 * cam[:, 1] / z

    # Subsample faces for speed, keep depth order
    idx = np.arange(0, len(faces), face_stride, dtype=np.int32)
    faces_s = faces[idx]
    depth = z[faces_s].mean(axis=1)
    order = np.argsort(depth)[::-1]
    faces_s = faces_s[order]

    # Face colors from vertex colors
    fc = vcol[faces_s].mean(axis=1).astype(np.uint8)

    xs = x[faces_s]
    ys = y[faces_s]
    xmin, xmax = float(xs.min()), float(xs.max())
    ymin, ymax = float(ys.min()), float(ys.max())
    span = max(xmax - xmin, ymax - ymin) * pad
    cx, cy = (xmin + xmax) / 2, (ymin + ymax) / 2
    scale = (size * 0.90) / span

    def pix(i):
        return (
            (x[i] - cx) * scale + size / 2,
            size / 2 - (y[i] - cy) * scale,
        )

    base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    for fi in range(0, len(faces_s), max(1, len(faces_s) // 600)):
        tri = faces_s[fi]
        pts = [pix(int(i)) for i in tri]
        sdraw.polygon([(p[0] + 5, p[1] + 10) for p in pts], fill=(0, 0, 0, 45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(8))
    img = Image.alpha_composite(base, shadow)
    draw = ImageDraw.Draw(img)

    cam_f = cam[faces_s]
    for fi, tri in enumerate(faces_s):
        pts = [pix(int(i)) for i in tri]
        c = fc[fi]
        v0, v1, v2 = cam_f[fi]
        n = np.cross(v1 - v0, v2 - v0)
        nn = np.linalg.norm(n)
        shade = 1.0
        if nn > 1e-9:
            n = n / nn
            shade = 0.55 + 0.45 * max(0.0, float(np.dot(n, np.array([0.2, 0.3, 0.9]))))
        fill = (
            min(255, int(c[0] * shade)),
            min(255, int(c[1] * shade)),
            min(255, int(c[2] * shade)),
            int(c[3]),
        )
        draw.polygon(pts, fill=fill)

    img = img.resize((256, 256), Image.Resampling.LANCZOS)
    img.save(out_path, 'PNG')
    print('saved', out_path, 'faces_drawn', len(faces_s))


def main():
    process_studio_thumb()
    print('loading glb...')
    scene = trimesh.load(str(glb_path), force='scene')
    mesh = list(scene.geometry.values())[0]
    print('faces', len(mesh.faces), 'baking vertex colors...')
    vcol = bake_vertex_colors(mesh)
    print('vcol', vcol.shape, vcol.mean(axis=0))

    extents = mesh.bounds[1] - mesh.bounds[0]
    long_axis = int(np.argmax(extents))
    direction = np.eye(3)[long_axis]
    center = mesh.centroid
    dist = float(np.linalg.norm(extents)) * 1.15

    # Rear candidates along long axis
    candidates = {
        'taxi_3d_rear.png': center - direction * dist + np.array([0, 0, dist * 0.22]),
        'taxi_3d_rear_a.png': center + direction * dist + np.array([0, 0, dist * 0.22]),
        'taxi_3d_rear_34.png': (
            center
            - direction * dist * 0.92
            + np.eye(3)[(long_axis + 1) % 3] * dist * 0.28
            + np.array([0, 0, dist * 0.25])
        ),
    }
    for name, eye in candidates.items():
        render_textured(mesh, vcol, eye, root / name, face_stride=22)

    print('done')


if __name__ == '__main__':
    main()
