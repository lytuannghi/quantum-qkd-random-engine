// =============================================================================
// File: quantum_qkd_top.v
// Module: quantum_qkd_top
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: Top-Level SoC Integration of QKD Post-Processing & Entropy Engine:
//              - BB84 Sifting & Real-time QBER Evaluation Engine
//              - Modified Cascade Error Reconciliation Engine
//              - Universal Toeplitz Hashing Privacy Amplification Engine
//              - NIST SP 800-90B Online Continuous Entropy Health Monitor (RCT/APT)
//              - AMBA 3 APB Slave Configuration and Secret Key Interface
// =============================================================================

`timescale 1ns / 1ps

module quantum_qkd_top (
    input  wire                 clk,
    input  wire                 rst_n,

    // Quantum Single-Photon Event Stream
    input  wire                 raw_event_valid,
    input  wire                 alice_basis,
    input  wire                 alice_bit,
    input  wire                 bob_basis,
    input  wire                 bob_bit,

    // Quantum Entropy Source (SPAD Arrival Jitter)
    input  wire                 trng_sample_valid,
    input  wire [3:0]           trng_sample,

    // Classical Public Channel Data for Reconciliation
    input  wire                 alice_block_parity,
    input  wire [63:0]          alice_ref_block,

    // AMBA 3 APB Slave Interface
    input  wire [7:0]           paddr,
    input  wire                 psel,
    input  wire                 penable,
    input  wire                 pwrite,
    input  wire [31:0]          pwdata,
    output wire [31:0]          prdata,
    output wire                 pready,
    output wire                 pslverr,

    // Security Alarms & Interrupts
    output wire                 irq_key_ready,
    output wire                 alarm_eve_detected,
    output wire                 alarm_trng_fault
);

    // Internal Wires
    wire        reg_sifting_enable;
    wire [7:0]  reg_qber_threshold;
    wire        reg_reconcile_start;
    wire        reg_hash_start;

    wire        sifted_valid;
    wire        sifted_bit;
    wire [15:0] total_raw_events;
    wire [15:0] total_sifted_bits;
    wire [15:0] error_bits_count;
    wire [7:0]  qber_pct;
    wire        qber_alarm_abort;

    wire        reconcile_done;
    wire [63:0] key_block_corrected;
    wire [5:0]  error_bit_index;
    wire        error_corrected_flag;

    wire        hash_done;
    wire [31:0] final_secret_key;

    wire        rct_alarm;
    wire        apt_alarm;
    wire        health_test_pass;

    // Sifted Key Shift Buffer (accumulates 64 bits for reconciliation block)
    reg [63:0]  sifted_key_buf;
    reg [5:0]   sifted_count;
    reg         block_ready_for_reconcile;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sifted_key_buf            <= 64'd0;
            sifted_count              <= 6'd0;
            block_ready_for_reconcile <= 1'b0;
        end else begin
            block_ready_for_reconcile <= 1'b0;

            if (sifted_valid) begin
                sifted_key_buf <= {sifted_key_buf[62:0], sifted_bit};
                sifted_count   <= sifted_count + 6'd1;

                if (sifted_count == 6'd63) begin
                    block_ready_for_reconcile <= 1'b1;
                    sifted_count              <= 6'd0;
                end
            end
        end
    end

    // 1. BB84 Sifting & QBER Engine
    qkd_bb84_sifting_engine u_sifting (
        .clk               (clk),
        .rst_n             (rst_n),
        .event_valid       (raw_event_valid),
        .alice_basis       (alice_basis),
        .alice_bit         (alice_bit),
        .bob_basis         (bob_basis),
        .bob_bit           (bob_bit),
        .qber_threshold_pct(reg_qber_threshold),
        .sifting_enable    (reg_sifting_enable),
        .sifted_valid      (sifted_valid),
        .sifted_bit        (sifted_bit),
        .total_raw_events  (total_raw_events),
        .total_sifted_bits (total_sifted_bits),
        .error_bits_count  (error_bits_count),
        .qber_pct          (qber_pct),
        .qber_alarm_abort  (qber_alarm_abort)
    );

    // 2. Modified Cascade Error Reconciliation Engine
    cascade_error_reconciler u_reconciler (
        .clk                 (clk),
        .rst_n               (rst_n),
        .reconcile_start     (block_ready_for_reconcile || reg_reconcile_start),
        .key_block_in        (sifted_key_buf),
        .alice_block_parity  (alice_block_parity),
        .alice_ref_block     (alice_ref_block),
        .reconcile_done      (reconcile_done),
        .key_block_corrected (key_block_corrected),
        .error_bit_index     (error_bit_index),
        .error_corrected_flag(error_corrected_flag)
    );

    // 3. Universal Toeplitz Hashing Privacy Amplification Engine
    toeplitz_privacy_amplification #(
        .IN_BITS(64),
        .OUT_BITS(32)
    ) u_privacy (
        .clk             (clk),
        .rst_n           (rst_n),
        .seed_load       (1'b0),
        .toeplitz_seed   (95'd0),
        .hash_start      (reconcile_done || reg_hash_start),
        .reconciled_key  (key_block_corrected),
        .hash_done       (hash_done),
        .final_secret_key(final_secret_key)
    );

    // 4. NIST SP 800-90B TRNG Continuous Health Monitor
    nist_sp800_90b_health_test u_trng_health (
        .clk                 (clk),
        .rst_n               (rst_n),
        .entropy_sample_valid(trng_sample_valid),
        .entropy_sample      (trng_sample),
        .rct_alarm           (rct_alarm),
        .apt_alarm           (apt_alarm),
        .health_test_pass    (health_test_pass),
        .sample_counter      ()
    );

    // 5. APB3 Slave Register Bank
    qkd_regs_apb u_regs (
        .pclk                 (clk),
        .presetn              (rst_n),
        .paddr                (paddr),
        .psel                 (psel),
        .penable              (penable),
        .pwrite               (pwrite),
        .pwdata               (pwdata),
        .prdata               (prdata),
        .pready               (pready),
        .pslverr              (pslverr),
        .reg_sifting_enable   (reg_sifting_enable),
        .reg_qber_threshold   (reg_qber_threshold),
        .reg_reconcile_start  (reg_reconcile_start),
        .reg_hash_start       (reg_hash_start),
        .status_qber_alarm    (qber_alarm_abort),
        .status_reconcile_done(reconcile_done),
        .status_hash_done     (hash_done),
        .status_trng_pass     (health_test_pass),
        .qber_pct             (qber_pct),
        .total_raw_events     (total_raw_events),
        .total_sifted_bits    (total_sifted_bits),
        .final_secret_key     (final_secret_key),
        .irq_key_ready        (irq_key_ready)
    );

    assign alarm_eve_detected = qber_alarm_abort;
    assign alarm_trng_fault   = rct_alarm | apt_alarm;

endmodule
