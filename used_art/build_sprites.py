#!/usr/bin/env python3
"""Build the sprite sheet and sprite ROM for the PPU. Requires Pillow.

Run from the project root: python3 used_art/build_sprites.py
Step 1: copy frames from art_asset/ into used_art/sprites.png (5x5 grid of 32x32).
Step 2: convert used_art/sprites.png into sprites.mem and sprites_rgb222.png.
If art_asset/ is missing, step 1 is skipped and the existing sprites.png is used.

sprites.mem: 25 frames x 32x32 = 25,600 words x 7 bits, ASCII hex.
  address = frame * 1024 + pixel_y * 32 + pixel_x  (= {frame[4:0], y[4:0], x[4:0]})
Word format is the same as back.mem / tileset.mem: {opaque, R[1:0], G[1:0], B[1:0]}.
"""

import argparse
from pathlib import Path

from PIL import Image

from convert_assets import channel

FRAME = 32
COLS = 5
DITHER = False  # small sprites look cleaner without Bayer dithering

# (frame index, source path relative to Assets/, paste offset inside the 32x32 cell, crop box)
FOXY = "Characters/Foxy/{}/sprites/f-{:02d}.png"
FRAMES = (
    [(FOXY.format("idle", i), (0, 0), (0, 0, 32, 32)) for i in range(1, 5)]       # 0-3   idle
    + [(FOXY.format("run", i), (0, 0), (0, 0, 32, 32)) for i in range(1, 7)]      # 4-9   run
    + [(FOXY.format("jump", i), (0, 0), (0, 0, 32, 32)) for i in range(1, 3)]     # 10-11 jump up/down
    + [(FOXY.format("hurt", 1), (0, 0), (0, 0, 32, 32))]                          # 12    hurt
    + [(FOXY.format("Victory", 1), (0, 0), (0, 0, 32, 32))]                       # 13    victory
    # Opossum is 36x28 and faces left: keep its nose, drop 3 px of tail, sit on the bottom row.
    + [(f"Characters/Opossum/opossum/opossum-{i}.png", (0, 4), (1, 0, 33, 28))
       for i in range(1, 7)]                                                      # 14-19 opossum
    # Gem is 15x13: centre it so its pixels cover x 9..21, y 11..21.
    + [(f"Misc/Sunnyland items/Sprites/gem/gem-{i}.png", (8, 10), (0, 0, 15, 13))
       for i in range(1, 6)]                                                      # 20-24 gem
)


def assemble(assets):
    sheet = Image.new("RGBA", (COLS * FRAME, (len(FRAMES) + COLS - 1) // COLS * FRAME))
    for index, (path, offset, box) in enumerate(FRAMES):
        with Image.open(assets / path) as image:
            part = image.convert("RGBA").crop(box)
        cell = Image.new("RGBA", (FRAME, FRAME))
        cell.paste(part, offset)
        sheet.paste(cell, (index % COLS * FRAME, index // COLS * FRAME))
    return sheet


def encode(sheet):
    if any(sheet.getchannel("A").histogram()[1:255]):
        raise ValueError("Only fully opaque or fully transparent pixels are supported")
    words = []
    for index in range(len(FRAMES)):
        left, top = index % COLS * FRAME, index // COLS * FRAME
        for y in range(FRAME):
            for x in range(FRAME):
                r, g, b, a = sheet.getpixel((left + x, top + y))
                words.append((0x40 | channel(r, x, y, DITHER) << 4 | channel(g, x, y, DITHER) << 2
                              | channel(b, x, y, DITHER)) if a else 0)
    return words


def decode(words, size):
    image = Image.new("RGBA", size)
    for i, word in enumerate(words):
        frame, pixel = divmod(i, FRAME * FRAME)
        y, x = divmod(pixel, FRAME)
        image.putpixel((frame % COLS * FRAME + x, frame // COLS * FRAME + y),
                       ((word >> 4 & 3) * 85, (word >> 2 & 3) * 85, (word & 3) * 85,
                        255 if word & 64 else 0))
    return image


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path,
                        default=here.parent / "art_asset" / "Sunny-land-files" / "Assets")
    parser.add_argument("--out", type=Path, default=here)
    args = parser.parse_args()

    sheet_path = args.out / "sprites.png"
    if args.assets.is_dir():
        assemble(args.assets).save(sheet_path)
    with Image.open(sheet_path) as image:
        sheet = image.convert("RGBA")
    words = encode(sheet)
    (args.out / "sprites.mem").write_text("".join(f"{w:02X}\n" for w in words), encoding="ascii")
    decode(words, sheet.size).save(args.out / "sprites_rgb222.png")
    print(f"sprites.mem: {len(FRAMES)} frames, {len(words)} words x 7 bits")


if __name__ == "__main__":
    main()
