#!/usr/bin/env python3
"""Post-flutter-create Android branding step.

Run AFTER `flutter create --platforms=android` in CI (and locally). It:
  1. Overwrites the default launcher icons (mipmap-*dpi/ic_launcher.png) with
     our weapon icon at the correct densities.
  2. Overwrites the adaptive-icon foreground for Android 9+ (mipmap-anydpi-v26).
  3. Sets the app label (launcher name) in AndroidManifest.xml.
  4. Renames the output APK artifact-friendly name is handled by the workflow.

Requires Pillow (available on the GitHub Actions ubuntu runner after
`pip install pillow`).
"""
import os
import re
import sys
import shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_SRC = os.path.join(ROOT, "assets", "icon", "app_icon.png")
ANDROID_RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
MANIFEST = os.path.join(ROOT, "android", "app", "src", "main", "AndroidManifest.xml")

# Standard Android launcher icon densities (px for a 108dp icon).
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

APP_LABEL = "帽子计算器"


def set_icons():
    if not os.path.exists(ICON_SRC):
        print(f"!! icon source missing: {ICON_SRC}")
        return False
    img = Image.open(ICON_SRC).convert("RGBA")
    ok = True
    for folder, px in DENSITIES.items():
        target = os.path.join(ANDROID_RES, folder, "ic_launcher.png")
        target_dir = os.path.dirname(target)
        os.makedirs(target_dir, exist_ok=True)
        resized = img.resize((px, px), Image.LANCZOS)
        resized.save(target, "PNG")
        print(f"  wrote {target} ({px}px)")
        ok = ok and os.path.exists(target)
    return ok


def set_adaptive_foreground():
    """Android 9+ (API 26+) uses adaptive icons via mipmap-anydpi-v26/ic_launcher.xml.
    flutter create generates that xml referencing a background color + a
    foreground drawable. Our launcher icon is a complete rounded-square design
    (own dark background + gold rifle artwork), so we set the adaptive
    *background* to our full bitmap and keep a transparent foreground. Under
    the adaptive mask Android still shows our full design (slightly cropped at
    the very corners, which is expected for adaptive icons)."""
    anydpi = os.path.join(ANDROID_RES, "mipmap-anydpi-v26")
    if not os.path.isdir(anydpi):
        return True  # no adaptive dir (older template) -> nothing to do
    xml_path = os.path.join(anydpi, "ic_launcher.xml")
    if not os.path.exists(xml_path):
        return True
    with open(xml_path, "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@mipmap/ic_launcher"/>\n'
            '    <foreground android:drawable="@android:color/transparent"/>\n'
            '</adaptive-icon>\n'
        )
    print("  adaptive ic_launcher.xml -> background=our icon, transparent fg")
    return True


def set_label():
    if not os.path.exists(MANIFEST):
        print(f"!! manifest missing: {MANIFEST}")
        return False
    with open(MANIFEST, "r", encoding="utf-8") as f:
        xml = f.read()
    # Replace android:label="..." with our app name.
    new_xml = re.sub(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        xml,
        count=1,
    )
    if new_xml == xml:
        print("!! android:label not found in manifest")
        return False
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(new_xml)
    print(f"  manifest label -> {APP_LABEL}")
    return True



def inject_location_permissions():
    """geolocator needs location permissions in the (CI-regenerated) manifest."""
    if not os.path.exists(MANIFEST):
        print(f"!! manifest missing: {MANIFEST}")
        return False
    with open(MANIFEST, "r", encoding="utf-8") as f:
        xml = f.read()
    if "ACCESS_FINE_LOCATION" in xml:
        print("  location permissions already present")
        return True
    perms = (
        '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
        '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    )
    new_xml, n = re.subn(r"([ \t]*<application)", perms + r"\1", xml, count=1)
    if n != 1:
        print("!! <application> tag not found in manifest")
        return False
    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(new_xml)
    print("  manifest + ACCESS_COARSE/FINE_LOCATION")
    return True


def main():
    if not os.path.exists(ANDROID_RES):
        print("!! android res dir not found; run after flutter create")
        return 1
    icons_ok = set_icons()
    adaptive_ok = set_adaptive_foreground()
    label_ok = set_label()
    perms_ok = inject_location_permissions()
    print(f"  icons={icons_ok} adaptive={adaptive_ok} label={label_ok} perms={perms_ok}")
    return 0 if (icons_ok and label_ok and perms_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
