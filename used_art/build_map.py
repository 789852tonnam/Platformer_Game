#!/usr/bin/env python3
"""Build a 60x15 SunnyLand tile map. Requires Pillow.

Run beside the used_art PNGs: python3 build_map.py
Or: python3 build_map.py PATH/TO/used_art OUTPUT_DIR
Map words are 10-bit tile IDs, row-major, three hex digits per line.
"""

import argparse
from pathlib import Path

from PIL import Image


WIDTH, HEIGHT, TILE = 60, 15, 16
EMPTY = 0
CAVE_BACK = 452  # Background artwork, not a collision surface.


def build_map():
    grid = [[EMPTY] * WIDTH for _ in range(HEIGHT)]

    # A dark tunnel behind the foreground roof, platforms, and floor.
    for y in range(7, HEIGHT):
        for x in range(40, 57):
            grid[y][x] = CAVE_BACK

    # Long ground sections leave one outdoor pit and one cave pit.
    for left, right in ((0, 14), (17, 46), (50, 59)):
        for y in range(12, HEIGHT):
            for x in range(left, right + 1):
                grid[y][x] = (26 if x == left else 30 if x == right else 28) if y == 12 else (
                    76 if x == left else 80 if x == right else 78
                )

    def platform(left, right, row):
        for x in range(left, right + 1):
            grid[row][x] = 365 if x == left else 369 if x == right else 367

    # Three optional steps reach the rooftop; the cave has no floating platforms.
    for left, right, row in (
        (22, 25, 10), (28, 31, 8), (35, 38, 6),
    ):
        platform(left, right, row)

    # Grassy cave roof: top, solid rock body, and exposed underside.
    for y in range(4, 7):
        for x in range(40, 57):
            left, middle, right = (26, 28, 30) if y == 4 else (
                (126, 128, 130) if y == 6 else (76, 78, 80)
            )
            grid[y][x] = left if x == 40 else right if x == 56 else middle

    # Small vegetation and stalactites; these are decorative tile IDs.
    for x, tile in ((2, 201), (4, 203), (18, 201), (21, 203), (29, 201), (34, 203)):
        grid[11][x] = tile
    for x in (42, 48, 54):
        grid[7][x] = 361

    # A 3x3 wooden gate marks the end of the level.
    for dy, row in enumerate(((190, 192, 194), (240, 242, 244), (290, 292, 294))):
        grid[9 + dy][57:60] = row

    assert len(grid) == 15 and all(len(row) == 60 for row in grid)
    assert all(0 <= tile < 575 for row in grid for tile in row)
    for left, right in ((15, 16), (47, 49)):
        assert all(grid[y][x] in (EMPTY, CAVE_BACK)
                   for y in range(12, 15) for x in range(left, right + 1))
    return grid


def render(grid, tileset, background):
    if tileset.size != (400, 368) or background.size != (384, 240):
        raise ValueError("Expected a 400x368 tileset and 384x240 background")
    scene = Image.new("RGBA", (WIDTH * TILE, HEIGHT * TILE))
    for x in range(0, scene.width, background.width):
        scene.paste(background, (x, 0))
    for y, row in enumerate(grid):
        for x, tile in enumerate(row):
            tx, ty = tile % 25 * TILE, tile // 25 * TILE
            patch = tileset.crop((tx, ty, tx + TILE, ty + TILE))
            scene.alpha_composite(patch, (x * TILE, y * TILE))
    return scene.convert("RGB").resize((1920, 480), Image.Resampling.NEAREST)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=Path(__file__).resolve().parent)
    parser.add_argument("output", type=Path, nargs="?")
    args = parser.parse_args()
    output = args.output or args.source
    grid = build_map()
    # Render both versions before writing files, so missing inputs fail early.
    previews = []
    for suffix in ("", "_rgb222"):
        with Image.open(args.source / f"tileset{suffix}.png") as tiles, Image.open(
            args.source / f"back{suffix}.png"
        ) as back:
            previews.append((suffix, render(grid, tiles.convert("RGBA"), back.convert("RGBA"))))
    output.mkdir(parents=True, exist_ok=True)
    (output / "map.mem").write_text(
        "".join(f"{tile:03X}\n" for row in grid for tile in row), encoding="ascii"
    )
    for suffix, preview in previews:
        preview.save(output / f"map{suffix}.png")
    assert len((output / "map.mem").read_text().split()) == WIDTH * HEIGHT
    print("Built map.mem: 60x15 = 900 words x 10 bits; previews: 1920x480")


if __name__ == "__main__":
    main()
