# Platformer Game

A small Mario-style platformer written in Verilog for VGA Playground. A custom **PPU** (Picture Processing Unit) draws a parallax background, a scrolling tile map, sprites, and a HUD. A **game logic** module runs the player physics, collisions, enemies, and pickups once per frame. The artwork is SunnyLand.

**[Open in VGA Playground](https://vga-playground.com/?repo=https://github.com/789852tonnam/Platformer_Game)**

## Controls

Enable the gamepad (the blue button), then:

| Key | Action |
| --- | --- |
| Left / Right | Walk |
| Up, `a` or `b` | Jump (hold for a higher jump, tap for a short hop) |
| `t` (Start) | Restart the level |

Goal: reach the wooden gate at the far right, on the ground. Stomp opossums from above. Touching one from the side, or falling into a pit, kills you, and the level restarts after about 2 seconds. Each collected gem appears in the top-left HUD (6 gems in total).

## Architecture

```text
                 once per frame (vblank)                      every pixel
gamepad ──► game_logic ── cam_x ─────────────────────────► ppu ──► RGB222 ──► VGA
              │  S_X → S_GND → S_Y → S_INT → S_OAM            │
              │                          └─ OAM write port ──►│ OAM (11 x 27 bit)
              └─ collision_map (solid.mem)                     │ back / tile / map / sprite ROMs
```

### PPU (`src/ppu.v`)

Layers are drawn back to front at 2x scale (320x240 source pixels):

1. **Background:** a 384x240 image. The sky scrolls at 1/4 of the camera speed and the sea at 1/2, which gives the parallax effect.
2. **Tile layer:** a 60x15 map of 16x16 tiles (`map.mem` → `tileset.mem`), using two ROM reads per pixel.
3. **Sprites:** 11 sprites of 32x32. Each sprite unit tests whether the pixel is inside its box, mirrors horizontally if needed, and reads `sprites.mem`. The lowest-numbered opaque sprite wins, so sprite 0 (the player) is drawn on top.
4. **HUD:** one gem icon per collected gem, fixed to the screen.

Data for pixel x+1 (and x+2 for the two-step tile lookup) is fetched ahead, so every layer is ready when pixel x is output.

**OAM (Object Attribute Memory)** lives inside the PPU. The game writes one entry per clock during vblank, similar to NES OAM DMA, so the sprites never tear. Each entry is 27 bits:

| Bits | Field |
| --- | --- |
| 26 | enable |
| 25 | flip horizontally |
| 24:20 | frame (0-3 idle, 4-9 run, 10-11 jump, 12 hurt, 13 victory, 14-19 opossum, 20-24 gem) |
| 19:10 | y + 64 (so sprites can sit partly above the screen) |
| 9:0 | world x |

### Game logic (`src/game_logic.v`)

On each frame tick (the start of vblank), a state machine runs:

- **S_X:** walks 2 px per frame. If the leading edge of the 14x20 hitbox hits a solid tile, the player snaps to the tile edge.
- **S_GND:** checks for solid ground 1 px below the feet.
- **S_Y:** handles jumps (on button press, only when on the ground), gravity (5/16 px/frame², capped at 7 px/frame), and the variable jump height. The player lands on floors and bumps into ceilings, snapping to the tile edge in both cases. Position y uses 4 fractional bits.
- **S_INT:** handles enemies (stomp or get hit), gems, pits, the goal, the camera, and animation.
- **S_OAM:** copies the 11 sprite entries into the PPU.

Collisions use a separate 1-bit `solid.mem` instead of the graphics map, so decorations and the cave backdrop are not solid. All arithmetic is unsigned. Every y value is stored as y + 64, and the velocity is an 8-bit two's complement value handled with plain bit operations. Every signal is at most 64 bits wide, which the VGA Playground simulator requires.

## File Structure

```text
Platformer_Game/
├── info.yaml                 # VGA Playground: sources and top module
├── src/
│   ├── platformer.v          # Top module (tt_um_platformer_game): wiring
│   ├── ppu.v                 # PPU: background, tiles, sprites, HUD, OAM
│   ├── game_logic.v          # Physics, collision_map, enemy, pickup modules
│   ├── hsync_generator.v     # VGA timing
│   ├── gamepad_pmod.v        # Gamepad driver
│   └── bg_scrolling.v        # Earlier background-scrolling version (not built)
├── used_art/
│   ├── back.mem, tileset.mem # Background and tile ROMs
│   ├── map.mem               # 60x15 tile IDs
│   ├── solid.mem             # 60x15 collision bits
│   ├── sprites.png / .mem    # 25 sprite frames, 32x32, built from art_asset/
│   ├── convert_assets.py     # back.png + tileset.png -> .mem
│   ├── build_map.py          # Level layout -> map.mem + solid.mem
│   └── build_sprites.py      # art_asset frames -> sprites.png -> sprites.mem
└── art_asset/                # Original SunnyLand asset pack
```

## Regenerate ROM Files

```bash
python3 -m pip install Pillow
python3 used_art/convert_assets.py
python3 used_art/build_map.py
python3 used_art/build_sprites.py
```

For a local simulation (for example with Icarus Verilog), run from `src/` so the `../used_art/*.mem` paths resolve.

## Assets

Artwork: **[SunnyLand by Ansimuz](https://ansimuz.itch.io/sunny-land-pixel-game-art)**. The asset page lists the license as CC0.
