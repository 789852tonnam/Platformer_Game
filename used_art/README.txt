Run beside back.png and tileset.png:
  python3 convert_assets.py
Requires Pillow: python3 -m pip install Pillow

MEM: ASCII hex, one 7-bit word per line, for $readmemh.
Bits: [6] opaque (1=visible), [5:4] red, [3:2] green, [1:0] blue.
Transparent pixels are 00; opaque black is 40.
RGB222 channel values 0,1,2,3 represent 0,85,170,255.
4x4 Bayer ordered dithering is applied in Python, with no runtime HDL cost.
The matrix repeats within each 16x16 tile, so rearranging tiles keeps its phase.
Only binary alpha is supported; partial alpha is rejected.

back.mem: 384x240, 92,160 words, row-major.
  address = y * 384 + x; x=0..383, y=0..239.
tileset.mem: 400x368 = 25x23 tiles = 575 tiles, 147,200 words.
  Tiles are numbered left-to-right, then top-to-bottom, starting at zero.
  Each tile is 16x16, pixels left-to-right then top-to-bottom.
  address = tile_id * 256 + pixel_y * 16 + pixel_x.
  tile_id=0..574 (10 bits), pixel_x/pixel_y=0..15.
  Some tile IDs are empty transparent cells; no compaction is performed.

Verilog declarations:
  reg [6:0] back_rom [0:92159];
  reg [6:0] tile_rom [0:147199];
  initial begin
    $readmemh("../used_art/back.mem", back_rom);
    $readmemh("../used_art/tileset.mem", tile_rom);
  end
Run local simulation from src/ so ../used_art paths resolve.
VGA Playground loads these paths relative to src/ in the GitHub repository.
Add MEM files to FPGA projects.

*_rgb222.png are reconstructed from encoded words, preserving alpha.
The current HDL displays the background at 2x scale; the map builder is documented below.


Map design: 60 columns x 15 rows, zero-based coordinates.
Each tile is 16x16 source pixels, displayed at 2x (32x32 screen pixels).
World: 960x240 source pixels / 1920x480 display pixels = 3 screens.
Viewport: 20x15 tiles. Native-pixel scrollOffset range: 0..640.

map.mem: 900 words x 10 bits, ASCII hex, 3 digits per word.
Address = tile_row * 60 + tile_col.
Tile ID = tileset_row * 25 + tileset_col (original 25x23 atlas, unchanged).
Pixel address in tileset.mem = tile_id * 256 + pixel_y * 16 + pixel_x.

World coordinate conversion:
  world_x = (pix_x >> 1) + scrollOffset;
  world_y = pix_y >> 1;
  tile_col = world_x >> 4;
  tile_row = world_y >> 4;
  pixel_x = world_x & 15;
  pixel_y = world_y & 15;
Guard VGA blanking before accessing the map. Align ROM latency with VGA sync.

Ground: rows 12..14, columns 0..14, 17..46, 50..59.
Pits: columns 15..16 and 47..49, open through row 14.
Floating platforms (left..right, row):
  22..25,10; 28..31,8; 35..38,6.
The three platforms form an optional ascent to the cave roof.
There are no floating platforms inside the cave.
The ground route stays continuous between the two pits.
Cave: columns 40..56; solid grassy roof at rows 4..6;
  dark background at rows 7..14, behind foreground terrain.
  Stalactites at (42,7), (48,7), (54,7).
Exit marker: wooden gate, columns 57..59, rows 9..11.

Selected tile IDs (decimal):
  0 = empty transparent cell.
  26/28/30 = grass surface, left/middle/right.
  76/78/80 = ground body, left/middle/right.
  126/128/130 = exposed underside of cave roof.
  365/367/369 = floating platform, left/middle/right.
  201/203 = decorative grass.
  361 = decorative stalactite.
  452 = dark cave background: NOT solid ground.
  Gate rows: 190/192/194, 240/242/244, 290/292/294 (decoration).

This is a graphics tile map, not a collision map. Do not derive solidity from
opaque pixels: cave backdrop and decorations are opaque but not terrain.
Jump reachability depends on future player speed, gravity, and jump impulse;
no movement/collision implementation or playtesting is included.

map.png: original-color layout preview.
map_rgb222.png: the same layout using the dithered RGB222 assets.
Preview repeats back.png at its native width; the atlas/Map ROM is unchanged.
The map is not connected to the current HDL renderer yet.
Rebuild: python3 used_art/build_map.py
Requires Pillow and back.png/tileset.png plus their *_rgb222.png versions.
