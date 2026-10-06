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
report timing > march_c-_timing.rep
report power  > march_c-_power.rep
report area   > march_c-_area.rep
report messages > march_c-_messages.rep

# ================================
# Output
# ================================
write_hdl > march_c-_netlist.v
write_sdc > march_c-.sdc

# gui_show

