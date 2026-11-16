/*
 * PPU (Picture Processing Unit) for the SunnyLand platformer.
 *
 * Layers, back to front:
 *   1. Background  - 384x240 image, parallax scroll (sky = cam/4, sea = cam/2)
 *   2. Tile layer  - 60x15 map of 16x16 tiles, scrolls with the camera
 *   3. Sprites     - NSPR sprites of 32x32 from the sprite ROM (OAM = attribute table)
 *   4. HUD         - one gem icon per collected gem, fixed on screen
 *
 * Everything is drawn at 2x scale: one source pixel = 2x2 VGA pixels, so the
 * visible source area is 320x240.
 *
 * OAM: NSPR entries stored inside the PPU. The game writes them one per clock
 * through (oam_we, oam_addr, oam_data) during vblank, like NES OAM DMA.
 * (This also keeps every signal <= 64 bits for the VGA Playground simulator.)
 *
 * OAM entry (27 bits each, sprite 0 has the highest priority):
 *   [26]    enable
 *   [25]    flip horizontally
 *   [24:20] frame index in the sprite ROM (32x32 per frame)
 *   [19:10] y + 64  (world y with an offset of 64, so sprites can be partly above the screen)
 *   [9:0]   x       (world x of the left edge, 0..959)
 *
 * Pipeline: the beam is at pix_x; data for pix_x+1 (background, sprites) and
 * pix_x+2 (map -> tile, two ROM reads) is fetched ahead, so every layer is
 * ready when the color register for pix_x is written.
 */

`default_nettype none

module ppu #(
    parameter NSPR = 11
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [9:0]           pix_x,
    input  wire [9:0]           pix_y,
    input  wire [9:0]           cam_x,      // camera left edge in world pixels (0..640)
    input  wire                 oam_we,     // OAM write port (used by the game during vblank)
    input  wire [3:0]           oam_addr,
    input  wire [26:0]          oam_data,
    input  wire [2:0]           hud_count,
    output reg  [5:0]           rgb         // {R[1:0], G[1:0], B[1:0]}
);

  // ---------------------------------------------------------------- ROMs
  reg [6:0] back_rom [0:92159];    // 384x240
  reg [6:0] tile_rom [0:147199];   // 575 tiles x 16x16
  reg [9:0] map_rom  [0:899];      // 60x15 tile IDs
  reg [6:0] spr_rom  [0:25599];    // 25 frames x 32x32

  initial begin
    $readmemh("../used_art/back.mem", back_rom);
    $readmemh("../used_art/tileset.mem", tile_rom);
    $readmemh("../used_art/map.mem", map_rom);
    $readmemh("../used_art/sprites.mem", spr_rom);
  end

  // ------------------------------------------------- look-ahead positions
  wire       line_end1 = (pix_x == 10'd799);
  wire       line_end2 = (pix_x >= 10'd798);
  wire [9:0] next_y    = (pix_y == 10'd524) ? 10'd0 : pix_y + 10'd1;

  wire [9:0] x1 = line_end1 ? 10'd0 : pix_x + 10'd1;
  wire [9:0] y1 = line_end1 ? next_y : pix_y;
  wire [9:0] x2 = line_end2 ? pix_x - 10'd798 : pix_x + 10'd2;
  wire [9:0] y2 = line_end2 ? next_y : pix_y;

  wire vis1 = (x1 < 10'd640) && (y1 < 10'd480);
  wire vis2 = (x2 < 10'd640) && (y2 < 10'd480);

  // Source (1x) coordinates
  wire [9:0] sx1 = {1'b0, x1[9:1]};       // 0..319 on screen
  wire [9:0] sy1 = {1'b0, y1[9:1]};       // 0..239
  wire [9:0] wx1 = sx1 + cam_x;           // world x
  wire [9:0] wyo1 = sy1 + 10'd64;         // world y + 64 (OAM convention)

  wire [9:0] wx2 = {1'b0, x2[9:1]} + cam_x;
  wire [9:0] wy2 = {1'b0, y2[9:1]};

  // -------------------------------------------------- layer 1: background
  // Sky (top 112 rows) moves at 1/4 camera speed, sea at 1/2: parallax.
  wire [9:0]  par    = (sy1 < 10'd112) ? {2'b0, cam_x[9:2]} : {1'b0, cam_x[9:1]};
  wire [10:0] bx_sum = {1'b0, sx1} + {1'b0, par};
  wire [9:0]  bx     = (bx_sum >= 11'd384) ? bx_sum - 11'd384 : bx_sum[9:0];
  wire [16:0] back_addr = vis1 ? sy1 * 17'd384 + {7'd0, bx} : 17'd0;

  // ---------------------------------------------------- layer 2: tile map
  wire [9:0] map_addr = vis2 ? wy2[7:4] * 10'd60 + {4'd0, wx2[9:4]} : 10'd0;

  reg  [9:0] tile_id;
  reg  [3:0] tile_px, tile_py;

  // ----------------------------------------------------- layer 3: sprites
  // OAM (Object Attribute Memory): the game writes it during vblank.
  reg [26:0] oam_mem [0:NSPR-1];
  reg        oam_ready;               // no sprites until the first OAM write

  always @(posedge clk) begin
    if (oam_we) oam_mem[oam_addr] <= oam_data;
  end

  // Every sprite unit tests the pixel against its 32x32 box and fetches its
  // pixel from the sprite ROM.
  wire [NSPR-1:0] spr_opaque;
  wire [6:0]      spr_word [0:NSPR-1];

  genvar i;
  generate
    for (i = 0; i < NSPR; i = i + 1) begin : sprite_unit
      wire [26:0] e    = oam_mem[i];
      wire [10:0] dx   = {1'b0, wx1} - {1'b0, e[9:0]};   // wraps to >= 32 when left of sprite
      wire [9:0]  dy   = wyo1 - e[19:10];
      wire        hit  = oam_ready && e[26] && (dx < 11'd32) && (dy < 10'd32);
      wire [4:0]  lx   = e[25] ? ~dx[4:0] : dx[4:0];      // ~dx = 31 - dx (mirror)
      wire [14:0] addr = hit ? {e[24:20], dy[4:0], lx} : 15'd0;
      wire [6:0]  word = spr_rom[addr];
      assign spr_word[i]   = word;
      assign spr_opaque[i] = hit && word[6];
    end
  endgenerate

  // Priority: the lowest-numbered opaque sprite wins (sprite 0 = player on top).
  reg [6:0] spr_pick;
  integer j;
  always @(*) begin
    spr_pick = 7'd0;
    for (j = NSPR - 1; j >= 0; j = j - 1)
      if (spr_opaque[j]) spr_pick = spr_word[j];
  end

  // --------------------------------------------------------- layer 4: HUD
  // Gem icons at screen (4 + 16*n, 4), using gem frame 20.
  localparam [4:0] HUD_FRAME = 5'd20;
  wire [9:0] hud_dx  = sx1 - 10'd4;
  wire [9:0] hud_dy  = sy1 - 10'd4;
  wire       in_hud  = vis1 && (sx1 >= 10'd4) && (sy1 >= 10'd4) && (sy1 < 10'd20)
                       && (hud_dx[9:4] < {3'd0, hud_count});
  wire [4:0] hud_lx  = {1'b0, hud_dx[3:0]} + 5'd8;
  wire [4:0] hud_ly  = {1'b0, hud_dy[3:0]} + 5'd9;
  wire [6:0] hud_word = spr_rom[in_hud ? {HUD_FRAME, hud_ly, hud_lx} : 15'd0];

  // ------------------------------------------------------- fetch pipeline
  reg [6:0] color_bg;
  reg [6:0] tile_color;
  reg [6:0] spr_color;

  always @(posedge clk) begin
    if (!rst_n) begin
      rgb        <= 6'd0;
      color_bg   <= 7'd0;
      tile_id    <= 10'd0;
      tile_px    <= 4'd0;
      tile_py    <= 4'd0;
      tile_color <= 7'd0;
      spr_color  <= 7'd0;
      oam_ready  <= 1'b0;
    end else begin
      if (oam_we) oam_ready <= 1'b1;

      // pixel + 2: which tile is there?
      tile_id <= vis2 ? map_rom[map_addr] : 10'd0;
      tile_px <= wx2[3:0];
      tile_py <= wy2[3:0];

      // pixel + 1: tile pixel, background pixel, sprite/HUD pixel
      tile_color <= tile_rom[{tile_id, tile_py, tile_px}];
      color_bg   <= back_rom[back_addr];
      spr_color  <= (in_hud && hud_word[6]) ? hud_word : spr_pick;

      // pixel: composite (sprites > tiles > background)
      if (pix_x < 10'd640 && pix_y < 10'd480) begin
        if (spr_color[6])
          rgb <= spr_color[5:0];
        else if (tile_color[6])
          rgb <= tile_color[5:0];
        else
          rgb <= color_bg[5:0];
      end else begin
        rgb <= 6'd0;
      end
    end
  end

endmodule
