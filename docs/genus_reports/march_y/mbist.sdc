# Create clock
create_clock -name clk -period 2 [get_ports clk]

# Set clock transition
set_clock_transition 0.05 [get_clocks clk]

# Input delay (edit ports as per your design)
set_input_delay 0.2 -clock clk [get_ports rst]

# Output delay (edit port name if different)
set_output_delay 0.2 -clock clk [get_ports data_out]


