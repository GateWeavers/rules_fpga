connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_lite_interconnect_0/S00_AXI]
connect_bd_net [get_bd_pins ps7_0/FCLK_CLK0] [get_bd_pins ps7_0/S_AXI_HP0_ACLK]

connect_bd_intf_net [get_bd_intf_pins smartconnect_dma_0/M00_AXI] [get_bd_intf_pins ps7_0/S_AXI_HP0]

set idx 0
set hp_ports [list "ps7_0/S_AXI_HP0"]
puts $sc_master_pins
