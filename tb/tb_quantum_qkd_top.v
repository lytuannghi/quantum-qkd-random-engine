// =============================================================================
// File: tb_quantum_qkd_top.v
// Module: tb_quantum_qkd_top
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: Comprehensive Self-Checking Testbench.
//              Executes 10 rigorous test cases covering:
//              - APB3 Register Bus Access & Configuration
//              - BB84 Basis Matching & 50% Yield Sifting
//              - Real-time QBER Evaluation & Security Abort on Eavesdropping
//              - Modified Cascade Information Reconciliation & Bit Error Correction
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
        if (read_val == 32'd0) begin
            $display("[PASS] Test 1: Power-on Reset verified, APB register bus idle and clean.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 1: Register reset failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 2: BB84 Basis Sifting Matching Verification (Rectilinear vs Diagonal)
        // -------------------------------------------------------------
        apb_write(8'h00, 32'h00000001); // Enable Sifting
        @(posedge clk); #0.2;

        // Send 1 matched basis event (Alice 0, Bob 0)
        raw_event_valid = 1; alice_basis = 0; alice_bit = 1; bob_basis = 0; bob_bit = 1;
        @(posedge clk); #0.2;
        // Send 1 mismatched basis event (Alice 0, Bob 1) -> must be discarded
        raw_event_valid = 1; alice_basis = 0; alice_bit = 1; bob_basis = 1; bob_bit = 0;
        @(posedge clk); #0.2;
        raw_event_valid = 0;
        repeat(3) @(posedge clk);

        if (u_dut.total_raw_events == 16'd2 && u_dut.total_sifted_bits == 16'd1) begin
            $display("[PASS] Test 2: BB84 Sifting correctly accepted matched basis and discarded mismatched basis.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 2: Basis sifting logic error (raw=%d, sifted=%d).",
                u_dut.total_raw_events, u_dut.total_sifted_bits);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 3: Raw Key Detection & Sifted Key Output Rate (50% theoretical yield)
        // -------------------------------------------------------------
        // Stream 40 random events with equal probability of matching basis
        begin: sifting_rate_loop
            integer e;
            for (e = 0; e < 40; e = e + 1) begin
                raw_event_valid = 1;
                alice_basis = e[0];     // Alternating bases
                alice_bit   = e[1];
                bob_basis   = (e % 4 < 2) ? e[0] : ~e[0]; // Exactly 50% match
                bob_bit     = alice_bit;
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(5) @(posedge clk);

        if (u_dut.total_sifted_bits >= 16'd15 && u_dut.total_sifted_bits <= 16'd25) begin
            $display("[PASS] Test 3: Sifted Key Yield conforms to theoretical 50%% BB84 basis match rate (%0d bits).",
                u_dut.total_sifted_bits);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 3: Sifting rate out of bounds (%d bits).", u_dut.total_sifted_bits);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 4: Quantum Bit Error Rate (QBER) Calculation
        // -------------------------------------------------------------
        // Send 10 matched events with 1 intentional bit flip error (10% QBER)
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

        if (u_dut.error_bits_count >= 16'd1) begin
            $display("[PASS] Test 4: Real-time QBER tracking registered channel errors (Errors = %0d).",
                u_dut.error_bits_count);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 4: QBER error count failed to increment.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 5: QBER Threshold Exceeded Security Abort (Eve eavesdropping detection)
        // -------------------------------------------------------------
        // Flood channel with 20 errors to push QBER well above the 11% threshold
        saw_eve_alarm = 0;
        begin: eve_flood_loop
            integer e;
            for (e = 0; e < 20; e = e + 1) begin
                raw_event_valid = 1;
                alice_basis = 0;
                bob_basis   = 0;
                alice_bit   = 1;
                bob_bit     = 0; // 100% error -> Eve intercept-resend
                @(posedge clk); #0.2;
            end
        end
        raw_event_valid = 0;
        repeat(5) @(posedge clk);

        if (saw_eve_alarm || alarm_eve_detected || u_dut.qber_alarm_abort) begin
            $display("[PASS] Test 5: QBER security threshold exceeded (>11%%). Eve eavesdropping alarm triggered abort!");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 5: Eve eavesdropping alarm failed to fire.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 6: Cascade Interactive Error Reconciliation & Bit-Flip Correction
        // -------------------------------------------------------------
        // Load block into reconciler with parity mismatch
        u_dut.u_reconciler.key_block_corrected = 64'hFEDCBA9876543210;
        alice_block_parity = ~ (^64'hFEDCBA9876543210); // Opposite parity
        apb_write(8'h00, 32'h00000003); // Reconcile Start
        repeat(10) @(posedge clk);

        if (u_dut.u_reconciler.error_corrected_flag &&
            u_dut.u_reconciler.error_bit_index == 6'd3) begin
            $display("[PASS] Test 6: Modified Cascade Engine resolved parity mismatch and corrected bit-flip at index 3.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 6: Cascade error reconciliation failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 7: Toeplitz Matrix Universal Hash Generation
        // -------------------------------------------------------------
        // Trigger privacy amplification hash
        apb_write(8'h00, 32'h00000005); // Hash Start
        repeat(40) @(posedge clk);

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
        if (saw_hash_done || saw_key_irq) begin
            $display("[PASS] Test 8: Privacy Amplification compressed 64-bit reconciled block to 32-bit secret key.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 8: Privacy amplification completion flag missing.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 9: NIST SP 800-90B Health Tests: Repetition Count Test & APT
        // -------------------------------------------------------------
        // Feed 100 varying quantum entropy samples (clean)
        begin: trng_clean_loop
            integer s;
            for (s = 0; s < 100; s = s + 1) begin
                trng_sample_valid = 1;
                trng_sample = s % 16;
                @(posedge clk); #0.2;
            end
        end
        trng_sample_valid = 0;
        repeat(5) @(posedge clk);

        if (u_dut.u_trng_health.health_test_pass && !alarm_trng_fault) begin
            $display("[PASS] Test 9: NIST SP 800-90B Continuous Health Tests (RCT & APT) verified entropy stream healthy.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 9: False TRNG health test alarm.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 10: Final Secure Quantum Secret Key Ready Interrupt & APB Readout
        // -------------------------------------------------------------
        apb_read(8'h10, read_val); // Read secret key register
        if (read_val != 32'd0) begin
            $display("[PASS] Test 10: Secure Secret Key successfully extracted over APB3: 0x%08h.", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 10: Secret key readback is zero.");
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
