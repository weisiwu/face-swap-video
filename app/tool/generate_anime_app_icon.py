#!/usr/bin/env python3
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

APP_ROOT = Path(__file__).resolve().parents[1]
RES = APP_ROOT / 'android/app/src/main/res'
ASSET_DIR = APP_ROOT / 'assets/icons'
ASSET_DIR.mkdir(parents=True, exist_ok=True)

SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

PINK = (255, 122, 205, 255)
CYAN = (114, 242, 255, 255)
VIOLET = (139, 92, 246, 255)
DARK = (5, 5, 16, 255)
FACE = (255, 246, 248, 255)
INK = (23, 17, 31, 255)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def rgba(c, a):
    return (c[0], c[1], c[2], int(a))


def rounded_rectangle(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_gradient_bg(size):
    img = Image.new('RGBA', (size, size), DARK)
    pix = img.load()
    for y in range(size):
        for x in range(size):
            nx = x / (size - 1)
            ny = y / (size - 1)
            # diagonal dark purple base
            t = (nx + ny) / 2
            base = (
                lerp(5, 24, t),
                lerp(5, 14, t),
                lerp(16, 38, t),
                255,
            )
            # soft pink/cyan auras
            dp = math.hypot(nx - 0.22, ny - 0.22)
            dc = math.hypot(nx - 0.82, ny - 0.28)
            pink_strength = max(0, 1 - dp / 0.62) ** 2
            cyan_strength = max(0, 1 - dc / 0.55) ** 2
            r = min(255, int(base[0] + PINK[0] * pink_strength * 0.24 + CYAN[0] * cyan_strength * 0.14))
            g = min(255, int(base[1] + PINK[1] * pink_strength * 0.16 + CYAN[1] * cyan_strength * 0.22))
            b = min(255, int(base[2] + PINK[2] * pink_strength * 0.20 + CYAN[2] * cyan_strength * 0.24))
            pix[x, y] = (r, g, b, 255)
    return img


def draw_face(draw, cx, cy, r, hair_color, accent):
    # face
    face_box = [cx - r * 0.66, cy - r * 0.62, cx + r * 0.66, cy + r * 0.78]
    rounded_rectangle(draw, face_box, int(r * 0.55), FACE, accent, max(2, int(r * 0.045)))

    # hair cap
    hair = [
        (cx - r * 0.68, cy - r * 0.18),
        (cx - r * 0.48, cy - r * 0.78),
        (cx + r * 0.08, cy - r * 0.86),
        (cx + r * 0.58, cy - r * 0.64),
        (cx + r * 0.68, cy - r * 0.12),
        (cx + r * 0.26, cy - r * 0.30),
        (cx - r * 0.10, cy - r * 0.18),
        (cx - r * 0.44, cy - r * 0.02),
    ]
    draw.polygon(hair, fill=hair_color)

    # blush
    draw.ellipse([cx - r * 0.55, cy + r * 0.22, cx - r * 0.35, cy + r * 0.32], fill=(255, 122, 205, 70))
    draw.ellipse([cx + r * 0.35, cy + r * 0.22, cx + r * 0.55, cy + r * 0.32], fill=(255, 122, 205, 70))

    # eyes with highlight
    for ex in (cx - r * 0.28, cx + r * 0.28):
        draw.ellipse([ex - r * 0.075, cy + r * 0.02, ex + r * 0.075, cy + r * 0.30], fill=INK)
        draw.ellipse([ex + r * 0.018, cy + r * 0.055, ex + r * 0.055, cy + r * 0.09], fill=(255, 255, 255, 235))

    # tiny smile
    draw.arc([cx - r * 0.18, cy + r * 0.34, cx + r * 0.18, cy + r * 0.52], 0, 180, fill=(23, 17, 31, 175), width=max(1, int(r * 0.035)))


def create_icon(size):
    scale = size / 192
    img = draw_gradient_bg(size)

    # work on overlay for glow
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([size*0.09, size*0.10, size*0.91, size*0.92], outline=rgba(CYAN, 95), width=max(2, int(5*scale)))
    gd.arc([size*0.16, size*0.16, size*0.84, size*0.84], 205, 492, fill=rgba(PINK, 160), width=max(2, int(8*scale)))
    gd.arc([size*0.10, size*0.10, size*0.90, size*0.90], -36, 202, fill=rgba(CYAN, 160), width=max(2, int(6*scale)))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(1, int(2*scale))))
    img.alpha_composite(glow)

    draw = ImageDraw.Draw(img)
    # crisp rings
    draw.arc([size*0.16, size*0.16, size*0.84, size*0.84], 205, 492, fill=PINK, width=max(2, int(5*scale)))
    draw.arc([size*0.10, size*0.10, size*0.90, size*0.90], -36, 202, fill=CYAN, width=max(2, int(4*scale)))

    # main merged anime face
    draw_face(draw, size*0.50, size*0.51, size*0.31, PINK, (255,255,255,210))
    # cyan hair shard to imply swapped side
    shard = [
        (size*0.49, size*0.19),
        (size*0.69, size*0.25),
        (size*0.72, size*0.45),
        (size*0.52, size*0.36),
    ]
    draw.polygon(shard, fill=CYAN)

    # center swap bolt / arrows
    arrow_w = max(2, int(size*0.035))
    y = size*0.76
    draw.line([size*0.34, y, size*0.62, y], fill=(255,255,255,230), width=arrow_w)
    draw.polygon([(size*0.62, y), (size*0.55, y-size*0.045), (size*0.55, y+size*0.045)], fill=(255,255,255,230))
    draw.line([size*0.66, y+size*0.055, size*0.38, y+size*0.055], fill=(255,255,255,180), width=max(1, int(arrow_w*0.75)))
    draw.polygon([(size*0.38, y+size*0.055), (size*0.45, y+size*0.012), (size*0.45, y+size*0.098)], fill=(255,255,255,180))

    # small sparkles
    for x, yy, col, rr in [
        (0.26,0.31,CYAN,0.018),(0.76,0.34,PINK,0.016),(0.30,0.72,VIOLET,0.014),(0.72,0.70,CYAN,0.013)
    ]:
        cx, cy, rad = size*x, size*yy, size*rr
        draw.line([cx-rad, cy, cx+rad, cy], fill=col, width=max(1,int(2*scale)))
        draw.line([cx, cy-rad, cx, cy+rad], fill=col, width=max(1,int(2*scale)))

    # rounded mask for modern adaptive-launcher-like shape
    mask = Image.new('L', (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, size-1, size-1], radius=int(size*0.225), fill=255)
    out = Image.new('RGBA', (size, size), (0,0,0,0))
    out.alpha_composite(img)
    out.putalpha(mask)
    return out


def main():
    master = create_icon(1024)
    master_path = ASSET_DIR / 'app_icon_anime_faceswap_master.png'
    master.save(master_path)
    print(master_path)
    for folder, size in SIZES.items():
        out = RES / folder / 'ic_launcher.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        icon = create_icon(size)
        icon.save(out, 'PNG')
        print(f'{out} {size}x{size}')

if __name__ == '__main__':
    main()
