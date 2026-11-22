// =============================================================================
// File: qkd_bb84_sifting_engine.v
// Module: qkd_bb84_sifting_engine
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: BB84 Sifting & Quantum Bit Error Rate (QBER) Evaluation Engine.
//              - Compares Alice transmission bases and Bob measurement bases.
//              - Discards mismatched bases; retains correlated sifted key bits.
//              - Evaluates real-time QBER across test sample subsets.
//              - Asserts security abort if QBER exceeds threshold (Eve detected).
// =============================================================================

`timescale 1ns / 1ps

module qkd_bb84_sifting_engine (
    input  wire                 clk,
    input  wire                 rst_n,

    // Raw Quantum Event Stream
    input  wire                 event_valid,
    input  wire                 alice_basis,      // 0: Rectilinear (+), 1: Diagonal (x)
    input  wire                 alice_bit,        // Alice sent bit value
    input  wire                 bob_basis,        // 0: Rectilinear (+), 1: Diagonal (x)
    input  wire                 bob_bit,          // Bob measured bit value

    // Configuration
    input  wire [7:0]           qber_threshold_pct,// e.g. 11 for 11% theoretical abort limit
    input  wire                 sifting_enable,

    // Sifted Key Output
    output reg                  sifted_valid,
    output reg                  sifted_bit,
    output reg  [15:0]          total_raw_events,
    output reg  [15:0]          total_sifted_bits,
    output reg  [15:0]          error_bits_count,
    output reg  [7:0]           qber_pct,         // Current QBER percentage (0 - 100%)
    output reg                  qber_alarm_abort  // High if Eve eavesdropping detected
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sifted_valid      <= 1'b0;
            sifted_bit        <= 1'b0;
            total_raw_events  <= 16'd0;
            total_sifted_bits <= 16'd0;
            error_bits_count  <= 16'd0;
            qber_pct          <= 8'd0;
            qber_alarm_abort  <= 1'b0;
        end else if (!sifting_enable) begin
            sifted_valid     <= 1'b0;
            qber_alarm_abort <= 1'b0;
        end else begin
            sifted_valid <= 1'b0;

            if (event_valid) begin
                total_raw_events <= total_raw_events + 16'd1;

                // BB84 Basis Match Check
                if (alice_basis == bob_basis) begin
                    sifted_valid      <= 1'b1;
                    sifted_bit        <= bob_bit;
                    total_sifted_bits <= total_sifted_bits + 16'd1;

                    // Error tracking
                    if (alice_bit != bob_bit) begin
                        error_bits_count <= error_bits_count + 16'd1;
                    end

                    // Update QBER percentage
                    if (total_sifted_bits > 16'd10) begin
                        qber_pct <= (error_bits_count * 16'd100) / total_sifted_bits;

                        // Check QBER against security threshold
                        if (((error_bits_count * 16'd100) / total_sifted_bits) > qber_threshold_pct) begin
                            qber_alarm_abort <= 1'b1; // Eve detected! Abort QKD session
                        end
                    end
                end
            end
        end
    end

endmodule
