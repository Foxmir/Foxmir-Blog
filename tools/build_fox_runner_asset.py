from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


def find_components(img: Image.Image, alpha_threshold: int = 16) -> list[tuple[int, int, int, int]]:
    alpha = img.getchannel("A")
    width, height = img.size
    occupied_columns: list[bool] = []

    for x in range(width):
      column = alpha.crop((x, 0, x + 1, height))
      occupied_columns.append(column.getbbox() is not None)

    ranges: list[tuple[int, int]] = []
    start: int | None = None
    gap = 0
    max_gap = max(8, width // 180)

    for x, occupied in enumerate(occupied_columns):
        if occupied:
            if start is None:
                start = x
            gap = 0
            continue

        if start is not None:
            gap += 1
            if gap > max_gap:
                ranges.append((start, x - gap + 1))
                start = None
                gap = 0

    if start is not None:
        ranges.append((start, width))

    boxes: list[tuple[int, int, int, int]] = []
    for left, right in ranges:
        crop_alpha = alpha.crop((left, 0, right, height))
        bbox = crop_alpha.getbbox()
        if not bbox:
            continue
        l2, top, r2, bottom = bbox
        box = (left + l2, top, left + r2, bottom)
        if box[2] - box[0] > 20 and box[3] - box[1] > 20:
            boxes.append(box)

    return boxes


def trim_transparent(img: Image.Image) -> Image.Image:
    bbox = img.getchannel("A").getbbox()
    if not bbox:
        return img
    return img.crop(bbox)


def composite_debug_sheet(frames: list[Image.Image], out: Path) -> None:
    pad = 18
    label_h = 24
    cell_w = max(frame.width for frame in frames)
    cell_h = max(frame.height for frame in frames)
    sheet = Image.new("RGBA", ((cell_w + pad) * len(frames) + pad, cell_h + label_h + pad * 2), (250, 248, 242, 255))
    draw = ImageDraw.Draw(sheet)
    for i, frame in enumerate(frames):
        x = pad + i * (cell_w + pad)
        y = pad + label_h + (cell_h - frame.height)
        draw.text((x, pad // 2), f"{i + 1}", fill=(70, 60, 50, 255))
        draw.rectangle((x, pad + label_h, x + cell_w, pad + label_h + cell_h), outline=(210, 195, 180, 255))
        sheet.alpha_composite(frame, (x + (cell_w - frame.width) // 2, y))
    sheet.save(out)


def composite_sprite_sheet(frames: list[Image.Image], out: Path) -> None:
    sheet = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.alpha_composite(frame, (index * frames[0].width, 0))
    sheet.save(out)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_fox_runner_asset.py <transparent-sprite-sheet> <output-dir>", file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    frames_dir = out_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    boxes = find_components(img)
    if len(boxes) != 6:
        print(f"expected 6 fox components, found {len(boxes)}: {boxes}", file=sys.stderr)
        return 1

    raw_frames = [trim_transparent(img.crop(box)) for box in boxes]
    max_w = max(frame.width for frame in raw_frames)
    max_h = max(frame.height for frame in raw_frames)
    canvas_w = max_w + 36
    canvas_h = max_h + 26
    bottom_pad = 10

    frames: list[Image.Image] = []
    for index, frame in enumerate(raw_frames, start=1):
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        x = (canvas_w - frame.width) // 2
        y = canvas_h - bottom_pad - frame.height
        canvas.alpha_composite(frame, (x, y))
        frame_path = frames_dir / f"fox_{index:02d}.png"
        canvas.save(frame_path)
        frames.append(canvas)

    frames[0].save(
        out_dir / "fox-runner.webp",
        save_all=True,
        append_images=frames[1:],
        duration=110,
        loop=0,
        lossless=False,
        quality=88,
        method=6,
    )

    frames[0].save(
        out_dir / "fox-runner.apng",
        save_all=True,
        append_images=frames[1:],
        duration=110,
        loop=0,
        disposal=2,
    )

    composite_debug_sheet(frames, out_dir / "fox-runner-contact-sheet.png")
    composite_sprite_sheet(frames, out_dir / "fox-runner-sprite.png")

    print(f"source={src}")
    print(f"boxes={boxes}")
    print(f"frame_size={canvas_w}x{canvas_h}")
    print(f"sprite={out_dir / 'fox-runner-sprite.png'}")
    print(f"webp={out_dir / 'fox-runner.webp'}")
    print(f"apng={out_dir / 'fox-runner.apng'}")
    print(f"contact_sheet={out_dir / 'fox-runner-contact-sheet.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
