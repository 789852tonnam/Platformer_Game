#!/usr/bin/env python3
"""Convert SunnyLand back.png and tileset.png to $readmemh ROM data.

Requires Pillow: python3 -m pip install Pillow
Usage: python3 convert_assets.py [PATH/TO/used_art] [OUTPUT_DIR]
Each word is 7 bits: {opaque, red[1:0], green[1:0], blue[1:0]}.
Uses 4x4 Bayer ordered dithering; tile boundaries keep the same pattern.
"""

import argparse
from pathlib import Path

from PIL import Image


BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def channel(value, x, y, dither):
    if not dither:
        return (value * 3 + 127) // 255
    level, remainder = divmod(value * 3, 255)
    return level + int(remainder * 32 > (2 * BAYER[y % 4][x % 4] + 1) * 255)


def encode(image, tiled=False, dither=True):
    image = image.convert("RGBA")
    width, height = image.size
    if tiled and (width % 16 or height % 16):
        raise ValueError("Tileset width and height must be multiples of 16")
    if any(image.getchannel("A").histogram()[1:255]):
        raise ValueError("Only fully opaque or fully transparent pixels are supported")

    words = []
    step_x, step_y = (16, 16) if tiled else (width, height)
    for top in range(0, height, step_y):
        for left in range(0, width, step_x):
            for y in range(top, top + step_y):
                for x in range(left, left + step_x):
                    r, g, b, a = image.getpixel((x, y))
                    words.append(
                        (0x40 | (channel(r, x, y, dither) << 4)
                         | (channel(g, x, y, dither) << 2) | channel(b, x, y, dither))
                        if a else 0
                    )
    return words


def decode(words, size, tiled=False):
    """Reconstruct exactly the pixels in the ROM, for preview and round-trip checks."""
    image = Image.new("RGBA", size)
    width, height = size
    step_x, step_y = (16, 16) if tiled else size
    index = 0
    for top in range(0, height, step_y):
        for left in range(0, width, step_x):
            for y in range(top, top + step_y):
                for x in range(left, left + step_x):
                    word = words[index]
                    image.putpixel((x, y), (((word >> 4) & 3) * 85,
                                           ((word >> 2) & 3) * 85,
                                           (word & 3) * 85,
                                           255 if word & 64 else 0))
                    index += 1
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=Path(__file__).resolve().parent,
                        help="Directory containing both PNG files (default: beside script)")
    parser.add_argument("output", type=Path, nargs="?", help="Default: source directory")
    args = parser.parse_args()
    output = args.output or args.source

    # Validate both inputs before writing either ROM.
    converted = []
    for name, tiled in (("back", False), ("tileset", True)):
        with Image.open(args.source / f"{name}.png") as image:
            image = image.convert("RGBA")
            converted.append((name, image, tiled, encode(image, tiled)))
    output.mkdir(parents=True, exist_ok=True)
    for name, image, tiled, words in converted:
        size = image.size
        target = output / f"{name}.mem"
        target.write_text("".join(f"{word:02X}\n" for word in words), encoding="ascii")
        preview = decode(words, size, tiled)
        preview.save(output / f"{name}_rgb222.png")
        print(f"{target}: {size[0]}x{size[1]}, {len(words)} words x 7 bits")


if __name__ == "__main__":
    main()
