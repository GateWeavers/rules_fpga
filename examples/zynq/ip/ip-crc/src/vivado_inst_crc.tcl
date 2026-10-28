proc vivado_inst_crc_top_wrapper { inst_name generics } {

    set hier_name $inst_name
    set inst_name $inst_name\_ip

    create_bd_cell -type module -reference crc_top_wrapper $inst_name

    # Create instance: AXI_DMA, and set properties
    set AXI_DMA [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 $hier_name\_AXI_DMA ]
    set_property -dict [ list \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_sg_length_width {25} \
    CONFIG.c_m_axis_mm2s_tdata_width {8}\
    ] $AXI_DMA

    connect_bd_intf_net -intf_net $inst_name\_DMA_M_AXI_MM2S [get_bd_intf_pins $inst_name/S_AXIS] [get_bd_intf_pins $hier_name\_AXI_DMA/M_AXIS_MM2S]

    create_bd_cell -type hier $hier_name

    move_bd_cells [get_bd_cells $hier_name] [get_bd_cells $inst_name]

    move_bd_cells [get_bd_cells $hier_name] [get_bd_cells $hier_name\_AXI_DMA]


    # Create cell and set as current instance
    current_bd_instance $hier_name

    # create axi ports
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_LITE
    create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI_MM2S

    # create pin
    create_bd_pin -dir I -type rst s_axi_aresetn
    create_bd_pin -dir I -type clk s_axi_aclk

    # connect internal wires
    connect_bd_intf_net [get_bd_intf_pins s_axi] [get_bd_intf_pins $inst_name/s_axi]
    connect_bd_intf_net [get_bd_intf_pins S_AXI_LITE] [get_bd_intf_pins $hier_name\_AXI_DMA/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins M_AXI_MM2S] [get_bd_intf_pins $hier_name\_AXI_DMA/M_AXI_MM2S]

    connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins $inst_name/S_AXI_ACLK] [get_bd_pins $inst_name/S_AXIS_ACLK] [get_bd_pins $inst_name/M_AXIS_ACLK] [get_bd_pins $hier_name\_AXI_DMA/s_axi_lite_aclk]
    connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins $hier_name\_AXI_DMA/axi_resetn] [get_bd_pins $inst_name/S_AXI_ARESETN]
    connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins $hier_name\_AXI_DMA/m_axi_mm2s_aclk]

    current_bd_instance
}

proc vivado_memory_mapping_crc_top_wrapper { inst_name segments } {
    array set addrs $segments
    set base_addr $addrs(SEG_CRC)
    set dma_base_addr $addrs(SEG_CRC_DMA)
    set s2mm_base_addr $addrs(S2MM_DMA)

    #########################################
    # create addr segments
    #########################################

    set ps_base ps7_0
    set ps_data_space [get_bd_addr_spaces $ps_base/Data]

    set reg0_seg [get_bd_addr_segs **/${inst_name}_ip/s_axi/reg0]
    set dma_reg_seg [get_bd_addr_segs **/${inst_name}_AXI_DMA/S_AXI_LITE/Reg]
    set dma_space [get_bd_addr_spaces **/${inst_name}_AXI_DMA/Data_MM2S]
    set hp0_seg [get_bd_addr_segs $ps_base/S_AXI_HP0/HP0_DDR_LOWOCM]

    create_bd_addr_seg -range 0x00010000 -offset $base_addr $ps_data_space $reg0_seg SEG_${inst_name}

    create_bd_addr_seg -range 0x00010000 -offset $dma_base_addr $ps_data_space $dma_reg_seg SEG_${inst_name}_DMA

    create_bd_addr_seg -range 512M -offset $s2mm_base_addr $dma_space $hp0_seg SEG_${inst_name}_MASTER_DMA_FROM_RAM

}