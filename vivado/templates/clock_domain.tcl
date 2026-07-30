# ------------------------------------------------------------
# Procedure: connect_axi_lite
# ------------------------------------------------------------
# Creates:
#   - an AXI Interconnect (axi_interconnect) configured for N slave ports
#   - proc_sys_reset (synchronous reset sync) driven by ref clock/reset
# Then connects:
#   - each IP inst/S_AXI -> interconnect/Sxx_AXI
#   - interconnect ACLK/ARESETN -> proc_sys_reset outputs and ref clock
#   - each IP clock/reset pins -> ref clock and proc_sys_reset output
#
# Inputs:
#   ip_insts_list      : list of BD cell instance names for AXI-Lite slaves
#   ref_clk_pin        : BD pin object for the reference clock (e.g. get_bd_pins /clk_wiz_0/clk_out1)
#   ref_rst_pin        : BD pin object for the (external) reset input to proc_sys_reset (active high or low depends on CONFIG)
#   axi_clk_pin_name   : name of clock pin on each IP instance (e.g. "s_axi_aclk")
#   axi_aresetn_pin_name: name of reset pin on each IP instance (e.g. "s_axi_aresetn")
#   axi_ic_name        : name for the created AXI interconnect cell
#   proc_reset_name    : name for the created proc_sys_reset cell
#   axi_intf_pin_name  : AXI-Lite slave interface pin name on each IP (default "S_AXI")
#   s_reset_active_low : set 1 if ref_rst_pin is active-low, 0 if active-high
#
proc connect_axi_lite { \
    ip_insts_list \
    ref_clk_pin \
    ref_rst_pin \
    {axi_clk_pin_name "s_axi_aclk"} \
    {axi_aresetn_pin_name "s_axi_aresetn"} \
    {axi_ic_name "axi_lite_interconnect_0"} \
    {proc_reset_name "proc_sys_reset_0"} \
    {axi_intf_pin_name "S_AXI"} \
    {s_reset_active_low 1} \
} {
    # -------------------- Basic checks --------------------
    if {[llength $ip_insts_list] < 1} {
        error "ip_insts_list is empty."
    }

    # -------------------- Create AXI interconnect --------------------
    # Note: This is the IP Integrator interconnect used to connect masters->slaves.
    # In your case, the "external master M_AXI" side is assumed to exist elsewhere;
    # this procedure builds the interconnect and wires slaves.
    #
    # If your Vivado build fails because CONFIG.NUM_SI / variant differs,
    # run again and paste the exact error—CONFIG field name can differ by version/VC.
    set ic_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect $axi_ic_name]

    set num_slaves [llength $ip_insts_list]

    # Configure number of slave interfaces.
    # (May require adjustment if your interconnect preset uses different config fields.)
    set_property -dict [list CONFIG.NUM_SI $num_slaves] $ic_cell

    # Typical pin names on axi_interconnect:
    #   - ACLK
    #   - ARESETN
    set ic_aclk    [get_bd_pins ${axi_ic_name}/ACLK]
    set ic_aresetn [get_bd_pins ${axi_ic_name}/ARESETN]

    if {[llength $ic_aclk] == 0 || [llength $ic_aresetn] == 0} {
        error "Could not find ${axi_ic_name}/ACLK or ${axi_ic_name}/ARESETN pins."
    }

    # -------------------- Create synchronous reset block (proc_sys_reset) --------------------
    set rst_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset $proc_reset_name]

    # Typical proc_sys_reset ports:
    #   - slowest_sync_clk
    #   - ext_reset_in
    #   - peripheral_aresetn
    #
    # Also, connect reset sync output to both interconnect and AXI peripherals.
    set psr_clk    [get_bd_pins ${proc_reset_name}/slowest_sync_clk]
    set psr_extrst [get_bd_pins ${proc_reset_name}/ext_reset_in]
    set psr_periph_aresetn [get_bd_pins ${proc_reset_name}/peripheral_aresetn]

    if {[llength $psr_clk] == 0 || [llength $psr_extrst] == 0 || [llength $psr_periph_aresetn] == 0} {
        error "Could not find proc_sys_reset expected pins (slowest_sync_clk/ext_reset_in/peripheral_aresetn)."
    }

    # Configure polarity of ext_reset_in / output (active low).
    # proc_sys_reset uses CONFIG.C_EXT_RESET_HIGH to interpret ext_reset_in polarity.
    # If your ref_rst_pin is active-low (default), ext_reset_in is low when asserted => C_EXT_RESET_HIGH {0}.
    set c_ext_reset_high [expr {$s_reset_active_low ? 0 : 1}]
    set_property CONFIG.C_EXT_RESET_HIGH $c_ext_reset_high $rst_cell

    # Clock/reset wiring into proc_sys_reset
    connect_bd_net $ref_clk_pin $psr_clk
    connect_bd_net $ref_rst_pin $psr_extrst

    # -------------------- Connect interconnect clock/reset --------------------
    connect_bd_net $ref_clk_pin $ic_aclk
    connect_bd_net $psr_periph_aresetn $ic_aresetn

    # -------------------- Connect each IP's S_AXI to interconnect Sxx_AXI and wire clock/reset --------------------
    set idx 0
    foreach inst $ip_insts_list {
        # IP AXI interface pin
        set ip_axi_intf [get_bd_intf_pins ${inst}/${axi_intf_pin_name}]
        if {[llength $ip_axi_intf] == 0} {
            error "Could not find ${inst}/${axi_intf_pin_name} intf pin."
        }

        # IP clock/reset pins (per your statement: same as provided ref clock/reset pins)
        set ip_aclk     [get_bd_pins ${inst}/${axi_clk_pin_name}]
        set ip_aresetn  [get_bd_pins ${inst}/${axi_aresetn_pin_name}]
        if {[llength $ip_aclk] == 0 || [llength $ip_aresetn] == 0} {
            error "Could not find ${inst}/${axi_clk_pin_name} or ${inst}/${axi_aresetn_pin_name} pins."
        }

        # interconnect slave interface pin names: S00_AXI, S01_AXI, ...
        set ic_s_if "S[format %02d $idx]_AXI"
        set ic_slave_intf [get_bd_intf_pins ${axi_ic_name}/${ic_s_if}]
        if {[llength $ic_slave_intf] == 0} {
            error "Could not find ${axi_ic_name}/${ic_s_if} interconnect slave interface pin."
        }

        # Connect AXI-Lite interface (slave wiring)
        connect_bd_intf_net -quiet $ic_slave_intf $ip_axi_intf

        # Connect clocks and resets to the IP
        connect_bd_net $ref_clk_pin $ip_aclk
        connect_bd_net $psr_periph_aresetn $ip_aresetn

        incr idx
    }

    # (Optional) Layout/validation
    # regenerate_bd_layout
    # validate_bd_design
}
