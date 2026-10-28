# Zynq ps inst
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0]

set_property -dict [list \
  CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
] [get_bd_cells ps7_0]

apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR"} $ps

connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ps7_0/M_AXI_GP0_ACLK]
