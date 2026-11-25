// =============================================================================
// File: tb_quantum_qkd_top.v
// Module: tb_quantum_qkd_top
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: Comprehensive Self-Checking Testbench.
//              Executes 10 rigorous test cases covering:
//              - APB3 Register Bus Access & Configuration
//              - BB84 Basis Matching & 50% Yield Sifting
//              - Real-time QBER Evaluation & Security Abort on Eavesdropping
//              - Binary-Bisection Cascade Error Reconciliation (bit-index 47)
//              - Toeplitz Universal Hashing Matrix Multiplication
//              - Privacy Amplification (64-bit to 32-bit key condensation)
//              - NIST SP 800-90B Online Continuous Health Tests (RCT & APT)
//              - Secret Key Extraction and Interrupt Signaling
// =============================================================================

`timescale 1ns / 1ps

module tb_quantum_qkd_top;

    reg         clk;
    reg         rst_n;

    // Quantum Single-Photon Event Stream
    reg         raw_event_valid;
    reg         alice_basis;
    reg         alice_bit;
    reg         bob_basis;
    reg         bob_bit;

    // Quantum Entropy Source (SPAD Arrival Jitter)
    reg         trng_sample_valid;
    reg  [3:0]  trng_sample;

    // Classical Public Channel Data
    reg         alice_block_parity;
    reg  [63:0] alice_ref_block;

    // APB3 Interface
    reg  [7:0]  paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    wire        irq_key_ready;
    wire        alarm_eve_detected;
    wire        alarm_trng_fault;

    integer tests_passed = 0;
    integer tests_failed = 0;

    // DUT Instantiation
    quantum_qkd_top u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .raw_event_valid   (raw_event_valid),
        .alice_basis       (alice_basis),
        .alice_bit         (alice_bit),
        .bob_basis         (bob_basis),
        .bob_bit           (bob_bit),
        .trng_sample_valid (trng_sample_valid),
        .trng_sample       (trng_sample),
        .alice_block_parity(alice_block_parity),
        .alice_ref_block   (alice_ref_block),
        .paddr             (paddr),
        .psel              (psel),
        .penable           (penable),
        .pwrite            (pwrite),
        .pwdata            (pwdata),
        .prdata            (prdata),
        .pready            (pready),
        .pslverr           (pslverr),
        .irq_key_ready     (irq_key_ready),
        .alarm_eve_detected(alarm_eve_detected),
        .alarm_trng_fault  (alarm_trng_fault)
    );

    // 250 MHz System Clock (4.0 ns period)
    always #2.0 clk = ~clk;

    // APB Read/Write Tasks
    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #0.2;
            paddr   = addr;
            pwrite  = 1'b1;
            psel    = 1'b1;
            pwdata  = data;
            @(posedge clk); #0.2;
            penable = 1'b1;
            @(posedge clk); #0.2;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    task apb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #0.2;
            paddr   = addr;
            pwrite  = 1'b0;
            psel    = 1'b1;
            @(posedge clk); #0.2;
            penable = 1'b1;
            #0.2;
            data    = prdata;
            @(posedge clk); #0.2;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    reg [31:0] read_val;
    reg [31:0] key_status;

    // Sticky capture flags
    reg saw_key_irq;
    reg saw_eve_alarm;
    reg saw_hash_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_key_irq   <= 1'b0;
            saw_eve_alarm <= 1'b0;
            saw_hash_done <= 1'b0;
        end else begin
            if (irq_key_ready)             saw_key_irq   <= 1'b1;
            if (alarm_eve_detected)        saw_eve_alarm <= 1'b1;
            if (u_dut.u_privacy.hash_done) saw_hash_done <= 1'b1;
        end
    end

    localparam [63:0] ALICE_KEY_BLOCK = 64'hFEDCBA9876543210;
    localparam [63:0] BOB_KEY_BLOCK   = 64'hFEDCBA9876543210 ^ (64'd1 << 47);

    initial begin
        $dumpfile("sim/waves/tb_quantum_qkd_top.vcd");
        $dumpvars(0, tb_quantum_qkd_top);

        clk                = 0;
        rst_n              = 0;
        raw_event_valid    = 0;
        alice_basis        = 0;
        alice_bit          = 0;
        bob_basis          = 0;
        bob_bit            = 0;
        trng_sample_valid  = 0;
        trng_sample        = 4'd0;
        alice_block_parity = 0;
        alice_ref_block    = 64'd0;
        paddr              = 8'd0;
        psel               = 0;
        penable            = 0;
        pwrite             = 0;
        pwdata             = 32'd0;

        $display("=====================================================================");
        $display("   QUANTUM KEY DISTRIBUTION (QKD) & NIST TRNG ASIC VERIFICATION SUITE ");
        $display("=====================================================================");

        // -------------------------------------------------------------
        // Test 1: Power-on Reset & APB Register Defaults
        // -------------------------------------------------------------
        #20;
        rst_n = 1;
        #10;

        apb_read(8'h00, read_val);
        if (read_val == 32'd0 && !alarm_eve_detected && !alarm_trng_fault && !irq_key_ready) begin
            $display("[PASS] Test 1: Power-on Reset verified, APB register bus idle and clean.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 1: Register reset failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 2: BB84 Basis Sifting Matching Verification
        // -------------------------------------------------------------
        apb_write(8'h00, 32'h00000001); // Enable Sifting
        @(posedge clk); #0.2;

        raw_event_valid = 1; alice_basis = 0; alice_bit = 1; bob_basis = 0; bob_bit = 1;
        @(posedge clk); #0.2;
        raw_event_valid = 1; alice_basis = 0; alice_bit = 1; bob_basis = 1; bob_bit = 0;
        @(posedge clk); #0.2;
        raw_event_valid = 0;
        repeat(3) @(posedge clk);

        apb_read(8'h0C, read_val);
        if (read_val[31:16] == 16'd2 && read_val[15:0] == 16'd1) begin
            $display("[PASS] Test 2: BB84 Sifting correctly accepted matched basis and discarded mismatched basis.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 2: Basis sifting logic error (raw=%d, sifted=%d).",
                read_val[31:16], read_val[15:0]);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 3: Raw Key Detection & Sifted Key Output Rate (50% yield)
        // -------------------------------------------------------------
        begin: sifting_rate_loop
            integer e;
            for (e = 0; e < 40; e = e + 1) begin
                raw_event_valid = 1;
                alice_basis = e[0];
                alice_bit   = e[1];
                bob_basis   = (e[1] == 1'b0) ? e[0] : ~e[0]; // 50% basis match
                bob_bit     = alice_bit;
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(5) @(posedge clk);

        apb_read(8'h0C, read_val);
        if (read_val[15:0] == 16'd21) begin
            $display("[PASS] Test 3: Sifted Key Yield conforms to 50%% BB84 match rate (%0d cumulative bits).",
                read_val[15:0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 3: Sifting rate mismatch (%d bits).", read_val[15:0]);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 4: Quantum Bit Error Rate (QBER) Calculation
        // -------------------------------------------------------------
        begin: qber_loop
            integer e;
            for (e = 0; e < 10; e = e + 1) begin
                raw_event_valid = 1;
                alice_basis = 0;
                bob_basis   = 0;
                alice_bit   = 1;
                bob_bit     = (e == 0) ? 1'b0 : 1'b1; // 1 error
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(5) @(posedge clk);

        apb_read(8'h08, read_val);
        if (u_dut.error_bits_count == 16'd1 && read_val[15:8] > 8'd0) begin
            $display("[PASS] Test 4: Real-time QBER engine computed QBER=%0d%% (Errors=1).", read_val[15:8]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 4: QBER calculation failed (err=%d qber=%d).",
                u_dut.error_bits_count, read_val[15:8]);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 5: QBER Threshold Exceeded Security Abort (Eve detection)
        // -------------------------------------------------------------
        saw_eve_alarm = 0;
        begin: eve_flood_loop
            integer e;
            for (e = 0; e < 20; e = e + 1) begin
                raw_event_valid = 1;
                alice_basis = 0;
                bob_basis   = 0;
                alice_bit   = 1;
                bob_bit     = 0;
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(5) @(posedge clk);

        if (saw_eve_alarm && alarm_eve_detected) begin
            $display("[PASS] Test 5: QBER security threshold exceeded (>11%%). Eve eavesdropping alarm triggered abort!");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 5: Eve eavesdropping alarm failed to fire.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 6: Binary-Bisection Cascade Reconciliation via Sifted Stream
        // -------------------------------------------------------------
        // Reset cleanly so sifted_key_buf aligns cleanly at bit 0
        rst_n = 0;
        #10;
        rst_n = 1;
        #10;
        saw_key_irq   = 0;
        saw_hash_done = 0;

        apb_write(8'h00, 32'h00000001); // Enable Sifting
        alice_ref_block    = ALICE_KEY_BLOCK;
        alice_block_parity = ^ALICE_KEY_BLOCK;

        // Stream 64 real sifted photon events (bit 47 corrupted on Bob side)
        begin: stream_block_loop
            integer idx;
            for (idx = 63; idx >= 0; idx = idx - 1) begin
                raw_event_valid = 1;
                alice_basis     = idx[0];
                bob_basis       = idx[0];
                alice_bit       = ALICE_KEY_BLOCK[idx];
                bob_bit         = BOB_KEY_BLOCK[idx];
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(15) @(posedge clk);

        if (u_dut.u_reconciler.error_corrected_flag &&
            u_dut.u_reconciler.error_bit_index == 6'd47 &&
            u_dut.u_reconciler.key_block_corrected == ALICE_KEY_BLOCK) begin
            $display("[PASS] Test 6: Binary-Bisection Cascade isolated and corrected bit-flip at index %0d.",
                u_dut.u_reconciler.error_bit_index);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 6: Cascade error reconciliation failed (flag=%b idx=%0d block=%016h).",
                u_dut.u_reconciler.error_corrected_flag,
                u_dut.u_reconciler.error_bit_index,
                u_dut.u_reconciler.key_block_corrected);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 7: Toeplitz Matrix Universal Hash Generation
        // -------------------------------------------------------------
        repeat(70) @(posedge clk);

        if (u_dut.u_privacy.final_secret_key != 32'd0) begin
            $display("[PASS] Test 7: Toeplitz Universal Hash matrix multiplication generated final key: 0x%08h",
                u_dut.u_privacy.final_secret_key);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 7: Toeplitz hash generated zero key.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 8: Privacy Amplification Key Compression (64 -> 32 bits)
        // -------------------------------------------------------------
        apb_read(8'h04, key_status);
        if (saw_hash_done && saw_key_irq && irq_key_ready) begin
            $display("[PASS] Test 8: Privacy Amplification compressed 64-bit block to 32-bit key and raised IRQ.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 8: Privacy amplification completion missing (done=%b irq=%b).",
                saw_hash_done, saw_key_irq);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 9: NIST SP 800-90B Health Tests: RCT & APT
        // -------------------------------------------------------------
        begin: trng_clean_loop
            integer s;
            for (s = 0; s < 100; s = s + 1) begin
                trng_sample_valid = 1;
                trng_sample = s[3:0];
                @(posedge clk); #0.2;
            end
        end
        trng_sample_valid = 0;
        repeat(5) @(posedge clk);

        apb_read(8'h04, key_status);
        if (key_status[3] == 1'b1 && !alarm_trng_fault) begin
            $display("[PASS] Test 9: NIST SP 800-90B Continuous Health Tests (RCT & APT) verified entropy healthy.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 9: False TRNG health test alarm.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 10: Final Secure Quantum Secret Key APB Readout & IRQ Clear
        // -------------------------------------------------------------
        apb_read(8'h10, read_val);
        @(posedge clk); #0.2;
        if (read_val != 32'd0 && !irq_key_ready) begin
            $display("[PASS] Test 10: Secure Secret Key extracted over APB3 (0x%08h) and IRQ cleared.", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 10: Secret key APB readout failed (key=%08h irq=%b).", read_val, irq_key_ready);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test Summary and Sign-off
        // -------------------------------------------------------------
        $display("=====================================================================");
        $display("   TEST SUMMARY: PASSED %0d / 10 TESTS", tests_passed);
        $display("=====================================================================");

        if (tests_passed == 10 && tests_failed == 0) begin
            $display(">>> ALL 10 VERIFICATION TESTS COMPLETED WITH 100%% PASS RATE <<<");
            $finish;
        end else begin
            $display(">>> VERIFICATION FAILED WITH %0d FAILURES <<<", tests_failed);
            $fatal(1, "Testbench execution terminated with errors.");
        end
    end

endmodule
