/*
* Copyright (c) 2025 Uri Shaked
* SPDX-License-Identifier: Apache-2.0
*/

`default_nettype none

module tt_um_bg_scrolling (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in[7], ui_in[4:0], uio_in};

  // VGA signals
  wire hsync;
  wire vsync;
  reg [1:0] R;
  reg [1:0] G;
  reg [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // Tiny VGA Pmod
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // Gamepad Pmod
  wire inp_b, inp_y, inp_select, inp_start, inp_up, inp_down, inp_left, inp_right, inp_a, inp_x, inp_l, inp_r;

  gamepad_pmod_single driver (
      // Inputs:
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      // Outputs:
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


  // Initial background and tile rom
  reg [6:0] back_rom [0:92159];
  reg [6:0] tile_rom [0:147199];
  reg [9:0] map_rom [0:899];

  initial begin
    $readmemh("../used_art/back.mem", back_rom);
    $readmemh("../used_art/tileset.mem", tile_rom);
    $readmemh("../used_art/map.mem", map_rom);
  end

  // Render background
  wire [9:0] fore_x_one = (pix_x + 1) % 800;
  wire [9:0] fore_y_one = (pix_x < 799) ? pix_y : (pix_y + 1) % 525;
  reg [6:0] color_bg;

  // Render tile
  wire [9:0] fore_x_two = (pix_x + 2) % 800;
  wire [9:0] fore_y_two = (pix_x < 798) ? pix_y : (pix_y + 1) % 525;
  wire [9:0] world_x = (fore_x_two >> 1) + scroll_offset;
  wire [9:0] world_y = fore_y_two >> 1;
  wire [3:0] tile_pixel_x = (fore_x_one >> 1) + scroll_offset;
  wire [3:0] tile_pixel_y = fore_y_one >> 1;
  reg [9:0] scroll_offset;
  reg [9:0] tile_map;
  reg [6:0] tile_color;

  always @(posedge clk) begin
    if(!rst_n) begin
      {R, G, B} <= 6'b0;
      color_bg <= 6'b0;
      tile_map <= 10'b0;
      tile_color <= 6'b0;
    end else begin
      // Get color from background img
      if(fore_x_one < 640 && fore_y_one < 480) begin
        color_bg <= back_rom[(fore_y_one >> 1) * 384 + (((fore_x_one >> 1) + (scroll_offset >> 1)) % 384)];
        if(pix_y < 224) begin
          // Seperate sky from sea
          color_bg <= back_rom[(fore_y_one >> 1) * 384 + (((fore_x_one >> 1) + (scroll_offset >> 2)) % 384)];
        end
      end
      
      // Get color from tile
      if(fore_x_two < 640 && fore_y_two < 480) begin
        tile_map <= map_rom[(world_y >> 4) * 60 + (world_x >> 4)];
      end
      tile_color <= tile_rom[tile_map * 256 + tile_pixel_y * 16 + tile_pixel_x];
      
      // Drawing scene
      if(pix_x < 640 && pix_y < 480) begin
        // In drawing region
        //  Draw background
        if(color_bg[6]) begin
          {R, G, B} <= tile_color[6] ? tile_color[5:0] : color_bg[5:0];
        end else begin
          {R, G, B} <= 6'b0;
        end
        
        //  Draw tile
        
      end else begin
        // Out drawing region
        {R, G, B} <= 6'b0;
      end
    end
  end
  
  always @(posedge vsync) begin
    if(!rst_n) begin
      scroll_offset <= 10'b0;
    end else begin
      if(inp_right && scroll_offset < 10'd640) begin
        scroll_offset <= scroll_offset + 1;
      end

      if(inp_left && scroll_offset > 10'd0) begin
        scroll_offset <= scroll_offset - 1;
      end
    end
  end


endmodule
