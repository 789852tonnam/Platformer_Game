# Platformer Game

A Verilog project that renders a tile-based scene with horizontal scrolling in VGA Playground. It uses SunnyLand artwork and a level built from 16x16 pixel tiles.

**[Open in VGA Playground](https://vga-playground.com/?repo=https://github.com/789852tonnam/Platformer_Game)**

## Controls

1. Open the VGA Playground link above and wait for the project to load.
2. Enable the gamepad controls and press **Left / Right** to scroll through the level.

The display runs at 640x480 pixels with RGB222 output (64 colors). Bayer dithering is applied ahead of time in Python. Artwork is displayed at 2x scale, so each tile occupies 32x32 screen pixels.

The map is **60x15 tiles**, spanning three screens, with grassy terrain, pits, outdoor floating platforms, and a cave. The `scroll_offset` ranges from 0 to 640 source pixels and changes by one source pixel per frame while a direction button is held.

## How It Works

```text
VGA coordinates -> Divide by 2, add scroll_offset -> Map ROM -> Tile ID
                                                                  |
                                                                  v
                                                              Tile ROM
                                                                  |
Back ROM -> Background color --------------------------> Select color -> VGA
```

- **Map ROM:** 900 entries, each containing a 10-bit tile ID.
- **Tile ROM:** 575 tiles stored consecutively in the order of the original 25x23 tile atlas.
- **Back ROM:** A 384x240 pixel background image.
- Each pixel uses 7 bits: `{opaque, R[1:0], G[1:0], B[1:0]}`. When `opaque = 0`, the background color is displayed instead.

## File Structure

```text
Platformer_Game/
├── info.yaml                 # Project metadata and sources for VGA Playground
├── README.md
├── .gitignore                # Excludes PDFs and Python caches
├── src/
│   ├── bg_scrolling.v        # Top module: ROM reads, compositing, and scrolling
│   ├── hsync_generator.v     # VGA coordinates and synchronization signals
│   └── gamepad_pmod.v        # Gamepad input driver
├── used_art/
│   ├── back.png              # Original background image
│   ├── tileset.png           # Original tile atlas
│   ├── back.mem              # Background ROM data
│   ├── tileset.mem           # Tile ROM data, stored one 16x16 tile at a time
│   ├── map.mem               # 60x15 map, stored in row-major order
│   ├── back_rgb222.png       # Converted RGB222 previews
│   ├── tileset_rgb222.png
│   ├── map.png               # Level preview with original colors
│   ├── map_rgb222.png        # Level preview with RGB222 colors
│   ├── convert_assets.py     # PNG-to-ROM conversion with Bayer dithering
│   ├── build_map.py          # Level layout and map.mem generation
│   └── README.txt            # ROM formats and detailed map documentation
└── art_asset/                # Downloaded original asset pack
```

## Regenerate ROM Files

Run these commands from the project root using Python and Pillow:

```bash
python3 -m pip install Pillow
python3 used_art/convert_assets.py
python3 used_art/build_map.py
```

For local Verilog simulation, use `src/` as the working directory so the `../used_art/*.mem` paths match the `$readmemh` calls in the source.

## Assets

Artwork: **[SunnyLand by Ansimuz](https://ansimuz.itch.io/sunny-land-pixel-game-art)**. The asset page lists the license as CC0.
