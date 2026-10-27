# ------------------------------------------------------------
# Procedure: connect_axi_lite
# ------------------------------------------------------------
proc connect_axi_lite { \
    ip_insts_list \
    ref_clk_pin \
    ref_rst_pin \
    {axi_clk_pin_name "s_axi_aclk"} \
    {axi_aresetn_pin_name "s_axi_aresetn"} \
    {axi_ic_name "axi_lite_interconnect_0"} \
    {proc_reset_name "proc_sys_reset_0"} \
    {axi_intf_patterns {"S_AXI" "S_AXI_LITE"}} \
    {s_reset_active_low 1} \
} {
    if {[llength $ip_insts_list] < 1} {
        error "ip_insts_list is empty."
    }

    set found_slave_intfs [list]
    foreach inst $ip_insts_list {
        foreach pattern $axi_intf_patterns {
            set intfs [get_bd_intf_pins -quiet -filter {MODE == "Slave"} ${inst}/${pattern}]
            foreach intf $intfs {
                if {[lsearch -exact $found_slave_intfs $intf] == -1} {
                    lappend found_slave_intfs $intf
                }
            }
        }
    }

    set num_slaves [llength $found_slave_intfs]
    if {$num_slaves < 1} {
        error "WARNING: no AXI Slave Found in : $ip_insts_list with pattern $axi_intf_patterns"
        return
    }

    set ic_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect $axi_ic_name]
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI $num_slaves] $ic_cell

    set ic_aclk    [get_bd_pins ${axi_ic_name}/ACLK]
    set ic_aresetn [get_bd_pins ${axi_ic_name}/ARESETN]

    if {[llength $ic_aclk] == 0 || [llength $ic_aresetn] == 0} {
        error "Could not find ${axi_ic_name}/ACLK or ${axi_ic_name}/ARESETN pins."
    }

    set rst_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset $proc_reset_name]

    set psr_clk    [get_bd_pins ${proc_reset_name}/slowest_sync_clk]
    set psr_extrst [get_bd_pins ${proc_reset_name}/ext_reset_in]
    set psr_periph_aresetn [get_bd_pins ${proc_reset_name}/peripheral_aresetn]

    if {[llength $psr_clk] == 0 || [llength $psr_extrst] == 0 || [llength $psr_periph_aresetn] == 0} {
        error "Could not find proc_sys_reset expected pins."
    }

    catch {
        set c_ext_reset_high [expr {$s_reset_active_low ? 0 : 1}]
        set_property CONFIG.C_EXT_RESET_HIGH $c_ext_reset_high $rst_cell
    }

    if {[llength $ref_clk_pin] == 0} {
        if {[llength [get_bd_ports -quiet sys_clk]] == 0} {
            set ref_clk_pin [create_bd_port -dir I -type clk -freq_hz 100000000 sys_clk]
        } else {
            set ref_clk_pin [get_bd_ports sys_clk]
        }
    }
    if {[llength $ref_rst_pin] == 0} {
        if {[llength [get_bd_ports -quiet sys_rst_n]] == 0} {
            set ref_rst_pin [create_bd_port -dir I -type rst sys_rst_n]
        } else {
            set ref_rst_pin [get_bd_ports sys_rst_n]
        }
    }

    connect_bd_net -quiet $ref_clk_pin $psr_clk
    connect_bd_net -quiet $ref_rst_pin $psr_extrst

    if {[llength $ref_clk_pin] > 0} {
        connect_bd_net -quiet $ref_clk_pin [get_bd_pins ${axi_ic_name}/*ACLK*]
    }
    connect_bd_net -quiet $psr_periph_aresetn [get_bd_pins ${axi_ic_name}/*ARESETN*]

    # connect AXI slave interfaces
    set idx 0
    foreach ip_axi_intf $found_slave_intfs {
        set ic_m_if "M[format %02d $idx]_AXI"
        set ic_master_intf [get_bd_intf_pins ${axi_ic_name}/${ic_m_if}]
        connect_bd_intf_net -quiet $ic_master_intf $ip_axi_intf
        incr idx
    }

    # connect clk an reset pins for each IPs
    foreach inst $ip_insts_list {
        set ip_aclk    [get_bd_pins -quiet ${inst}/${axi_clk_pin_name}]
        set ip_aresetn [get_bd_pins -quiet ${inst}/${axi_aresetn_pin_name}]

        if {[llength $ref_clk_pin] > 0 && [llength $ip_aclk] > 0} {
            connect_bd_net -quiet $ref_clk_pin $ip_aclk
        }
        if {[llength $ip_aresetn] > 0 && [llength $ip_aresetn] > 0} {
            connect_bd_net -quiet $psr_periph_aresetn $ip_aresetn
        }
    }
}

# Helper script for user
proc connect_master_to_interconnect {master_intf_pin {axi_ic_name "axi_lite_interconnect_0"} {slave_idx 0}} {
    set ic_s_if "S[format %02d $slave_idx]_AXI"
    set ic_slave_intf [get_bd_intf_pins ${axi_ic_name}/${ic_s_if}]
    if {[llength $ic_slave_intf] > 0 && [llength $master_intf_pin] > 0} {
        connect_bd_intf_net -quiet $master_intf_pin $ic_slave_intf
    }
}

proc connect_axi_masters_to_smartconnect { \
    ip_insts_list \
    ref_clk_pin \
    ref_rst_pin \
    {axi_intf_pattern "M_AXI*"} \
    {sc_name "axi_smartconnect_0"} \
    {num_mi 1} \
} {

    set found_master_intfs [list]

    foreach inst $ip_insts_list {
        # Find if the IP has an AXI master interface that matches a given pattern
        set intfs [get_bd_intf_pins -quiet -filter {MODE == "Master"} ${inst}/${axi_intf_pattern}]

        # Fallback
        if {[llength $intfs] == 0} {
            set intfs [get_bd_intf_pins -quiet -filter {MODE == "Master"} ${inst}/*]
        }

        foreach intf $intfs {
            lappend found_master_intfs $intf
        }
    }

    set num_masters [llength $found_master_intfs]

    if {$num_masters < 1} {
        puts "WARNING: No AXI master found in the list of IPs : $ip_insts_list"
        return [list]
    }

    # create smartconnect instance
    set sc_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 $sc_name]
    set_property -dict [list \
        CONFIG.NUM_SI $num_masters \
        CONFIG.NUM_MI $num_mi \
    ] $sc_cell

    set sc_aclk    [get_bd_pins ${sc_name}/aclk]
    set sc_aresetn [get_bd_pins ${sc_name}/aresetn]

    if {[llength $ref_clk_pin] > 0 && [llength $sc_aclk] > 0} {
        connect_bd_net -quiet $ref_clk_pin $sc_aclk
    }
    if {[llength $ref_rst_pin] > 0 && [llength $sc_aresetn] > 0} {
        connect_bd_net -quiet $ref_rst_pin $sc_aresetn
    }

    # Connect M_AXI interface to the smartconnect Sxx_AXI
    set idx 0
    foreach src_master_intf $found_master_intfs {
        set sc_s_if "S[format %02d $idx]_AXI"
        set sc_slave_intf [get_bd_intf_pins ${sc_name}/${sc_s_if}]

        connect_bd_intf_net -quiet $src_master_intf $sc_slave_intf
        incr idx
    }

    # output pins created to be used by users
    set m_pins [list]
    for {set i 0} {$i < $num_mi} {incr i} {
        set sc_m_if "M[format %02d $i]_AXI"
        lappend m_pins [get_bd_intf_pins ${sc_name}/${sc_m_if}]
    }

    return $m_pins
}