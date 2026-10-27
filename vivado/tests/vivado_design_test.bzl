load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//fpga:design.bzl",
    "fpga_clock_domain",
    "fpga_design",
    "fpga_ip",
    "fpga_ip_inst",
)
load("//fpga:providers.bzl", "FpgaDesignInfo", "FpgaProjectInfo", "FpgaSynthesisInfo")
load("//fpga:rules.bzl", "fpga_project", "fpga_synthesis")

def _vivado_design_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    # Extract output files
    files = target_under_test[DefaultInfo].files.to_list()
    file_names = [f.basename for f in files]

    # Assert generated TCL scripts
    asserts.true(env, "test_design_bd_inst.tcl" in file_names, "Should contain BD instantiation script")
    asserts.true(env, "test_design_memory_mapping.tcl" in file_names, "Should contain memory mapping script")
    asserts.true(env, "test_design_clock_domain.tcl" in file_names, "Should contain clock domain script")
    asserts.true(env, "test_design_bd.tcl" in file_names, "Should contain main BD script")

    # Assert actions writing the scripts
    bd_action = None
    mem_action = None
    clk_action = None
    main_bd_action = None
    actions = analysistest.target_actions(env)
    for action in actions:
        for out in action.outputs.to_list():
            if out.basename == "test_design_bd_inst.tcl":
                bd_action = action
            elif out.basename == "test_design_memory_mapping.tcl":
                mem_action = action
            elif out.basename == "test_design_clock_domain.tcl":
                clk_action = action
            elif out.basename == "test_design_bd.tcl":
                main_bd_action = action

    asserts.true(env, bd_action != None, "BD instantiation action should be registered")
    asserts.true(env, mem_action != None, "Memory mapping action should be registered")
    asserts.true(env, clk_action != None, "Clock domain action should be registered")
    asserts.true(env, main_bd_action != None, "Main BD script action should be registered")

    # Check BD instantiation script content
    bd_content = bd_action.content
    asserts.true(env, "source vivado/tests/vivado_inst_my_module.tcl\n" in bd_content, "Should source the instantiation script")
    asserts.true(env, 'vivado_inst_my_module "u_module_inst"' in bd_content, "Should call vivado_inst_my_module procedure")

    # Check memory mapping script content
    mem_content = mem_action.content
    asserts.true(env, "source vivado/tests/vivado_inst_my_module.tcl\n" in mem_content, "Should source the instantiation script")
    asserts.true(env, 'vivado_memory_mapping_my_module "u_module_inst"' in mem_content, "Should call vivado_memory_mapping_my_module procedure")

    # Check clock domain script content
    clk_content = clk_action.content
    asserts.true(env, "source vivado/templates/clock_domain.tcl\n\n" in clk_content, "Should source the clock_domain.tcl template")

    # Check main BD script content
    main_bd_content = main_bd_action.content
    asserts.true(env, 'create_bd_design "test_design"\n' in main_bd_content, "Should create block design with target name")
    asserts.true(env, "source vivado/tests/vivado_inst_my_module.tcl\n" in main_bd_content, "Should source block design hook")
    asserts.true(env, "source " + bd_action.outputs.to_list()[0].path in main_bd_content, "Should source BD instantiation script")
    asserts.true(env, "source " + mem_action.outputs.to_list()[0].path in main_bd_content, "Should source memory mapping script")
    asserts.true(env, "source " + clk_action.outputs.to_list()[0].path in main_bd_content, "Should source clock domain script")

    return analysistest.end(env)

vivado_design_test = analysistest.make(
    impl = _vivado_design_test_impl,
)

def _fpga_project_bd_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    files = target_under_test[DefaultInfo].files.to_list()
    file_names = [f.basename for f in files]

    asserts.true(env, "test_project_create_project.tcl" in file_names, "Should contain project creation script")
    asserts.true(env, "test_project_read_sources.tcl" in file_names, "Should contain read sources script")
    asserts.true(env, "test_design_bd.tcl" in file_names, "Should include top BD script in project outputs")

    asserts.true(env, FpgaProjectInfo in target_under_test, "Should provide FpgaProjectInfo")
    project_info = target_under_test[FpgaProjectInfo]
    asserts.true(env, hasattr(project_info, "files"), "FpgaProjectInfo should contain files field")
    proj_files = [f.basename for f in project_info.files.to_list()]
    asserts.true(env, "test_project_create_project.tcl" in proj_files)
    asserts.true(env, "test_design_bd.tcl" in proj_files)

    return analysistest.end(env)

fpga_project_bd_test = analysistest.make(
    impl = _fpga_project_bd_test_impl,
)

def _fpga_synthesis_bd_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    files = target_under_test[DefaultInfo].files.to_list()
    file_names = [f.basename for f in files]

    asserts.true(env, "test_synthesis.dcp" in file_names, "Should contain synthesized DCP netlist")

    actions = analysistest.target_actions(env)
    synth_action = None
    for action in actions:
        if action.mnemonic == "VivadoSynth":
            synth_action = action
            break

    asserts.true(env, synth_action != None, "VivadoSynth action should be registered")

    input_names = [f.basename for f in synth_action.inputs.to_list()]
    asserts.true(env, "test_project_create_project.tcl" in input_names, "Synthesis inputs should include project script")
    asserts.true(env, "test_design_bd.tcl" in input_names, "Synthesis inputs should include top BD script")

    return analysistest.end(env)

fpga_synthesis_bd_test = analysistest.make(
    impl = _fpga_synthesis_bd_test_impl,
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

    # Register IP declarations
    fpga_ip(
        name = "uart_ctrl_ip",
        entity_name = "uart_ctrl",
        generics = {"BAUD_RATE": "115200"},
        clock_port = "s_axi_aclk",
        reset_port = "s_axi_aresetn",
        reset_type = "active_low",
        interfaces = {"s_axi": "slave"},
        inst_tcl = "vivado_inst_my_module.tcl",
        tags = ["manual"],
    )

    fpga_ip(
        name = "my_module_ip",
        entity_name = "my_module",
        generics = {"PARAM": "1"},
        clock_port = "s_axi_aclk",
        reset_port = "s_axi_aresetn",
        reset_type = "active_low",
        interfaces = {"s_axi": "slave"},
        inst_tcl = "vivado_inst_my_module.tcl",
        tags = ["manual"],
    )

    # Register IP instances (inline instances)
    fpga_ip_inst(
        name = "u_uart_debug",
        ip = ":uart_ctrl_ip",
        instance_name = "u_uart_debug",
        generics = {"BAUD_RATE": "115200"},
        clock_domain = ":main_clk_domain",
        ooc = False,
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "u_uart_telemetry",
        ip = ":uart_ctrl_ip",
        instance_name = "u_uart_telemetry",
        generics = {"BAUD_RATE": "115200"},
        clock_domain = ":main_clk_domain",
        ooc = False,
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "u_uart_gps",
        ip = ":uart_ctrl_ip",
        instance_name = "u_uart_gps",
        generics = {"BAUD_RATE": "9600"},
        clock_domain = ":high_clk_domain",
        ooc = False,
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "u_non_ooc_ip",
        ip = ":my_module_ip",
        instance_name = "u_module_inst",
        generics = {"PARAM": "1"},
        ooc = False,
        memory_mapping = {"seg1": "0x40000000", "seg2": "0x40010000"},
        clock_domain = ":main_clk_domain",
        tags = ["manual"],
    )

    # Define fpga_design target
    fpga_design(
        name = "test_design",
        ips = [
            ":u_uart_debug",
            ":u_uart_telemetry",
            ":u_uart_gps",
            ":u_non_ooc_ip",
        ],
        top = "blinky_top",
        part = "xc7z020clg400-1",
        pre_bd_hook = "vivado_inst_my_module.tcl",
        tags = ["manual"],
    )

    # Define fpga_project target
    fpga_project(
        name = "test_project",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        design = ":test_design",
        tags = ["manual"],
    )

    # Define fpga_synthesis target
    fpga_synthesis(
        name = "test_synthesis",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        project = ":test_project",
        tags = ["manual"],
    )

    # Define analysis tests
    vivado_design_test(
        name = name + "_test",
        target_under_test = ":test_design",
    )

    fpga_project_bd_test(
        name = name + "_project_bd_test",
        target_under_test = ":test_project",
    )

    fpga_synthesis_bd_test(
        name = name + "_synthesis_bd_test",
        target_under_test = ":test_synthesis",
    )
