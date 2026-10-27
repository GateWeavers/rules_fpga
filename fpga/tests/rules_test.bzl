load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//fpga:design.bzl",
    "fpga_clock_domain",
    "fpga_design",
    "fpga_ip",
    "fpga_ip_inst",
)
load(
    "//fpga:providers.bzl",
    "FpgaBitstreamInfo",
    "FpgaDesignInfo",
    "FpgaImplementationInfo",
    "FpgaProjectInfo",
    "FpgaSynthesisInfo",
)
load(
    "//fpga:rules.bzl",
    "fpga_bitstream",
    "fpga_flow",
    "fpga_implementation",
    "fpga_project",
    "fpga_synthesis",
)

# ---------------------------------------------------------------------------
# Analysis Tests
# ---------------------------------------------------------------------------

def _fpga_project_standalone_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Provider checks
    asserts.true(env, FpgaProjectInfo in target, "Should provide FpgaProjectInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    proj_info = target[FpgaProjectInfo]
    asserts.equals(env, "fixture_standalone_proj", proj_info.project_name)
    asserts.equals(env, "vivado", proj_info.tool_name)
    asserts.true(env, proj_info.project_script != None)
    asserts.true(env, proj_info.project_script.basename.endswith("_create_project.tcl"))

    # 2. Output files check
    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "fixture_standalone_proj_create_project.tcl" in files)
    asserts.true(env, "fixture_standalone_proj_read_sources.tcl" in files)
    asserts.true(env, "dummy.vhd" in files)
    asserts.true(env, "dummy.v" in files)
    asserts.true(env, "dummy.xdc" in files)

    return analysistest.end(env)

fpga_project_standalone_test = analysistest.make(_fpga_project_standalone_test_impl)

def _fpga_project_with_design_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, FpgaProjectInfo in target, "Should provide FpgaProjectInfo")

    # The design's master BD script should be part of the project files
    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "fixture_rules_design_bd.tcl" in files, "Should include design master BD script in project files")

    return analysistest.end(env)

fpga_project_with_design_test = analysistest.make(_fpga_project_with_design_test_impl)

def _fpga_synthesis_in_memory_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Provider checks
    asserts.true(env, FpgaSynthesisInfo in target, "Should provide FpgaSynthesisInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")
    asserts.true(env, OutputGroupInfo in target, "Should provide OutputGroupInfo")

    synth_info = target[FpgaSynthesisInfo]
    asserts.equals(env, "blinky_top", synth_info.top_entity)
    asserts.equals(env, "xc7z020clg400-1", synth_info.part)
    asserts.equals(env, "dcp", synth_info.netlist_type)
    asserts.true(env, synth_info.netlist.basename.endswith(".dcp"))

    # 2. Outputs check
    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "fixture_in_memory_synth.dcp" in files)

    # 3. Action check: VivadoSynth registered
    actions = analysistest.target_actions(env)
    synth_action = None
    for a in actions:
        if a.mnemonic == "VivadoSynth":
            synth_action = a
            break

    asserts.true(env, synth_action != None, "VivadoSynth action must be registered")

    action_outputs = [f.basename for f in synth_action.outputs.to_list()]
    asserts.true(env, "fixture_in_memory_synth.dcp" in action_outputs)
    asserts.true(env, "fixture_in_memory_synth_synth.log" in action_outputs)
    asserts.true(env, "fixture_in_memory_synth_synth_timing.rpt" in action_outputs)
    asserts.true(env, "fixture_in_memory_synth_synth_utilization.rpt" in action_outputs)

    return analysistest.end(env)

fpga_synthesis_in_memory_test = analysistest.make(_fpga_synthesis_in_memory_test_impl)

def _fpga_synthesis_with_project_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, FpgaSynthesisInfo in target, "Should provide FpgaSynthesisInfo")

    # Synthesis action inputs must include the project creation script
    actions = analysistest.target_actions(env)
    synth_action = None
    for a in actions:
        if a.mnemonic == "VivadoSynth":
            synth_action = a
            break

    asserts.true(env, synth_action != None, "VivadoSynth action must be registered")
    input_names = [f.basename for f in synth_action.inputs.to_list()]
    asserts.true(env, "fixture_standalone_proj_create_project.tcl" in input_names, "Should include project script in synthesis inputs")

    return analysistest.end(env)

fpga_synthesis_with_project_test = analysistest.make(_fpga_synthesis_with_project_test_impl)

def _fpga_implementation_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Provider checks
    asserts.true(env, FpgaImplementationInfo in target, "Should provide FpgaImplementationInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    impl_info = target[FpgaImplementationInfo]
    asserts.equals(env, "blinky_top", impl_info.top_entity)
    asserts.equals(env, "xc7z020clg400-1", impl_info.part)
    asserts.true(env, impl_info.design_checkpoint.basename.endswith("_routed.dcp"))

    # 2. Action checks
    actions = analysistest.target_actions(env)
    impl_action = None
    for a in actions:
        if a.mnemonic == "VivadoImpl":
            impl_action = a
            break

    asserts.true(env, impl_action != None, "VivadoImpl action must be registered")
    input_names = [f.basename for f in impl_action.inputs.to_list()]
    asserts.true(env, "fixture_in_memory_synth.dcp" in input_names, "Implementation input must include synthesis checkpoint")

    output_names = [f.basename for f in impl_action.outputs.to_list()]
    asserts.true(env, "fixture_impl_routed.dcp" in output_names)
    asserts.true(env, "fixture_impl_impl_timing.rpt" in output_names)
    asserts.true(env, "fixture_impl_impl_utilization.rpt" in output_names)
    asserts.true(env, "fixture_impl_route_status.rpt" in output_names)

    return analysistest.end(env)

fpga_implementation_test = analysistest.make(_fpga_implementation_test_impl)

def _fpga_bitstream_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Provider checks
    asserts.true(env, FpgaBitstreamInfo in target, "Should provide FpgaBitstreamInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    bit_info = target[FpgaBitstreamInfo]
    asserts.true(env, bit_info.bitstream.basename.endswith(".bit"))
    asserts.true(env, bit_info.debug_probes.basename.endswith(".ltx"))
    asserts.true(env, bit_info.platform.basename.endswith(".xsa"))

    # 2. Action checks
    actions = analysistest.target_actions(env)
    bit_action = None
    for a in actions:
        if a.mnemonic == "VivadoBitstream":
            bit_action = a
            break

    asserts.true(env, bit_action != None, "VivadoBitstream action must be registered")
    input_names = [f.basename for f in bit_action.inputs.to_list()]
    asserts.true(env, "fixture_impl_routed.dcp" in input_names, "Bitstream inputs must include routed checkpoint")

    output_names = [f.basename for f in bit_action.outputs.to_list()]
    asserts.true(env, "fixture_bit.bit" in output_names)
    asserts.true(env, "fixture_bit.ltx" in output_names)
    asserts.true(env, "fixture_bit.xsa" in output_names)

    return analysistest.end(env)

fpga_bitstream_test = analysistest.make(_fpga_bitstream_test_impl)

def _fpga_flow_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # The main target of fpga_flow is fpga_bitstream
    asserts.true(env, FpgaBitstreamInfo in target, "Main flow target should provide FpgaBitstreamInfo")
    asserts.true(env, DefaultInfo in target, "Main flow target should provide DefaultInfo")

    return analysistest.end(env)

fpga_flow_test = analysistest.make(_fpga_flow_test_impl)

def _synthesis_mutual_exclusive_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "'project' is mutually exclusive with srcs/constraints/deps")
    return analysistest.end(env)

synthesis_mutual_exclusive_failure_test = analysistest.make(
    _synthesis_mutual_exclusive_failure_test_impl,
    expect_failure = True,
)

# ---------------------------------------------------------------------------
# Test Suite Definition
# ---------------------------------------------------------------------------

def rules_test_suite(name):
    # 1. Project Standalone fixture
    fpga_project(
        name = "fixture_standalone_proj",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        srcs = [
            "dummy.vhd",
            "dummy.v",
        ],
        constraints = ["dummy.xdc"],
        tags = ["manual"],
    )

    fpga_project_standalone_test(
        name = name + "_project_standalone_test",
        target_under_test = ":fixture_standalone_proj",
    )

    # 2. Design and Project with design fixture
    fpga_clock_domain(
        name = "fixture_rules_clk",
        clock_pin = "ps7/clk0",
        reset_pin = "ps7/rst0",
        tags = ["manual"],
    )

    fpga_ip(
        name = "fixture_rules_ip",
        entity_name = "rules_entity",
        inst_tcl = "dummy_inst.tcl",
        srcs = ["dummy.vhd"],
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "fixture_rules_inst",
        ip = ":fixture_rules_ip",
        clock_domain = ":fixture_rules_clk",
        ooc = False,
        tags = ["manual"],
    )

    fpga_design(
        name = "fixture_rules_design",
        top = "top_wrapper",
        part = "xc7z020clg400-1",
        ips = [":fixture_rules_inst"],
        tags = ["manual"],
    )

    fpga_project(
        name = "fixture_design_proj",
        top = "top_wrapper",
        part = "xc7z020clg400-1",
        design = ":fixture_rules_design",
        tags = ["manual"],
    )

    fpga_project_with_design_test(
        name = name + "_project_with_design_test",
        target_under_test = ":fixture_design_proj",
    )

    # 3. Synthesis in-memory fixture
    fpga_synthesis(
        name = "fixture_in_memory_synth",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        srcs = ["dummy.vhd"],
        constraints = ["dummy.xdc"],
        generics = {"CLK_HZ": "50000000"},
        defines = {"DEBUG": "1"},
        synth_options = ["-flatten_hierarchy full"],
        max_threads = 4,
        memory = 4000,
        tags = ["manual"],
    )

    fpga_synthesis_in_memory_test(
        name = name + "_synthesis_in_memory_test",
        target_under_test = ":fixture_in_memory_synth",
    )

    # 4. Synthesis with project fixture
    fpga_synthesis(
        name = "fixture_proj_synth",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        project = ":fixture_standalone_proj",
        tags = ["manual"],
    )

    fpga_synthesis_with_project_test(
        name = name + "_synthesis_with_project_test",
        target_under_test = ":fixture_proj_synth",
    )

    # 5. Implementation fixture
    fpga_implementation(
        name = "fixture_impl",
        synthesis = ":fixture_in_memory_synth",
        part = "xc7z020clg400-1",
        impl_options = {
            "opt": ["-directive Explore"],
            "place": ["-directive Explore"],
        },
        tags = ["manual"],
    )

    fpga_implementation_test(
        name = name + "_implementation_test",
        target_under_test = ":fixture_impl",
    )

    # 6. Bitstream fixture
    fpga_bitstream(
        name = "fixture_bit",
        implementation = ":fixture_impl",
        part = "xc7z020clg400-1",
        bit_options = ["-bin_file"],
        tags = ["manual"],
    )

    fpga_bitstream_test(
        name = name + "_bitstream_test",
        target_under_test = ":fixture_bit",
    )

    # 7. Flow macro fixture
    fpga_flow(
        name = "fixture_flow",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        srcs = ["dummy.vhd"],
        constraints = ["dummy.xdc"],
        tags = ["manual"],
    )

    fpga_flow_test(
        name = name + "_flow_test",
        target_under_test = ":fixture_flow",
    )

    # 8. Negative test: Mutual exclusivity in synthesis
    fpga_synthesis(
        name = "fixture_synthesis_invalid_mutual_exclusive",
        top = "blinky_top",
        part = "xc7z020clg400-1",
        project = ":fixture_standalone_proj",
        srcs = ["dummy.vhd"],  # Invalid: cannot specify both project and srcs
        tags = ["manual"],
    )

    synthesis_mutual_exclusive_failure_test(
        name = name + "_synthesis_mutual_exclusive_test",
        target_under_test = ":fixture_synthesis_invalid_mutual_exclusive",
    )
