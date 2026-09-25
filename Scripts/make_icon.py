#!/usr/bin/env python3
"""Handsout 图标：圆角渐变底 + 两只举起的手（🙌）。

纯标准库实现：形状用 SDF（圆角矩形 / 胶囊）描述，支持旋转，
2x 超采样后降采样，再由 sips/iconutil 生成 icns。

用法: python3 Scripts/make_icon.py [--preview /tmp/preview.png]
"""
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

SIZE = 1024
SS = 2
OUT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "AppIcon.icns")
)

BG_TOP = (0x3B, 0x74, 0xF8)
BG_BOTTOM = (0x17, 0x24, 0x52)
HAND = (0xFF, 0xF3, 0xE0)


# ---------- 几何工具 ----------

def rot(x, y, deg, cx, cy):
    a = math.radians(deg)
    dx, dy = x - cx, y - cy
    return (cx + dx * math.cos(a) - dy * math.sin(a),
            cy + dx * math.sin(a) + dy * math.cos(a))


def dist_to_seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def inside(shape, x, y):
    """坐标均为归一化 0..1"""
    if shape[0] == "rrect":
        _, x0, y0, w, h, r = shape
        dx = max(x0 + r - x, 0.0, x - (x0 + w - r))
        dy = max(y0 + r - y, 0.0, y - (y0 + h - r))
        return dx * dx + dy * dy <= r * r
    _, ax, ay, bx, by, r = shape
    return dist_to_seg(x, y, ax, ay, bx, by) <= r


def shape_corners(shape):
    if shape[0] == "rrect":
        _, x0, y0, w, h, _r = shape
        return [(x0, y0), (x0 + w, y0), (x0, y0 + h), (x0 + w, y0 + h)]
    _, ax, ay, bx, by, r = shape
    return [(ax - r, ay - r), (ax + r, ay + r), (bx - r, by - r), (bx + r, by + r)]


def paint(buf, s, shape, deg, cx, cy, color):
    """把形状（可绕 (cx,cy) 旋转 deg 度）画进缓冲区，只扫描旋转后的包围盒。"""
    pts = [rot(p[0], p[1], deg, cx, cy) for p in shape_corners(shape)]
    xa = max(0, int(math.floor(min(p[0] for p in pts) * s)))
    xb = min(s - 1, int(math.ceil(max(p[0] for p in pts) * s)))
    ya = max(0, int(math.floor(min(p[1] for p in pts) * s)))
    yb = min(s - 1, int(math.ceil(max(p[1] for p in pts) * s)))
    rgba = bytes((color[0], color[1], color[2], 255))
    for y in range(ya, yb + 1):
        base = y * s * 4
        py = (y + 0.5) / s
        for x in range(xa, xb + 1):
            lx, ly = rot((x + 0.5) / s, py, -deg, cx, cy)
            if inside(shape, lx, ly):
                i = base + x * 4
                buf[i:i + 4] = rgba


def row_span(y, x0, y0, w, h, r):
    if y < y0 or y > y0 + h:
        return None
    if y < y0 + r:
        dy = y0 + r - y
        dx = math.sqrt(max(0.0, r * r - dy * dy))
        return (x0 + r - dx, x0 + w - r + dx)
    if y > y0 + h - r:
        dy = y - (y0 + h - r)
        dx = math.sqrt(max(0.0, r * r - dy * dy))
        return (x0 + r - dx, x0 + w - r + dx)
    return (x0, x0 + w)


def fill_bg(buf, s, geom, top, bottom):
    """背景圆角矩形 + 纵向渐变，按行整段填充。"""
    x0, y0, w, h, r = geom
    for y in range(s):
        span = row_span((y + 0.5) / s, *geom)
        if span is None:
            continue
        t = y / (s - 1)
        color = bytes((
            int(top[0] + (bottom[0] - top[0]) * t),
            int(top[1] + (bottom[1] - top[1]) * t),
            int(top[2] + (bottom[2] - top[2]) * t),
            255,
        ))
        xa = max(0, int(math.ceil(span[0] * s)))
        xb = min(s - 1, int(math.floor(span[1] * s)))
        if xb < xa:
            continue
        start = (y * s + xa) * 4
        buf[start:start + (xb - xa + 1) * 4] = color * (xb - xa + 1)


# ---------- 手的形状 ----------

def hand_shapes(mirror: bool, tilt: float):
    """返回一只举起的手（掌心朝前，手指朝上），mirror=True 时水平镜像。"""
    def m(x):
        return 1.0 - x if mirror else x

    shapes = []
    # 手掌（rrect 的 x0 是左边缘，镜像时必须翻的是两条边）
    px0, pw = 0.545, 0.245
    shapes.append(("rrect", m(px0 + pw) if mirror else px0, 0.505, pw, 0.28, 0.05))
    # 四指（中指最长，小指最短），胶囊端点即指尖，自然圆头
    for fx, tip in ((0.575, 0.345), (0.637, 0.305), (0.699, 0.325), (0.757, 0.380)):
        shapes.append(("capsule", m(fx), 0.545, m(fx), tip, 0.025))
    # 拇指：短、从手掌外缘朝斜上方张开
    shapes.append(("capsule", m(0.768), 0.645, m(0.836), 0.578, 0.025))
    return [(s, tilt if not mirror else -tilt, 0.5) for s in shapes]


def render():
    s = SIZE * SS
    buf = bytearray(s * s * 4)

    # 背景
    fill_bg(buf, s, (0.055, 0.055, 0.89, 0.89, 0.235), BG_TOP, BG_BOTTOM)

    # 两只手：各自绕手腕处向外倾斜
    for mirror in (False, True):
        pivot_x = 0.345 if mirror else 0.665
        for shape, tilt, _ in hand_shapes(mirror, 10.0):
            paint(buf, s, shape, tilt, pivot_x, 0.76, HAND)

    # 降采样 SS x SS -> 1
    out = bytearray(SIZE * SIZE * 4)
    k = SS * SS
    for y in range(SIZE):
        base_in = y * SS * s * 4
        base_out = y * SIZE * 4
        for x in range(SIZE):
            r = g = b = a = 0
            for dy in range(SS):
                off = base_in + dy * s * 4 + x * SS * 4
                for dx in range(SS):
                    j = off + dx * 4
                    r += buf[j]
                    g += buf[j + 1]
                    b += buf[j + 2]
                    a += buf[j + 3]
            o = base_out + x * 4
            out[o] = r // k
            out[o + 1] = g // k
            out[o + 2] = b // k
            out[o + 3] = a // k
    return bytes(out)


def write_png(path, rgba, size):
    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]

    rgba = render()
    png = preview or "/tmp/handsout_icon.png"
    write_png(png, rgba, SIZE)
    if preview:
        print(f"预览: {png}")
        return 0

    tmp = tempfile.mkdtemp()
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for side in (16, 32, 128, 256, 512):
        subprocess.run(["sips", "-z", str(side), str(side), png, "--out",
                        os.path.join(iconset, f"icon_{side}x{side}.png")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["sips", "-z", str(side * 2), str(side * 2), png, "--out",
                        os.path.join(iconset, f"icon_{side}x{side}@2x.png")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.copy(png, os.path.join(iconset, "icon_512x512@2x.png"))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
    shutil.rmtree(tmp)
    print(f"图标已生成: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
