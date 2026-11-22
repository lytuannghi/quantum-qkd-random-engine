// =============================================================================
// File: qkd_regs_apb.v
// Module: qkd_regs_apb
// Project: Quantum Key Distribution (QKD) Hardware Engine & NIST TRNG ASIC
// Description: AMBA 3 APB Slave Configuration, Status & Secret Key Register Bank.
// =============================================================================

`timescale 1ns / 1ps

module qkd_regs_apb (
    input  wire                 pclk,
    input  wire                 presetn,

    // APB3 Interface
    input  wire [7:0]           paddr,
    input  wire                 psel,
    input  wire                 penable,
    input  wire                 pwrite,
    input  wire [31:0]          pwdata,
    output reg  [31:0]          prdata,
    output wire                 pready,
    output wire                 pslverr,

    // Control Outputs to QKD Pipeline
    output reg                  reg_sifting_enable,
    output reg  [7:0]           reg_qber_threshold,
    output reg                  reg_reconcile_start,
    output reg                  reg_hash_start,

    // Telemetry from QKD Pipeline
    input  wire                 status_qber_alarm,
    input  wire                 status_reconcile_done,
    input  wire                 status_hash_done,
    input  wire                 status_trng_pass,
    input  wire [7:0]           qber_pct,
    input  wire [15:0]          total_raw_events,
    input  wire [15:0]          total_sifted_bits,
    input  wire [31:0]          final_secret_key,

    // Interrupt Output
    output reg                  irq_key_ready
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_sifting_enable  <= 1'b0;
            reg_qber_threshold  <= 8'd11; // 11% theoretical limit
            reg_reconcile_start <= 1'b0;
            reg_hash_start      <= 1'b0;
            irq_key_ready       <= 1'b0;
            prdata              <= 32'd0;
        end else begin
            reg_reconcile_start <= 1'b0;
            reg_hash_start      <= 1'b0;

            if (status_hash_done)
                irq_key_ready <= 1'b1;
            else if (psel && penable && !pwrite && paddr == 8'h10)
                irq_key_ready <= 1'b0; // Auto-clear on key read

            // APB Write
            if (psel && penable && pwrite) begin
                case (paddr)
                    8'h00: begin
                        reg_sifting_enable  <= pwdata[0];
                        reg_reconcile_start <= pwdata[1];
                        reg_hash_start      <= pwdata[2];
                    end
                    8'h08: begin
                        reg_qber_threshold <= pwdata[7:0];
                    end
                    default: ;
                endcase
            end

            // APB Read
            if (psel && !pwrite) begin
                case (paddr)
                    8'h00: prdata <= {29'd0, reg_sifting_enable};
                    8'h04: prdata <= {28'd0, status_trng_pass, status_hash_done, status_reconcile_done, status_qber_alarm};
                    8'h08: prdata <= {16'd0, qber_pct, reg_qber_threshold};
                    8'h0C: prdata <= {total_raw_events, total_sifted_bits};
                    8'h10: prdata <= final_secret_key;
                    default: prdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
