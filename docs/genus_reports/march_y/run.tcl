# Library setup
set_db lib_search_path /home/install/FOUNDRY/digital/90nm/dig/lib/
set_db library slow.lib

# Read all Verilog files
read_hdl {mbist_top.v fsm_controller.v data_generator.v comparator.v address_generator.v}

# Elaborate top module
elaborate mbist_top


read_sdc mbist.sdc

# ================================
# Synthesis
# ================================
syn_gen -effort medium
syn_map -effort medium

# ================================
# Reports
# ================================
report timing > march_y_timing.rep
report power  > march_y_power.rep
report area   > march_y_area.rep
report messages > march_y_messages.rep

# ================================
# Output
# ================================
write_hdl > march_y_netlist.v
write_sdc > march_y.sdc

# gui_show

