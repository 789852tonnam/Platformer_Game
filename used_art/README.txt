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
No scene map generation is included. The current HDL displays the background at 2x scale.
