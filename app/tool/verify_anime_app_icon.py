#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

app_root = Path(__file__).resolve().parents[1]
res = app_root / 'android/app/src/main/res'
master = app_root / 'assets/icons/app_icon_anime_faceswap_master.png'
expected = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}
checks = []
checks.append(('master icon exists', master.exists()))
if master.exists():
    with Image.open(master) as img:
        checks.append(('master icon is square and large', img.size[0] == img.size[1] and img.size[0] >= 512))
for folder, size in expected.items():
    path = res / folder / 'ic_launcher.png'
    ok = path.exists()
    if ok:
        with Image.open(path) as img:
            ok = img.size == (size, size) and img.mode == 'RGBA'
    checks.append((f'{folder}/ic_launcher.png is {size}x{size} RGBA', ok))
script = (app_root / 'tool/generate_anime_app_icon.py').read_text()
checks.extend([
    ('icon generator preserves anime style tokens', 'PINK' in script and 'CYAN' in script and 'draw_face' in script),
    ('icon generator expresses swap theme', 'arc' in script and 'draw_face' in script and 'swap' in script.lower()),
])
failed = [name for name, ok in checks if not ok]
if failed:
    print('FAILED checks:')
    for name in failed:
        print(f'- {name}')
    raise SystemExit(1)
print('All anime app icon checks passed.')
