from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import sys

root = Path(__file__).parent
build = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build"
iconset = build / "AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)

def make(size: int) -> Image.Image:
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale
    margin = int(s * 0.06)
    draw.rounded_rectangle(
        (margin, margin, s - margin, s - margin),
        radius=int(s * 0.23),
        fill=(242, 133, 74, 255),
    )
    draw.ellipse(
        (int(s * .18), int(s * .18), int(s * .82), int(s * .82)),
        fill=(255, 244, 234, 255),
    )
    draw.rounded_rectangle(
        (int(s * .31), int(s * .27), int(s * .69), int(s * .73)),
        radius=int(s * .045),
        fill=(48, 52, 59, 255),
    )
    draw.rectangle(
        (int(s * .35), int(s * .34), int(s * .65), int(s * .40)),
        fill=(242, 133, 74, 255),
    )
    for y in (.48, .57, .66):
        draw.rounded_rectangle(
            (int(s * .36), int(s * y), int(s * .59), int(s * (y + .035))),
            radius=int(s * .012),
            fill=(255, 244, 234, 255),
        )
    return canvas.resize((size, size), Image.Resampling.LANCZOS)

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
