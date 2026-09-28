#!/usr/bin/env python3
"""Post-flutter-create Web branding step (PWA support).

Run AFTER `flutter create --platforms=web` in CI. It:
  1. Generates web/icons/icon-192.png / icon-512.png / favicon.png from
     assets/icon/app_icon.png.
  2. Rewrites web/manifest.json with the Chinese app name, theme colors and
     our icons so the site is installable as a PWA ("add to home screen").
  3. Patches web/index.html: title, description, theme-color and favicon.

Requires Pillow (installed in the deploy workflow before this runs).
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SRC = os.path.join(ROOT, "assets", "icon", "app_icon.png")
WEB = os.path.join(ROOT, "web")
ICONS_DIR = os.path.join(WEB, "icons")

APP_NAME = "帽子计算器"
APP_SHORT = "帽子计算器"
DESCRIPTION = "专业3D外弹道计算器：RK4弹道积分、G1/G7阻力模型、全球武器弹药数据库"
THEME_COLOR = "#1B5E20"
BG_COLOR = "#ffffff"


def gen_icons():
    os.makedirs(ICONS_DIR, exist_ok=True)
    img = Image.open(ICON_SRC).convert("RGBA")
    for px, name in [(192, "icon-192.png"), (512, "icon-512.png"),
                     (32, "favicon.png")]:
        img.resize((px, px), Image.LANCZOS).save(
            os.path.join(ICONS_DIR, name), "PNG")
        print(f"  wrote web/icons/{name} ({px}px)")


def patch_manifest():
    path = os.path.join(WEB, "manifest.json")
    manifest = {
        "name": APP_NAME,
        "short_name": APP_SHORT,
        "start_url": ".",
        "display": "standalone",
        "background_color": BG_COLOR,
        "theme_color": THEME_COLOR,
        "description": DESCRIPTION,
        "orientation": "portrait-primary",
        "prefer_related_applications": False,
        "icons": [
            {"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png",
             "purpose": "maskable"},
        ],
    }
    with open(path, "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("  rewrote web/manifest.json")


def patch_index():
    path = os.path.join(WEB, "index.html")
    with open(path) as f:
        html = f.read()
    html = _replace_once(html, r"<title>.*?</title>",
                         f"<title>{APP_NAME} - 弹道计算</title>")
    html = _replace_once(
        html, r'<meta name="description" content="[^"]*">',
        f'<meta name="description" content="{DESCRIPTION}">')
    html = _replace_once(
        html, r'<meta name="theme-color" content="[^"]*">',
        f'<meta name="theme-color" content="{THEME_COLOR}">')
    html = _replace_once(
        html, r'<link rel="icon"[^>]*>',
        '<link rel="icon" type="image/png" href="icons/favicon.png">')
    # apple-touch-icon for iOS home-screen installs; add before </head>
    if 'rel="apple-touch-icon"' not in html:
        html = html.replace(
            "</head>",
            '  <link rel="apple-touch-icon" href="icons/icon-192.png">\n'
            "  </head>")
    with open(path, "w") as f:
        f.write(html)
    print("  patched web/index.html")


def _replace_once(html, pattern, repl):
    import re
    out, n = re.subn(pattern, repl, html, count=1)
    if n != 1:
        print(f"  !! pattern not found, skipped: {pattern}")
    return out


if __name__ == "__main__":
    if not os.path.exists(ICON_SRC):
        raise SystemExit(f"icon source missing: {ICON_SRC}")
    gen_icons()
    patch_manifest()
    patch_index()
    print("web branding done")
