//==============================================================================
// nms_top5 — single-pass online Non-Maximum Suppression peak picker
//------------------------------------------------------------------------------
// Consumes a 40x40 grid of 16-bit unsigned pixels in raster order over an
// AXI-Stream-like interface and tracks the 5 strongest, spatially separated
// peaks with no frame buffer (only a 5-slot flip-flop array, 140 bits).
//
// NMS algorithm (applied per incoming pixel (v, x, y) on tvalid):
//   1. Suppression: if any occupied slot j is "near" the new pixel, i.e.
//          dx = |x - slot_x[j]|, dy = |y - slot_y[j]|
//          dx*dx + dy*dy < MIN_DIST_SQ  (64 = 8^2, Euclidean dist < 8.0 px)
//      and slot_val[j] >= v, the new pixel is discarded.
//   2. Eviction: otherwise, every near slot with slot_val[j] < v is cleared
//      (the new, stronger pixel suppresses the old weaker candidates).
//   3. Insertion: the pixel then fills the first empty slot (value == 0), or
//      replaces the minimum-value slot if v exceeds that minimum.
//
// The distance check uses integer arithmetic only: dx, dy are 6-bit absolute
// differences (0..39), so dx*dx + dy*dy fits in 13 bits (max 3042) and the
// squared threshold avoids any square root. No division is used: x/y come
// from a wrapping column counter and a row counter.
//
// Outputs are registered every cycle from a combinational 5-element bubble
// sorting network (10 compare-and-swap) over the *next* slot state, so they
// are final and stable on the same edge that asserts done (one cycle after
// tlast). done stays high until reset.
//==============================================================================

module nms_top5 (
    input  logic        clk,
    input  logic        rst_n,      // active-low synchronous reset
    input  logic        tvalid,
    input  logic [15:0] tdata,
    input  logic        tlast,
    output logic        done,
    output logic [15:0] top_val_0,
    output logic [15:0] top_val_1,
    output logic [15:0] top_val_2,
    output logic [15:0] top_val_3,
    output logic [15:0] top_val_4,
    output logic [5:0]  top_x_0,
    output logic [5:0]  top_x_1,
    output logic [5:0]  top_x_2,
    output logic [5:0]  top_x_3,
    output logic [5:0]  top_x_4,
    output logic [5:0]  top_y_0,
    output logic [5:0]  top_y_1,
    output logic [5:0]  top_y_2,
    output logic [5:0]  top_y_3,
    output logic [5:0]  top_y_4
);

    localparam int GRID_W      = 40;
    localparam int GRID_H      = 40;
    localparam int TOP_N       = 5;
    localparam int MIN_DIST_SQ = 64;   // 8^2 -> Euclidean distance < 8.0 px

    //--------------------------------------------------------------------------
    // State
    //--------------------------------------------------------------------------
    logic [5:0]  x_cnt, y_cnt;                 // raster coordinate counters

    logic [15:0] slot_val [TOP_N];             // value 0 == empty slot
    logic [5:0]  slot_x   [TOP_N];
    logic [5:0]  slot_y   [TOP_N];

    //--------------------------------------------------------------------------
    // Combinational signals
    //--------------------------------------------------------------------------
    logic [15:0] nxt_val [TOP_N];              // slot state after this pixel
    logic [5:0]  nxt_x   [TOP_N];
    logic [5:0]  nxt_y   [TOP_N];

    logic [15:0] srt_val [TOP_N];              // sorted (descending) view
    logic [5:0]  srt_x   [TOP_N];
    logic [5:0]  srt_y   [TOP_N];

    logic        near_slot [TOP_N];            // within MIN_DIST_SQ & occupied
    logic        suppress;

    logic [5:0]  dx, dy;
    logic [12:0] dsq;

    logic        has_empty;
    logic [2:0]  empty_idx;
    logic [2:0]  min_idx;
    logic [15:0] min_val;

    logic [15:0] swp_v;
    logic [5:0]  swp_x, swp_y;

    //--------------------------------------------------------------------------
    // Next-state NMS logic + output sorting network
    //--------------------------------------------------------------------------
    always_comb begin
        // Defaults: hold current state
        for (int j = 0; j < TOP_N; j++) begin
            nxt_val[j]   = slot_val[j];
            nxt_x[j]     = slot_x[j];
            nxt_y[j]     = slot_y[j];
            near_slot[j] = 1'b0;
        end
        suppress  = 1'b0;
        dx        = '0;
        dy        = '0;
        dsq       = '0;
        has_empty = 1'b0;
        empty_idx = '0;
        min_idx   = '0;
        min_val   = '0;
        swp_v     = '0;
        swp_x     = '0;
        swp_y     = '0;

        if (tvalid) begin
            // Pass 1: proximity + suppression check
            for (int j = 0; j < TOP_N; j++) begin
                dx  = (x_cnt >= slot_x[j]) ? (x_cnt - slot_x[j]) : (slot_x[j] - x_cnt);
                dy  = (y_cnt >= slot_y[j]) ? (y_cnt - slot_y[j]) : (slot_y[j] - y_cnt);
                dsq = (13'(dx) * 13'(dx)) + (13'(dy) * 13'(dy));   // <= 3042, fits 13 bits
                near_slot[j] = (slot_val[j] != 16'd0) && (dsq < 13'(MIN_DIST_SQ));
                if (near_slot[j] && (slot_val[j] >= tdata))
                    suppress = 1'b1;
            end

            if (!suppress) begin
                // Pass 2: evict near slots weaker than the new pixel
                for (int j = 0; j < TOP_N; j++)
                    if (near_slot[j] && (slot_val[j] < tdata))
                        nxt_val[j] = 16'd0;

                // Pass 3: insertion (v == 0 is skipped: it is the "empty" code)
                if (tdata != 16'd0) begin
                    // first empty slot (after eviction)
                    for (int j = 0; j < TOP_N; j++)
                        if (!has_empty && (nxt_val[j] == 16'd0)) begin
                            has_empty = 1'b1;
                            empty_idx = 3'(j);
                        end

                    // minimum-value slot
                    min_val = nxt_val[0];
                    for (int j = 1; j < TOP_N; j++)
                        if (nxt_val[j] < min_val) begin
                            min_val = nxt_val[j];
                            min_idx = 3'(j);
                        end

                    if (has_empty) begin
                        nxt_val[empty_idx] = tdata;
                        nxt_x[empty_idx]   = x_cnt;
                        nxt_y[empty_idx]   = y_cnt;
                    end
                    else if (tdata > min_val) begin
                        nxt_val[min_idx] = tdata;
                        nxt_x[min_idx]   = x_cnt;
                        nxt_y[min_idx]   = y_cnt;
                    end
                end
            end
        end

        // Bubble sorting network (10 compare-and-swap), descending by value.
        // Sorting nxt_* means output registers are final on the same edge
        // that processes tlast / asserts done.
        for (int j = 0; j < TOP_N; j++) begin
            srt_val[j] = nxt_val[j];
            srt_x[j]   = nxt_x[j];
            srt_y[j]   = nxt_y[j];
        end
        for (int a = 0; a < TOP_N-1; a++) begin
            for (int b = 0; b < TOP_N-1-a; b++) begin
                if (srt_val[b] < srt_val[b+1]) begin
                    swp_v        = srt_val[b];
                    srt_val[b]   = srt_val[b+1];
                    srt_val[b+1] = swp_v;
                    swp_x        = srt_x[b];
                    srt_x[b]     = srt_x[b+1];
                    srt_x[b+1]   = swp_x;
                    swp_y        = srt_y[b];
                    srt_y[b]     = srt_y[b+1];
                    srt_y[b+1]   = swp_y;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential state
    //--------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            x_cnt <= '0;
            y_cnt <= '0;
            done  <= 1'b0;
            for (int j = 0; j < TOP_N; j++) begin
                slot_val[j] <= '0;
                slot_x[j]   <= '0;
                slot_y[j]   <= '0;
            end
            top_val_0 <= '0; top_val_1 <= '0; top_val_2 <= '0;
            top_val_3 <= '0; top_val_4 <= '0;
            top_x_0 <= '0; top_x_1 <= '0; top_x_2 <= '0;
            top_x_3 <= '0; top_x_4 <= '0;
            top_y_0 <= '0; top_y_1 <= '0; top_y_2 <= '0;
            top_y_3 <= '0; top_y_4 <= '0;
        end
        else begin
            // Candidate slots
            for (int j = 0; j < TOP_N; j++) begin
                slot_val[j] <= nxt_val[j];
                slot_x[j]   <= nxt_x[j];
                slot_y[j]   <= nxt_y[j];
            end

            // Registered, sorted outputs (stable once the stream ends)
            top_val_0 <= srt_val[0]; top_x_0 <= srt_x[0]; top_y_0 <= srt_y[0];
            top_val_1 <= srt_val[1]; top_x_1 <= srt_x[1]; top_y_1 <= srt_y[1];
            top_val_2 <= srt_val[2]; top_x_2 <= srt_x[2]; top_y_2 <= srt_y[2];
            top_val_3 <= srt_val[3]; top_x_3 <= srt_x[3]; top_y_3 <= srt_y[3];
            top_val_4 <= srt_val[4]; top_x_4 <= srt_x[4]; top_y_4 <= srt_y[4];

            // Raster counters: x wraps at GRID_W-1, y increments on wrap
            if (tvalid) begin
                if (x_cnt == 6'(GRID_W-1)) begin
                    x_cnt <= '0;
                    y_cnt <= (y_cnt == 6'(GRID_H-1)) ? '0 : (y_cnt + 6'd1);
                end
                else begin
                    x_cnt <= x_cnt + 6'd1;
                end

                if (tlast)
                    done <= 1'b1;   // pulses high one cycle after tlast, holds until reset
            end
        end
    end

endmodule
