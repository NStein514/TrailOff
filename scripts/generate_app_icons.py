import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/trailoff-icon.png"


def export_icon(destination, size, maskable=False):
    destination.parent.mkdir(parents=True, exist_ok=True)
    content_size = round(size * 0.8) if maskable else size
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", str(content_size),
         str(content_size), str(SOURCE), "--out", str(destination)],
        check=True, capture_output=True,
    )
    if maskable:
        subprocess.run(
            ["sips", "--padToHeightWidth", str(size), str(size),
             "--padColor", "101B2D", str(destination)],
            check=True, capture_output=True,
        )


def main():
    if not shutil.which("sips"):
        raise SystemExit("This icon exporter requires macOS sips.")
    catalogue = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    images = json.loads((catalogue / "Contents.json").read_text())["images"]
    outputs = {}
    for entry in images:
        size = round(float(entry["size"].split("x")[0]) *
                     float(entry["scale"].removesuffix("x")))
        outputs[catalogue / entry["filename"]] = (size, False)
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        outputs[ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"] = (size, False)
    for size in (192, 512):
        outputs[ROOT / f"web/icons/Icon-{size}.png"] = (size, False)
        outputs[ROOT / f"web/icons/Icon-maskable-{size}.png"] = (size, True)
    outputs[ROOT / "web/favicon.png"] = (32, False)
    with tempfile.TemporaryDirectory() as directory:
        cache = {}
        for destination, settings in outputs.items():
            if settings not in cache:
                cached = Path(directory) / f"{settings[0]}-{settings[1]}.png"
                export_icon(cached, *settings)
                cache[settings] = cached
            shutil.copyfile(cache[settings], destination)
    print(f"Exported {len(outputs)} app icons from {SOURCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
