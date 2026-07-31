load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//fpga:rules.bzl", "fpga_ip_config", "fpga_clock_domain")
load("//vivado:rules.bzl", "vivado_design")

def _vivado_design_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)
    
    # Extract output files
    files = target_under_test[DefaultInfo].files.to_list()
    file_names = [f.basename for f in files]
    
    # Assert top-level targets are generated
    asserts.true(env, "test_design_top.dcp" in file_names, "Should contain top level DCP")
    asserts.true(env, "test_design_top_synth.tcl" in file_names, "Should contain top level TCL script")
    asserts.true(env, "test_design_bd_inst.tcl" in file_names, "Should contain BD instantiation script")
    asserts.true(env, "test_design_memory_mapping.tcl" in file_names, "Should contain memory mapping script")
    asserts.true(env, "test_design_clock_domain.tcl" in file_names, "Should contain clock domain script")
    
    # Filter OOC DCP targets
    ooc_dcps = [f for f in file_names if f.startswith("ooc_") and f.endswith(".dcp")]
    ooc_tcls = [f for f in file_names if f.startswith("ooc_") and f.endswith(".tcl")]
    
    # Assert deduplication: 
    # we registered 3 IP targets, but u_uart_debug and u_uart_telemetry share the same config.
    asserts.equals(env, 2, len(ooc_dcps), "Should only generate 2 OOC DCPs due to deduplication")
    asserts.equals(env, 2, len(ooc_tcls), "Should only generate 2 OOC TCL scripts")
    
    # Assert BD instantiation script content by finding the action that writes it
    bd_action = None
    mem_action = None
    clk_action = None
    actions = analysistest.target_actions(env)
    for action in actions:
        for out in action.outputs.to_list():
            if out.basename == "test_design_bd_inst.tcl":
                bd_action = action
            elif out.basename == "test_design_memory_mapping.tcl":
                mem_action = action
            elif out.basename == "test_design_clock_domain.tcl":
                clk_action = action
                
    asserts.true(env, bd_action != None, "BD instantiation action should be registered")
    asserts.true(env, mem_action != None, "Memory mapping action should be registered")
    asserts.true(env, clk_action != None, "Clock domain action should be registered")
    
    # Check BD instantiation script content
    bd_content = bd_action.content
    asserts.true(env, "source vivado/tests/vivado_inst_my_module.tcl\n" in bd_content, "Should source the instantiation script exactly once")
    asserts.true(env, "vivado_inst_my_module \"u_module_inst\" [list \"PARAM\" \"1\"]\n" in bd_content, "Should call vivado_inst_my_module procedure with correct args")
    
    # Check memory mapping script content
    mem_content = mem_action.content
    asserts.true(env, "source vivado/tests/vivado_inst_my_module.tcl\n" in mem_content, "Should source the instantiation script exactly once")
    asserts.true(env, "vivado_memory_mapping_my_module \"u_module_inst\" [list \"seg1\" \"\" \"seg2\" \"\"]\n" in mem_content, "Should call vivado_memory_mapping_my_module procedure with correct args")
    
    # Check clock domain script content
    clk_content = clk_action.content
    asserts.true(env, "source vivado/templates/clock_domain.tcl\n\n" in clk_content, "Should source the clock_domain.tcl template")
    
    # Assert main_clk_domain connections:
    # u_module_inst, u_uart_debug, and u_uart_telemetry share main_clk_domain. They must be grouped.
    asserts.true(env, "connect_axi_lite \\\n    [list \"u_module_inst\" \"u_uart_debug\" \"u_uart_telemetry\"] \\\n" in clk_content, "Should group instances sharing main_clk_domain")
    asserts.true(env, "    get_bd_pins /clk_wiz_0/clk_out1 \\\n    get_bd_pins /rst_clk_wiz_0_100M/ext_reset_in \\\n" in clk_content, "Should pass main clock and reset pins")
    asserts.true(env, "    \"proc_sys_reset_0\" \\\n    \"S_AXI\" \\\n    1\n" in clk_content, "Should pass active_low value 1 for main clk reset")
    
    # Assert high_clk_domain connections:
    # u_uart_gps uses high_clk_domain.
    asserts.true(env, "connect_axi_lite \\\n    [list \"u_uart_gps\"] \\\n" in clk_content, "Should connect u_uart_gps separately")
    asserts.true(env, "    get_bd_pins /clk_wiz_0/clk_out2 \\\n    get_bd_pins /rst_clk_wiz_0_100M/ext_reset_in2 \\\n" in clk_content, "Should pass high clock and reset pins")
    asserts.true(env, "    \"proc_sys_reset_1\" \\\n    \"S_AXI\" \\\n    0\n" in clk_content, "Should pass active_high value 0 for high clk reset")
    
    return analysistest.end(env)

vivado_design_test = analysistest.make(
    impl = _vivado_design_test_impl,
)

def vivado_design_test_suite(name):
    # Register clock domains
    fpga_clock_domain(
        name = "main_clk_domain",
        clock_pin = "get_bd_pins /clk_wiz_0/clk_out1",
        reset_pin = "get_bd_pins /rst_clk_wiz_0_100M/ext_reset_in",
        reset_type = "active_low",
        tags = ["manual"],
    )
    
    fpga_clock_domain(
        name = "high_clk_domain",
        clock_pin = "get_bd_pins /clk_wiz_0/clk_out2",
        reset_pin = "get_bd_pins /rst_clk_wiz_0_100M/ext_reset_in2",
        reset_type = "active_high",
        tags = ["manual"],
    )

    # 1. Register 3 configs (2 are duplicates)
    fpga_ip_config(
        name = "u_uart_debug",
        entity_name = "uart_ctrl",
        instance_name = "u_uart_debug",
        generics = {"BAUD_RATE": "115200"},
        clock_domain = ":main_clk_domain",
        tags = ["manual"],
    )
    
    fpga_ip_config(
        name = "u_uart_telemetry",
        entity_name = "uart_ctrl",
        instance_name = "u_uart_telemetry",
        generics = {"BAUD_RATE": "115200"}, # Exact duplicate of u_uart_debug
        clock_domain = ":main_clk_domain",
        tags = ["manual"],
    )
    
    fpga_ip_config(
        name = "u_uart_gps",
        entity_name = "uart_ctrl",
        instance_name = "u_uart_gps",
        generics = {"BAUD_RATE": "9600"},
        clock_domain = ":high_clk_domain",
        tags = ["manual"],
    )
    
    # Register 1 non-OOC config with an instantiation script in srcs, memory mapping, and main clock domain
    fpga_ip_config(
        name = "u_non_ooc_ip",
        entity_name = "my_module",
        instance_name = "u_module_inst",
        generics = {"PARAM": "1"},
        ooc = False,
        memory_mapping = "seg1, seg2",
        clock_domain = ":main_clk_domain",
        srcs = ["vivado_inst_my_module.tcl"],
        tags = ["manual"],
    )
    
    # 2. Define the vivado_design target
    vivado_design(
        name = "test_design",
        ip_configs = [
            ":u_uart_debug",
            ":u_uart_telemetry",
            ":u_uart_gps",
            ":u_non_ooc_ip",
        ],
        top = "blinky_top",
        part = "xc7z020clg400-1",
        tags = ["manual"],
    )
    
    # 3. Define the analysis test
    vivado_design_test(
        name = name + "_test",
        target_under_test = ":test_design",
    )
