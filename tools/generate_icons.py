#!/usr/bin/env python3
"""Generate Android launcher icons from the base64 logo in Dart code.

Why this exists: the GitHub connector (MCP push_files) only pushes UTF-8
text files, so the binary launcher PNGs (mipmap-*/ic_launcher.png) and the
logo WebP cannot be pushed to the repo. The logo lives as base64 in
lib/config/logo_data.dart; this script (run by CI before the build) decodes
it and writes the 5 mipmap PNGs. It also creates the mipmap directories,
which do not exist in the repo (git does not track empty dirs).

Run from the repo root:  python3 tools/generate_icons.py
Requires: Pillow (CI installs it: python3 -m pip install pillow).
"""
import base64
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGO_DART = ROOT / "lib" / "config" / "logo_data.dart"

# (mipmap dir, icon size px) — matches Android launcher density buckets.
SIZES = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]


def load_logo_bytes() -> bytes:
    text = LOGO_DART.read_text(encoding="utf-8")
    parts = re.findall(r"'([A-Za-z0-9+/=]+)'", text)
    if not parts:
        raise SystemExit(f"no base64 string found in {LOGO_DART}")
    return base64.b64decode("".join(parts))


def main() -> int:
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required: python3 -m pip install pillow", file=sys.stderr)
        return 1
    import io

    logo = Image.open(io.BytesIO(load_logo_bytes()))
    print(f"logo: {logo.size} {logo.mode} {logo.format}")
    if logo.size[0] != logo.size[1]:
        # Center-crop to square so the icon is not stretched.
        side = min(logo.size)
        left = (logo.size[0] - side) // 2
        top = (logo.size[1] - side) // 2
        logo = logo.crop((left, top, left + side, top + side))
        print(f"center-cropped to square: {logo.size}")
    logo = logo.convert("RGB")

    res_dir = ROOT / "android" / "app" / "src" / "main" / "res"
    for dirname, size in SIZES:
        out_dir = res_dir / dirname
        out_dir.mkdir(parents=True, exist_ok=True)
        out = out_dir / "ic_launcher.png"
        logo.resize((size, size), Image.LANCZOS).save(out, format="PNG")
        print(f"wrote {out} ({size}x{size}, {out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
