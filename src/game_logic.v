/*
 * Game logic for the SunnyLand platformer (runs once per frame, during vblank).
 *
 * Coordinates are unsigned. World x is 0..959. Every y value uses
 * "yo" = world y + 64, so a sprite can be up to 64 px above the screen top
 * without negative numbers. The visible world is yo 64..303.
 *
 * Player:  32x32 sprite at (px, yo), hitbox x+9..x+22, y+12..y+31 (14x20).
 *          Position y is fixed point: pyf = yo * 16 + fraction.
 *          vy is 8-bit two's complement in 1/16 px per frame (positive = down).
 *
 * Per frame, a small state machine runs:
 *   S_X   : move left/right, stop at walls (snap to tile edge)
 *   S_GND : check whether the player stands on solid ground
 *   S_Y   : jump / gravity / move up or down, land on floors, bump ceilings
 *   S_INT : enemies, gems, pits, goal, camera, animation
 */

`default_nettype none

// Collision map: 60x15 tiles, 1 = solid. Three probes = three lookups per cycle.
module collision_map (
    input  wire [9:0] x0, input wire [9:0] yo0, output wire hit0,
    input  wire [9:0] x1, input wire [9:0] yo1, output wire hit1,
    input  wire [9:0] x2, input wire [9:0] yo2, output wire hit2
);
  reg solid_rom [0:899];
  initial $readmemh("../used_art/solid.mem", solid_rom);

  // Outside the map (above the sky, below the bottom, past the right edge) is air.
  wire [9:0] y0 = yo0 - 10'd64;
  wire [9:0] y1 = yo1 - 10'd64;
  wire [9:0] y2 = yo2 - 10'd64;
  wire in0 = (yo0 >= 10'd64) && (yo0 < 10'd304) && (x0 < 10'd960);
  wire in1 = (yo1 >= 10'd64) && (yo1 < 10'd304) && (x1 < 10'd960);
  wire in2 = (yo2 >= 10'd64) && (yo2 < 10'd304) && (x2 < 10'd960);
  wire [9:0] a0 = in0 ? y0[7:4] * 10'd60 + {4'd0, x0[9:4]} : 10'd0;
  wire [9:0] a1 = in1 ? y1[7:4] * 10'd60 + {4'd0, x1[9:4]} : 10'd0;
  wire [9:0] a2 = in2 ? y2[7:4] * 10'd60 + {4'd0, x2[9:4]} : 10'd0;
  assign hit0 = in0 && solid_rom[a0];
  assign hit1 = in1 && solid_rom[a1];
  assign hit2 = in2 && solid_rom[a2];
endmodule


// Opossum: walks between X_MIN and X_MAX on a floor; stomp it from above.
module enemy #(
    parameter X_MIN = 0,
    parameter X_MAX = 100,
    parameter YO    = 224        // sprite top (yo coordinates)
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       tick,
    input  wire [9:0] pl, input wire [9:0] pr,   // player hitbox left/right
    input  wire [9:0] pt, input wire [9:0] pb,   // player hitbox top/bottom (yo)
    input  wire       player_active,
    input  wire       player_falling,
    output reg  [9:0] x,
    output reg        dir_right,
    output reg        alive,
    output wire       stomp,
    output wire       hit
);
  // Enemy hitbox: x+4..x+27, y+14..y+31
  wire overlap = alive && player_active
                 && (pl <= x + 10'd27) && (pr >= x + 10'd4)
                 && (pt <= YO + 31) && (pb >= YO + 14);
  assign stomp = overlap && player_falling && (pb <= YO + 22);
  assign hit   = overlap && !stomp;

  always @(posedge clk) begin
    if (reset) begin
      x         <= X_MIN;
      dir_right <= 1'b1;
      alive     <= 1'b1;
    end else if (tick) begin
      if (stomp) begin
        alive <= 1'b0;
      end else if (alive) begin
        if (dir_right) begin
          if (x >= X_MAX) dir_right <= 1'b0;
          else            x <= x + 10'd1;
        end else begin
          if (x <= X_MIN) dir_right <= 1'b1;
          else            x <= x - 10'd1;
        end
      end
    end
  end
endmodule


// Gem: disappears when the player touches it.
module pickup #(
    parameter X  = 0,
    parameter YO = 0
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       tick,
    input  wire [9:0] pl, input wire [9:0] pr,
    input  wire [9:0] pt, input wire [9:0] pb,
    input  wire       player_active,
    output reg        taken
);
  // Gem pixels: x+9..x+21, y+11..y+21
  wire overlap = !taken && player_active
                 && (pl <= X + 21) && (pr >= X + 9)
                 && (pt <= YO + 21) && (pb >= YO + 11);
  always @(posedge clk) begin
    if (reset)                taken <= 1'b0;
    else if (tick && overlap) taken <= 1'b1;
  end
endmodule


module game_logic #(
    parameter NSPR = 11
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_tick,   // one pulse per frame, at the start of vblank
    input  wire               btn_left,
    input  wire               btn_right,
    input  wire               btn_jump,
    input  wire               btn_start,
    output reg  [9:0]         cam_x,
    output wire               oam_we,       // OAM write port into the PPU
    output wire [3:0]         oam_addr,
    output reg  [26:0]        oam_data,
    output wire [2:0]         gem_count
);

  // ------------------------------------------------------------ tuning
  localparam [9:0] SPEED   = 10'd2;     // px per frame
  localparam [7:0] GRAV    = 8'd5;      // 1/16 px per frame^2
  localparam [7:0] JUMP_V  = 8'd96;     // jump take-off speed (~57 px high)
  localparam [7:0] CUT_V   = 8'd32;     // max upward speed after jump is released
  localparam [7:0] MAX_FALL= 8'd112;    // 7 px per frame
  localparam [7:0] BOUNCE  = 8'd64;     // bounce after stomping an enemy

  localparam [9:0] HB_L = 10'd9, HB_R = 10'd22, HB_T = 10'd12, HB_B = 10'd31;
  localparam [9:0] START_X  = 10'd32;
  localparam [9:0] START_YO = 10'd224;  // feet on the ground row (world y 160)
  localparam [9:0] GOAL_X   = 10'd912;  // gate, column 57 (reach it on the ground row)
  localparam [9:0] PIT_YO   = 10'd304;  // fell below the screen

  localparam [1:0] M_PLAY = 2'd0, M_DIE = 2'd1, M_WIN = 2'd2;
  localparam [2:0] S_IDLE = 3'd0, S_X = 3'd1, S_GND = 3'd2, S_Y = 3'd3, S_INT = 3'd4,
                   S_OAM = 3'd5;

  // ------------------------------------------------------------ state
  reg [2:0]  state;
  reg [1:0]  mode;
  reg [9:0]  px;
  reg [13:0] pyf;
  reg [7:0]  vy;
  reg        facing_left;
  reg        on_ground;
  reg        moving;
  reg [6:0]  die_timer;
  reg        jump_prev, start_prev;
  reg        level_reset;
  reg [7:0]  frame_cnt;
  reg [2:0]  run_f, op_f, gem_f;     // animation frames
  reg [3:0]  oam_idx;                // OAM entry being written in S_OAM

  wire [9:0] yo = pyf[13:4];

  // ------------------------------------------------- horizontal movement
  wire want_r = (mode == M_PLAY) && btn_right && !btn_left;
  wire want_l = (mode == M_PLAY) && btn_left && !btn_right;

  wire [9:0] nx = want_r ? ((px > 10'd928 - SPEED) ? 10'd928 : px + SPEED)
                : want_l ? ((px < SPEED) ? 10'd0 : px - SPEED)
                : px;
  wire [9:0] lead_x = want_r ? nx + HB_R : nx + HB_L;

  // --------------------------------------------------- vertical movement
  wire jump_edge  = btn_jump && !jump_prev;
  wire start_jump = (mode == M_PLAY) && on_ground && jump_edge;
  wire grounded   = (mode != M_DIE) && on_ground && !start_jump;

  wire [7:0] vy_a = start_jump ? (8'd0 - JUMP_V) : vy;
  // Released the button while going up fast: cut the jump short (variable height).
  wire       cut  = (mode == M_PLAY) && !btn_jump && vy_a[7] && (vy_a < 8'd0 - CUT_V);
  wire [7:0] vy_b = cut ? (8'd0 - CUT_V) : vy_a;
  wire [7:0] vy_c = (!vy_b[7] && vy_b >= MAX_FALL - GRAV) ? MAX_FALL : vy_b + GRAV;
  wire [7:0] vy_n = grounded ? 8'd0 : vy_c;

  wire [13:0] nyf    = pyf + {{6{vy_n[7]}}, vy_n};
  wire [9:0]  nyo    = nyf[13:4];
  wire        rising = vy_n[7];
  wire [9:0]  edge_y = rising ? nyo + HB_T : nyo + HB_B;

  // ------------------------------------------------------ collision probes
  reg  [9:0] cx0, cy0, cx1, cy1, cx2, cy2;
  wire       ch0, ch1, ch2;

  always @(*) begin
    case (state)
      S_X: begin
        cx0 = lead_x; cy0 = yo + HB_T;
        cx1 = lead_x; cy1 = yo + 10'd22;
        cx2 = lead_x; cy2 = yo + HB_B;
      end
      S_GND: begin
        cx0 = px + HB_L; cy0 = yo + HB_B + 10'd1;
        cx1 = px + HB_R; cy1 = yo + HB_B + 10'd1;
        cx2 = px + HB_R; cy2 = yo + HB_B + 10'd1;
      end
      default: begin  // S_Y
        cx0 = px + HB_L; cy0 = edge_y;
        cx1 = px + HB_R; cy1 = edge_y;
        cx2 = px + HB_R; cy2 = edge_y;
      end
    endcase
  end

  collision_map cmap (
      .x0(cx0), .yo0(cy0), .hit0(ch0),
      .x1(cx1), .yo1(cy1), .hit1(ch1),
      .x2(cx2), .yo2(cy2), .hit2(ch2)
  );

  wire wall_hit = ch0 || ch1 || ch2;
  wire [9:0] tile_edge_x = {lead_x[9:4], 4'd0};
  wire [9:0] tile_edge_y = {edge_y[9:4], 4'd0};

  // ---------------------------------------------------- enemies and gems
  wire [9:0] pl = px + HB_L;
  wire [9:0] pr = px + HB_R;
  wire [9:0] pt = yo + HB_T;
  wire [9:0] pb = yo + HB_B;
  wire player_active  = (mode == M_PLAY);
  wire player_falling = !vy[7] && (vy != 8'd0);
  wire obj_tick  = (state == S_INT);
  wire obj_reset = !rst_n || level_reset;

  localparam NEN = 4;
  localparam NGEM = 6;
  wire [NEN*10-1:0] en_x;
  wire [NEN-1:0] en_right, en_alive, en_stomp, en_hit;
  wire [NGEM-1:0] gem_taken;

  // Opossum patrols (x range) on the ground row: one per area.
  enemy #(.X_MIN(120), .X_MAX(200), .YO(224)) en0 (clk, obj_reset, obj_tick, pl, pr, pt, pb,
      player_active, player_falling, en_x[0 +: 10], en_right[0], en_alive[0], en_stomp[0], en_hit[0]);
  enemy #(.X_MIN(420), .X_MAX(540), .YO(224)) en1 (clk, obj_reset, obj_tick, pl, pr, pt, pb,
      player_active, player_falling, en_x[10 +: 10], en_right[1], en_alive[1], en_stomp[1], en_hit[1]);
  enemy #(.X_MIN(650), .X_MAX(715), .YO(224)) en2 (clk, obj_reset, obj_tick, pl, pr, pt, pb,
      player_active, player_falling, en_x[20 +: 10], en_right[2], en_alive[2], en_stomp[2], en_hit[2]);
  enemy #(.X_MIN(805), .X_MAX(870), .YO(224)) en3 (clk, obj_reset, obj_tick, pl, pr, pt, pb,
      player_active, player_falling, en_x[30 +: 10], en_right[3], en_alive[3], en_stomp[3], en_hit[3]);

  // Gems: above the start, over the first pit, on each floating platform, on the cave roof.
  pickup #(.X(80),  .YO(214)) gem0 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[0]);
  pickup #(.X(240), .YO(190)) gem1 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[1]);
  pickup #(.X(360), .YO(200)) gem2 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[2]);
  pickup #(.X(456), .YO(168)) gem3 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[3]);
  pickup #(.X(568), .YO(136)) gem4 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[4]);
  pickup #(.X(760), .YO(104)) gem5 (clk, obj_reset, obj_tick, pl, pr, pt, pb, player_active, gem_taken[5]);

  wire any_stomp = |en_stomp;
  wire any_hit   = |en_hit;

  assign gem_count = {2'd0, gem_taken[0]} + {2'd0, gem_taken[1]} + {2'd0, gem_taken[2]}
                   + {2'd0, gem_taken[3]} + {2'd0, gem_taken[4]} + {2'd0, gem_taken[5]};

  // Camera follows the player, clamped to the level (0..640).
  wire [9:0] cam_target = (px < 10'd144) ? 10'd0
                        : (px > 10'd784) ? 10'd640
                        : px - 10'd144;

  // --------------------------------------------------------- frame update
  always @(posedge clk) begin
    if (!rst_n || level_reset) begin
      state       <= S_IDLE;
      mode        <= M_PLAY;
      px          <= START_X;
      pyf         <= {START_YO, 4'd0};
      vy          <= 8'd0;
      facing_left <= 1'b0;
      on_ground   <= 1'b1;
      moving      <= 1'b0;
      die_timer   <= 7'd0;
      cam_x       <= 10'd0;
      level_reset <= 1'b0;
      oam_idx     <= 4'd0;
      if (!rst_n) begin
        jump_prev  <= 1'b0;
        start_prev <= 1'b0;
        frame_cnt  <= 8'd0;
        run_f      <= 3'd0;
        op_f       <= 3'd0;
        gem_f      <= 3'd0;
      end
    end else begin
      case (state)
        S_IDLE: if (frame_tick) state <= S_X;

        S_X: begin
          moving <= want_r || want_l;
          if (want_r) facing_left <= 1'b0;
          if (want_l) facing_left <= 1'b1;
          if ((want_r || want_l) && wall_hit)
            px <= want_r ? tile_edge_x - (HB_R + 10'd1) : tile_edge_x + (10'd16 - HB_L);
          else
            px <= nx;
          state <= S_GND;
        end

        S_GND: begin
          on_ground <= (mode != M_DIE) && (ch0 || ch1);
          state <= S_Y;
        end

        S_Y: begin
          if (mode != M_DIE && vy_n != 8'd0 && (ch0 || ch1)) begin
            // Landed on a floor or bumped a ceiling: snap to the tile edge.
            pyf <= rising ? {tile_edge_y + (10'd16 - HB_T), 4'd0}
                          : {tile_edge_y - (HB_B + 10'd1), 4'd0};
            vy  <= 8'd0;
          end else if (mode == M_DIE && yo >= 10'd400) begin
            vy  <= 8'd0;                            // far below the screen: stop falling
          end else begin
            pyf <= nyf;
            vy  <= vy_n;
          end
          state <= S_INT;
        end

        S_INT: begin
          state      <= S_OAM;
          oam_idx    <= 4'd0;
          jump_prev  <= btn_jump;
          start_prev <= btn_start;

          // Animation
          frame_cnt <= frame_cnt + 8'd1;
          if (frame_cnt[1:0] == 2'd3) run_f <= (run_f == 3'd5) ? 3'd0 : run_f + 3'd1;
          if (frame_cnt[2:0] == 3'd7) op_f  <= (op_f  == 3'd5) ? 3'd0 : op_f  + 3'd1;
          if (frame_cnt[2:0] == 3'd3) gem_f <= (gem_f == 3'd4) ? 3'd0 : gem_f + 3'd1;

          if (mode == M_PLAY) cam_x <= cam_target;

          if (btn_start && !start_prev) begin
            level_reset <= 1'b1;                    // restart the level
          end else if (mode == M_PLAY) begin
            if (any_stomp) begin
              vy <= 8'd0 - BOUNCE;                  // bounce off the enemy
            end else if (any_hit) begin
              mode <= M_DIE;                        // touched an enemy: hop and fall
              vy   <= 8'd0 - JUMP_V;
            end else if (yo >= PIT_YO && yo < 10'd960) begin
              mode <= M_DIE;                        // fell into a pit
            end else if (pr >= GOAL_X && on_ground && yo == START_YO) begin
              mode <= M_WIN;                        // reached the gate
            end
          end else if (mode == M_DIE) begin
            die_timer <= die_timer + 7'd1;
            if (die_timer == 7'd100) level_reset <= 1'b1;
          end
        end

        // Copy one sprite entry per clock into the PPU's OAM.
        S_OAM: begin
          oam_idx <= oam_idx + 4'd1;
          if (oam_idx == NSPR - 1) state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------- OAM
  // Player animation frame
  reg [4:0] player_frame;
  always @(*) begin
    if (mode == M_WIN)        player_frame = 5'd13;              // victory
    else if (mode == M_DIE)   player_frame = 5'd12;              // hurt
    else if (!on_ground)      player_frame = vy[7] ? 5'd10 : 5'd11;  // jump up / fall
    else if (moving)          player_frame = 5'd4 + {2'd0, run_f};   // run
    else                      player_frame = {3'd0, frame_cnt[4:3]}; // idle
  end

  // Keep the dying player drawn only while it is near the screen.
  wire player_en = (yo < 10'd320);
  wire [4:0] enemy_frame = 5'd14 + {2'd0, op_f};
  wire [4:0] gem_frame   = 5'd20 + {2'd0, gem_f};

  // Entry format: {enable, flip, frame[4:0], yo[9:0], x[9:0]}
  // Opossum art faces left, so it is flipped while walking right.
  assign oam_we   = (state == S_OAM);
  assign oam_addr = oam_idx;

  always @(*) begin
    case (oam_idx)
      4'd0:    oam_data = {player_en,     facing_left, player_frame, yo,      px};
      4'd1:    oam_data = {en_alive[0],   en_right[0], enemy_frame,  10'd224, en_x[0 +: 10]};
      4'd2:    oam_data = {en_alive[1],   en_right[1], enemy_frame,  10'd224, en_x[10 +: 10]};
      4'd3:    oam_data = {en_alive[2],   en_right[2], enemy_frame,  10'd224, en_x[20 +: 10]};
      4'd4:    oam_data = {en_alive[3],   en_right[3], enemy_frame,  10'd224, en_x[30 +: 10]};
      4'd5:    oam_data = {!gem_taken[0], 1'b0,        gem_frame,    10'd214, 10'd80};
      4'd6:    oam_data = {!gem_taken[1], 1'b0,        gem_frame,    10'd190, 10'd240};
      4'd7:    oam_data = {!gem_taken[2], 1'b0,        gem_frame,    10'd200, 10'd360};
      4'd8:    oam_data = {!gem_taken[3], 1'b0,        gem_frame,    10'd168, 10'd456};
      4'd9:    oam_data = {!gem_taken[4], 1'b0,        gem_frame,    10'd136, 10'd568};
      4'd10:   oam_data = {!gem_taken[5], 1'b0,        gem_frame,    10'd104, 10'd760};
      default: oam_data = 27'd0;
    endcase
  end

endmodule
