// =============================================================================
// File: cascade_error_reconciler.v
// Module: cascade_error_reconciler
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: Binary-Bisection Cascade Information Reconciliation Engine.
//              - Receives 64-bit Bob sifted key block and Alice block parity.
//              - On parity mismatch, performs a 6-stage binary bisection parity
//                search over [0..63] against Alice's classical parity oracle to
//                isolate and flip the exact single-bit error index.
// =============================================================================

`timescale 1ns / 1ps

module cascade_error_reconciler (
    input  wire                 clk,
    input  wire                 rst_n,

    // Sifted Key Block Input (64-bit block)
    input  wire                 reconcile_start,
    input  wire [63:0]          key_block_in,
    input  wire                 alice_block_parity, // Even parity bit sent over public channel
    input  wire [63:0]          alice_ref_block,    // Alice classical block for bisection sub-parity

    // Reconciled Output
    output reg                  reconcile_done,
    output reg  [63:0]          key_block_corrected,
    output reg  [5:0]           error_bit_index,
    output reg                  error_corrected_flag
);

    localparam ST_IDLE    = 2'd0;
    localparam ST_BISECT  = 2'd1;
    localparam ST_CORRECT = 2'd2;

    reg [1:0]  state;
    reg [2:0]  stage;
    reg [5:0]  search_lo;
    reg [5:0]  search_hi;
    reg [63:0] work_block;

    wire [6:0] sum_idx = {1'b0, search_lo} + {1'b0, search_hi};
    wire [5:0] mid_idx = sum_idx[6:1];

    reg [63:0] lo_mask;
    integer    b;
    always @(*) begin
        for (b = 0; b < 64; b = b + 1) begin
            lo_mask[b] = (b >= search_lo && b <= mid_idx) ? 1'b1 : 1'b0;
        end
    end

    wire bob_lo_parity   = ^(work_block & lo_mask);
    wire alice_lo_parity = ^(alice_ref_block & lo_mask);
    wire lo_mismatch     = (bob_lo_parity != alice_lo_parity);

    wire bob_total_parity = ^key_block_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reconcile_done       <= 1'b0;
            key_block_corrected  <= 64'd0;
            error_bit_index      <= 6'd0;
            error_corrected_flag <= 1'b0;
            state                <= ST_IDLE;
            stage                <= 3'd0;
            search_lo            <= 6'd0;
            search_hi            <= 6'd63;
            work_block           <= 64'd0;
        end else begin
            reconcile_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (reconcile_start) begin
                        work_block           <= key_block_in;
                        error_corrected_flag <= 1'b0;
                        if (bob_total_parity == alice_block_parity) begin
                            key_block_corrected <= key_block_in;
                            error_bit_index     <= 6'd0;
                            reconcile_done      <= 1'b1;
                        end else begin
                            search_lo <= 6'd0;
                            search_hi <= 6'd63;
                            stage     <= 3'd0;
                            state     <= ST_BISECT;
                        end
                    end
                end

                ST_BISECT: begin
                    if (stage == 3'd5) begin
                        state <= ST_CORRECT;
                    end else begin
                        if (lo_mismatch)
                            search_hi <= mid_idx;
                        else
                            search_lo <= mid_idx + 6'd1;
                        stage <= stage + 3'd1;
                    end
                end

                ST_CORRECT: begin
                    if (lo_mismatch) begin
                        error_bit_index     <= search_lo;
                        key_block_corrected <= work_block ^ (64'd1 << search_lo);
                    end else begin
                        error_bit_index     <= search_hi;
                        key_block_corrected <= work_block ^ (64'd1 << search_hi);
                    end
                    error_corrected_flag <= 1'b1;
                    reconcile_done       <= 1'b1;
                    state                <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
