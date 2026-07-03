from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


def alpha_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    return img.getchannel("A").getbbox()


def find_row_components(img: Image.Image) -> list[tuple[int, int, int, int]]:
    alpha = img.getchannel("A")
    width, height = img.size
    occupied_rows = [alpha.crop((0, y, width, y + 1)).getbbox() is not None for y in range(height)]

    ranges: list[tuple[int, int]] = []
    start: int | None = None
    gap = 0
    max_gap = max(2, height // 260)

    for y, occupied in enumerate(occupied_rows):
        if occupied:
            if start is None:
                start = y
            gap = 0
            continue
        if start is not None:
            gap += 1
            if gap > max_gap:
                ranges.append((start, y - gap + 1))
                start = None
                gap = 0

    if start is not None:
        ranges.append((start, height))

    boxes: list[tuple[int, int, int, int]] = []
    for top, bottom in ranges:
        crop_alpha = alpha.crop((0, top, width, bottom))
        bbox = crop_alpha.getbbox()
        if bbox:
            left, inner_top, right, inner_bottom = bbox
            boxes.append((left, top + inner_top, right, top + inner_bottom))
    return boxes


def keep_large_alpha_components(img: Image.Image, min_area: int) -> Image.Image:
    width, height = img.size
    pix = img.load()
    seen: set[tuple[int, int]] = set()
    keep: set[tuple[int, int]] = set()

    for sy in range(height):
        for sx in range(width):
            if (sx, sy) in seen or pix[sx, sy][3] == 0:
                continue

            component: list[tuple[int, int]] = []
            queue: deque[tuple[int, int]] = deque([(sx, sy)])
            seen.add((sx, sy))
            while queue:
                x, y = queue.popleft()
                component.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    if (nx, ny) in seen or pix[nx, ny][3] == 0:
                        continue
                    seen.add((nx, ny))
                    queue.append((nx, ny))

            if len(component) >= min_area:
                keep.update(component)

    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out_pix = out.load()
    for x, y in keep:
        out_pix[x, y] = pix[x, y]
    return out


def normalize_frame(frame: Image.Image, canvas_w: int, canvas_h: int, bottom_pad: int) -> Image.Image:
    bbox = alpha_bbox(frame)
    if not bbox:
        return Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    trimmed = frame.crop(bbox)
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    x = (canvas_w - trimmed.width) // 2
    y = canvas_h - bottom_pad - trimmed.height
    canvas.alpha_composite(trimmed, (x, y))
    return canvas


def contact_sheet(frames: list[Image.Image], out: Path) -> None:
    pad = 12
    label_h = 20
    cell_w = max(frame.width for frame in frames)
    cell_h = max(frame.height for frame in frames)
    sheet = Image.new("RGBA", ((cell_w + pad) * len(frames) + pad, cell_h + label_h + pad * 2), (250, 248, 242, 255))
    draw = ImageDraw.Draw(sheet)
    for i, frame in enumerate(frames):
        x = pad + i * (cell_w + pad)
        y = pad + label_h
        draw.text((x, pad // 2), str(i + 1), fill=(70, 60, 50, 255))
        draw.rectangle((x, y, x + cell_w, y + cell_h), outline=(210, 195, 180, 255))
        sheet.alpha_composite(frame, (x, y))
    sheet.save(out)


def sprite_sheet(frames: list[Image.Image], out: Path) -> None:
    sheet = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * frames[0].width, 0))
    sheet.save(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--frames", type=int, required=True)
    parser.add_argument("--frame-height", type=int)
    parser.add_argument("--min-component-area", type=int, default=80)
    parser.add_argument("--duration", type=int, default=180)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = args.output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    src = Image.open(args.source).convert("RGBA")
    if args.frame_height:
        boxes = []
        for index in range(args.frames):
            top = index * args.frame_height
            bottom = min(src.height, top + args.frame_height)
            bbox = alpha_bbox(src.crop((0, top, src.width, bottom)))
            if bbox:
                left, inner_top, right, inner_bottom = bbox
                boxes.append((left, top + inner_top, right, top + inner_bottom))
    else:
        boxes = find_row_components(src)
    if len(boxes) != args.frames:
        print(f"expected {args.frames} frame rows, found {len(boxes)}: {boxes}")
        return 1

    raw_frames = [keep_large_alpha_components(src.crop(box), args.min_component_area) for box in boxes]
    trimmed = [frame.crop(alpha_bbox(frame)) for frame in raw_frames if alpha_bbox(frame)]
    canvas_w = max(frame.width for frame in trimmed) + 18
    canvas_h = max(frame.height for frame in trimmed) + 14
    frames = [normalize_frame(frame, canvas_w, canvas_h, bottom_pad=5) for frame in raw_frames]

    for i, frame in enumerate(frames, 1):
        frame.save(frames_dir / f"{args.prefix}_{i:02d}.png")

    sprite_sheet(frames, args.output_dir / f"{args.prefix}-sprite.png")
    contact_sheet(frames, args.output_dir / f"{args.prefix}-contact-sheet.png")
    frames[0].save(
        args.output_dir / f"{args.prefix}.webp",
        save_all=True,
        append_images=frames[1:],
        duration=args.duration,
        loop=0,
        lossless=False,
        quality=88,
        method=6,
    )

    print(f"source={args.source}")
    print(f"boxes={boxes}")
    print(f"frame_size={canvas_w}x{canvas_h}")
    print(f"sprite={args.output_dir / f'{args.prefix}-sprite.png'}")
    print(f"contact_sheet={args.output_dir / f'{args.prefix}-contact-sheet.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
