# ==============================================================================
# Synopsys Design Constraints (SDC)
# Design: quantum_qkd_top
# Operating Frequency: 250 MHz (Clock Period = 4.000 ns)
# Process: TSMC 28nm HPC+ Logic Library
# ==============================================================================

# Primary Master Clock Definition (250 MHz)
create_clock -name clk -period 4.000 -waveform {0.000 2.000} [get_ports clk]

# Clock Uncertainty and Jitter Constraints
set_clock_uncertainty -setup 0.150 [get_clocks clk]
set_clock_uncertainty -hold  0.080 [get_clocks clk]
set_clock_transition 0.050 [get_clocks clk]

# Input Port Delay Constraints
set_input_delay -clock clk -max 0.800 [get_ports {rst_n raw_event_* alice_* bob_* trng_* paddr* psel penable pwrite pwdata*}]
set_input_delay -clock clk -min 0.200 [get_ports {rst_n raw_event_* alice_* bob_* trng_* paddr* psel penable pwrite pwdata*}]

# Output Port Delay Constraints
set_output_delay -clock clk -max 0.900 [get_ports {prdata* pready pslverr irq_key_ready alarm_*}]
set_output_delay -clock clk -min 0.150 [get_ports {prdata* pready pslverr irq_key_ready alarm_*}]

# Drive Strength and Output Load Modeling
set_driving_cell -lib_cell INVD2BWP -library tcbn28hpcplus_ss0p9v125c [all_inputs]
set_load 0.025 [all_outputs]

# Multicycle Path & False Path Constraints
set_false_path -from [get_ports rst_n]
