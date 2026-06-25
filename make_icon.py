from PIL import Image
from pathlib import Path
import sys

root = Path(__file__).parent
build = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build"
iconset = build / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)

source_icon = root / "docs" / "images" / "icon.png"
if not source_icon.exists():
    raise FileNotFoundError(f"Missing source icon: {source_icon}")

source = Image.open(source_icon).convert("RGBA")

def make(size: int) -> Image.Image:
    return source.resize((size, size), Image.Resampling.LANCZOS)

specs = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for size, name in specs:
    make(size).save(iconset / name)
