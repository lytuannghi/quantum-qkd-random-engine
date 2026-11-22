// =============================================================================
// File: nist_sp800_90b_health_test.v
// Module: nist_sp800_90b_health_test
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: NIST SP 800-90B Online Continuous Health Tests for Quantum Entropy Sources:
//              1. Repetition Count Test (RCT): Triggers alarm if single output persists
//                 for C consecutive samples (cutoff C = 16).
//              2. Adaptive Proportion Test (APT): Evaluates window of W = 512 samples.
//                 Triggers alarm if identical sample count exceeds threshold (cutoff C = 325).
// =============================================================================

`timescale 1ns / 1ps

module nist_sp800_90b_health_test (
    input  wire                 clk,
    input  wire                 rst_n,

    // Entropy Sample Stream from Quantum Detector
    input  wire                 entropy_sample_valid,
    input  wire [3:0]           entropy_sample,

    // Health Test Alarms
    output reg                  rct_alarm,       // Repetition Count Test Failure
    output reg                  apt_alarm,       // Adaptive Proportion Test Failure
    output reg                  health_test_pass,// 1: Clean entropy, 0: Failed
    output reg  [9:0]           sample_counter
);

    // RCT Parameters
    localparam RCT_CUTOFF = 5'd16;
    reg [3:0]  rct_prev_sample;
    reg [4:0]  rct_count;

    // APT Parameters
    localparam APT_WINDOW = 10'd512;
    localparam APT_CUTOFF = 10'd325;
    reg [3:0]  apt_target_sample;
    reg [9:0]  apt_count;
    reg [9:0]  window_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rct_prev_sample   <= 4'd0;
            rct_count         <= 5'd1;
            rct_alarm         <= 1'b0;
            apt_target_sample <= 4'd0;
            apt_count         <= 10'd0;
            window_cnt        <= 10'd0;
            apt_alarm         <= 1'b0;
            health_test_pass  <= 1'b1;
            sample_counter    <= 10'd0;
        end else if (entropy_sample_valid) begin
            sample_counter <= sample_counter + 10'd1;

            // 1. Repetition Count Test (RCT)
            if (entropy_sample == rct_prev_sample) begin
                if (rct_count >= RCT_CUTOFF) begin
                    rct_alarm        <= 1'b1;
                    health_test_pass <= 1'b0;
                end else begin
                    rct_count <= rct_count + 5'd1;
                end
            end else begin
                rct_prev_sample <= entropy_sample;
                rct_count       <= 5'd1;
            end

            // 2. Adaptive Proportion Test (APT)
            if (window_cnt == 10'd0) begin
                // Start of window
                apt_target_sample <= entropy_sample;
                apt_count         <= 10'd1;
                window_cnt        <= 10'd1;
            end else begin
                if (entropy_sample == apt_target_sample) begin
                    apt_count <= apt_count + 10'd1;
                end

                if (window_cnt == APT_WINDOW - 1) begin
                    // End of window: Check threshold
                    if (apt_count > APT_CUTOFF) begin
                        apt_alarm        <= 1'b1;
                        health_test_pass <= 1'b0;
                    end else begin
                        apt_alarm        <= 1'b0;
                        health_test_pass <= 1'b1;
                    end
                    window_cnt <= 10'd0;
                end else begin
                    window_cnt <= window_cnt + 10'd1;
                end
            end
        end
    end

endmodule
