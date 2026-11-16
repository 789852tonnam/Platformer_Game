/*
 * SunnyLand platformer: top module.
 *
 *   gamepad -> game_logic (once per frame) -> camera + OAM -> ppu -> VGA
 *
 * Controls (VGA Playground keyboard): arrows move, Up / A / B jump,
 * T (Start) restarts the level.
 */

`default_nettype none

module tt_um_platformer_game (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam NSPR = 11;  // 1 player + 4 enemies + 6 gems

  assign uio_out = 0;
  assign uio_oe  = 0;
  wire _unused_ok = &{ena, ui_in[7], ui_in[3:0], uio_in};

  // ------------------------------------------------------------ VGA sync
  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  wire [5:0] rgb;

  // Tiny VGA Pmod
  assign uo_out = {hsync, rgb[0], rgb[2], rgb[4], vsync, rgb[1], rgb[3], rgb[5]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ------------------------------------------------------------- gamepad
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right;
  wire inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r)
  );

  // ---------------------------------------------------------------- game
  // One pulse per frame when the beam enters vblank: the game updates while
  // nothing is being drawn, so sprites never tear.
  wire frame_tick = (pix_x == 10'd0) && (pix_y == 10'd480);

  wire [9:0]  cam_x;
  wire        oam_we;
  wire [3:0]  oam_addr;
  wire [26:0] oam_data;
  wire [2:0]  gem_count;

  game_logic #(.NSPR(NSPR)) game (
      .clk(clk),
      .rst_n(rst_n),
      .frame_tick(frame_tick),
      .btn_left(inp_left),
      .btn_right(inp_right),
      .btn_jump(inp_up | inp_a | inp_b),
      .btn_start(inp_start),
      .cam_x(cam_x),
      .oam_we(oam_we),
      .oam_addr(oam_addr),
      .oam_data(oam_data),
      .gem_count(gem_count)
  );

  // ----------------------------------------------------------------- PPU
  ppu #(.NSPR(NSPR)) ppu_inst (
      .clk(clk),
      .rst_n(rst_n),
      .pix_x(pix_x),
      .pix_y(pix_y),
      .cam_x(cam_x),
      .oam_we(oam_we),
      .oam_addr(oam_addr),
      .oam_data(oam_data),
      .hud_count(gem_count),
      .rgb(rgb)
  );

endmodule
