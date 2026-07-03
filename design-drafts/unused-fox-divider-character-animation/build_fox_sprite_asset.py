from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw


def find_components(img: Image.Image, max_gap: int | None = None) -> list[tuple[int, int, int, int]]:
    alpha = img.getchannel("A")
    width, height = img.size
    occupied_columns: list[bool] = []

    for x in range(width):
        column = alpha.crop((x, 0, x + 1, height))
        occupied_columns.append(column.getbbox() is not None)

    ranges: list[tuple[int, int]] = []
    start: int | None = None
    gap = 0
    if max_gap is None:
        max_gap = max(8, width // 220)

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


def remove_small_alpha_components(img: Image.Image, min_area: int) -> Image.Image:
    if min_area <= 0:
        return img

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


def split_wide_components(
    img: Image.Image,
    boxes: list[tuple[int, int, int, int]],
    expected_count: int,
) -> list[tuple[int, int, int, int]]:
    if len(boxes) >= expected_count or not boxes:
        return boxes

    alpha = img.getchannel("A")
    split_boxes = boxes[:]

    while len(split_boxes) < expected_count:
        widths = [right - left for left, _, right, _ in split_boxes]
        typical = median(widths)
        widest_index = max(range(len(split_boxes)), key=lambda index: widths[index])
        widest = split_boxes[widest_index]
        left, top, right, bottom = widest
        width = right - left
        if typical <= 0 or width < typical * 1.35:
            break

        mid = left + width // 2
        replacements: list[tuple[int, int, int, int]] = []
        for part_left, part_right in ((left, mid), (mid, right)):
            part_alpha = alpha.crop((part_left, top, part_right, bottom))
            bbox = part_alpha.getbbox()
            if not bbox:
                continue
            l2, t2, r2, b2 = bbox
            replacements.append((part_left + l2, top + t2, part_left + r2, top + b2))

        if len(replacements) != 2:
            break
        split_boxes[widest_index:widest_index + 1] = replacements

    return split_boxes


def composite_debug_sheet(frames: list[Image.Image], out: Path) -> None:
    pad = 18
    label_h = 24
    cell_w = max(frame.width for frame in frames)
    cell_h = max(frame.height for frame in frames)
    sheet = Image.new(
        "RGBA",
        ((cell_w + pad) * len(frames) + pad, cell_h + label_h + pad * 2),
        (250, 248, 242, 255),
    )
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--frames", type=int, required=True)
    parser.add_argument("--prefix", default="fox")
    parser.add_argument("--duration", type=int, default=170)
    parser.add_argument("--max-gap", type=int, help="Maximum transparent column gap to bridge when detecting components.")
    parser.add_argument("--min-component-area", type=int, default=0, help="Drop tiny disconnected alpha fragments inside each frame.")
    parser.add_argument(
        "--slice-grid",
        action="store_true",
        help="Split the source into equal-width frame slots before trimming instead of detecting separated components.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    frames_dir = args.output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(args.source).convert("RGBA")
    if args.slice_grid:
        boxes = []
        for index in range(args.frames):
            left = round(index * img.width / args.frames)
            right = round((index + 1) * img.width / args.frames)
            slot = img.crop((left, 0, right, img.height))
            bbox = slot.getchannel("A").getbbox()
            if bbox:
                l2, top, r2, bottom = bbox
                boxes.append((left + l2, top, left + r2, bottom))
    else:
        boxes = find_components(img, args.max_gap)
        boxes = split_wide_components(img, boxes, args.frames)
    if len(boxes) != args.frames:
        print(f"expected {args.frames} fox components, found {len(boxes)}: {boxes}")
        return 1

    raw_frames = [trim_transparent(remove_small_alpha_components(img.crop(box), args.min_component_area)) for box in boxes]
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
        frame_path = frames_dir / f"{args.prefix}_{index:02d}.png"
        canvas.save(frame_path)
        frames.append(canvas)

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

    frames[0].save(
        args.output_dir / f"{args.prefix}.apng",
        save_all=True,
        append_images=frames[1:],
        duration=args.duration,
        loop=0,
        disposal=2,
    )

    composite_debug_sheet(frames, args.output_dir / f"{args.prefix}-contact-sheet.png")
    composite_sprite_sheet(frames, args.output_dir / f"{args.prefix}-sprite.png")

    print(f"source={args.source}")
    print(f"boxes={boxes}")
    print(f"frame_size={canvas_w}x{canvas_h}")
    print(f"sprite={args.output_dir / f'{args.prefix}-sprite.png'}")
    print(f"webp={args.output_dir / f'{args.prefix}.webp'}")
    print(f"apng={args.output_dir / f'{args.prefix}.apng'}")
    print(f"contact_sheet={args.output_dir / f'{args.prefix}-contact-sheet.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
