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
    "FpgaClockDomainInfo",
    "FpgaDesignInfo",
    "FpgaIpInfo",
    "FpgaIpInstInfo",
    "FpgaSourceInfo",
)

# ---------------------------------------------------------------------------
# Analysis Tests
# ---------------------------------------------------------------------------

def _clock_domain_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, FpgaClockDomainInfo in target, "Should provide FpgaClockDomainInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    info = target[FpgaClockDomainInfo]
    asserts.equals(env, "ps7/clk0", info.clock_pin)
    asserts.equals(env, "100MHz", info.clock_frequency)
    asserts.equals(env, "ps7/rst0", info.reset_pin)
    asserts.equals(env, "active_low", info.reset_type)

    return analysistest.end(env)

clock_domain_test = analysistest.make(_clock_domain_test_impl)

def _fpga_ip_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Must provide FpgaIpInfo and DefaultInfo
    asserts.true(env, FpgaIpInfo in target, "Should provide FpgaIpInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    # 2. Invariant: fpga_ip must NOT export FpgaSourceInfo directly
    asserts.false(env, FpgaSourceInfo in target, "fpga_ip must NOT provide FpgaSourceInfo directly")

    info = target[FpgaIpInfo]
    asserts.equals(env, "my_entity", info.entity_name)
    asserts.equals(env, "32", info.generics.get("WIDTH"))
    asserts.equals(env, "16", info.generics.get("DEPTH"))
    asserts.equals(env, "clk", info.clock_port)
    asserts.equals(env, "rst_n", info.reset_port)
    asserts.equals(env, "active_low", info.reset_type)
    asserts.equals(env, {"s_axi": "slave"}, info.interfaces)

    # 3. DefaultInfo files
    default_files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "dummy.vhd" in default_files)
    asserts.true(env, "dummy_inst.tcl" in default_files)
    asserts.true(env, "dummy_wrapper.vhd" in default_files)

    return analysistest.end(env)

fpga_ip_test = analysistest.make(_fpga_ip_test_impl)

def _fpga_ip_inst_inline_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, FpgaIpInstInfo in target, "Should provide FpgaIpInstInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    # Inline instance MUST re-export FpgaSourceInfo so RTL is part of the project
    asserts.true(env, FpgaSourceInfo in target, "Inline instance MUST provide FpgaSourceInfo")

    info = target[FpgaIpInstInfo]
    asserts.equals(env, "u_inline_1", info.instance_name)
    asserts.false(env, info.ooc, "ooc should be False")

    # Generics overlay: WIDTH was overridden to 64, DEPTH inherited default 16
    asserts.equals(env, "64", info.generics.get("WIDTH"))
    asserts.equals(env, "16", info.generics.get("DEPTH"))

    # Memory mapping
    asserts.equals(env, {"SEG_A": "0x40000000"}, info.memory_mapping)

    # Check that IP sources are in DefaultInfo
    default_files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "dummy.vhd" in default_files)

    return analysistest.end(env)

fpga_ip_inst_inline_test = analysistest.make(_fpga_ip_inst_inline_test_impl)

def _fpga_ip_inst_ooc_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, FpgaIpInstInfo in target, "Should provide FpgaIpInstInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    # OOC instance must NOT re-export FpgaSourceInfo (RTL stays out of project sources)
    asserts.false(env, FpgaSourceInfo in target, "OOC instance must NOT provide FpgaSourceInfo")

    info = target[FpgaIpInstInfo]
    asserts.equals(env, "u_ooc_1", info.instance_name)
    asserts.true(env, info.ooc, "ooc should be True")

    return analysistest.end(env)

fpga_ip_inst_ooc_test = analysistest.make(_fpga_ip_inst_ooc_test_impl)

def _fpga_ip_inst_keys_test_impl(ctx):
    env = analysistest.begin(ctx)
    target1 = analysistest.target_under_test(env)
    info1 = target1[FpgaIpInstInfo]

    # Verify synth_key and inst_key format
    asserts.true(env, "ooc=False" in info1.synth_key)
    asserts.true(env, "u_inline_1" in info1.inst_key)

    return analysistest.end(env)

fpga_ip_inst_keys_test = analysistest.make(_fpga_ip_inst_keys_test_impl)

def _fpga_design_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Provider checks
    asserts.true(env, FpgaDesignInfo in target, "Should provide FpgaDesignInfo")
    asserts.true(env, FpgaSourceInfo in target, "Should provide FpgaSourceInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    design_info = target[FpgaDesignInfo]
    asserts.equals(env, "fixture_design", design_info.design_name)
    asserts.equals(env, "top_wrapper", design_info.top_entity)
    asserts.true(env, design_info.design_script != None)
    asserts.true(env, design_info.design_script.basename.endswith("_bd.tcl"))

    # 2. Check deduplication:
    # 2 inline instances with identical entity & generics share 1 group
    # 1 OOC instance is in ooc_ips
    asserts.equals(env, 1, len(design_info.non_ooc_ips), "2 inline instances sharing generics should be 1 group")
    asserts.equals(env, 1, len(design_info.ooc_ips), "1 OOC instance should be in ooc_ips")

    # 3. Check output files in DefaultInfo
    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "fixture_design_bd.tcl" in files, "Should contain master BD script")
    asserts.true(env, "fixture_design_bd_inst.tcl" in files, "Should contain BD instantiation script")
    asserts.true(env, "fixture_design_memory_mapping.tcl" in files, "Should contain memory mapping script")
    asserts.true(env, "fixture_design_clock_domain.tcl" in files, "Should contain clock domain script")

    # 4. Check generated wrapper file for OOC instance in design sources
    design_sources = target[FpgaSourceInfo]
    vhdl_files = [f.basename for f in design_sources.vhdl_files.to_list()]
    wrapper_files = [f for f in vhdl_files if "_wrap_" in f and f.endswith(".vhd")]
    asserts.equals(env, 1, len(wrapper_files), "Should generate 1 wrapper file for OOC instance in design sources")

    # 5. Check template expansion action registered for wrapper
    actions = analysistest.target_actions(env)
    action_mnemonics = [a.mnemonic for a in actions]
    asserts.true(env, "TemplateExpand" in action_mnemonics, "Should have TemplateExpand action for wrapper")

    # 6. Check that design sources include inline IP RTL
    asserts.true(env, "dummy.vhd" in vhdl_files, "Inline IP RTL dummy.vhd should be in design sources")

    return analysistest.end(env)

fpga_design_test = analysistest.make(_fpga_design_test_impl)

# ---------------------------------------------------------------------------
# Test Suite Definition
# ---------------------------------------------------------------------------

def design_test_suite(name):
    # 1. Clock domain fixture
    fpga_clock_domain(
        name = "fixture_clk",
        clock_pin = "ps7/clk0",
        clock_frequency = "100MHz",
        reset_pin = "ps7/rst0",
        reset_type = "active_low",
        tags = ["manual"],
    )

    clock_domain_test(
        name = name + "_clock_domain_test",
        target_under_test = ":fixture_clk",
    )

    # 2. IP declaration fixture
    fpga_ip(
        name = "fixture_ip",
        entity_name = "my_entity",
        generics = {
            "WIDTH": "32",
            "DEPTH": "16",
        },
        clock_port = "clk",
        reset_port = "rst_n",
        reset_type = "active_low",
        interfaces = {"s_axi": "slave"},
        inst_tcl = "dummy_inst.tcl",
        wrapper_template = "dummy_wrapper.vhd",
        srcs = ["dummy.vhd"],
        tags = ["manual"],
    )

    fpga_ip_test(
        name = name + "_ip_test",
        target_under_test = ":fixture_ip",
    )

    # 3. Inline IP instance fixtures (2 sharing generics to test grouping, 1 distinct)
    fpga_ip_inst(
        name = "fixture_inst_inline_1",
        ip = ":fixture_ip",
        instance_name = "u_inline_1",
        generics = {"WIDTH": "64"},
        ooc = False,
        clock_domain = ":fixture_clk",
        memory_mapping = {"SEG_A": "0x40000000"},
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "fixture_inst_inline_2",
        ip = ":fixture_ip",
        instance_name = "u_inline_2",
        generics = {"WIDTH": "64"},  # Identical generics -> shares group with u_inline_1
        ooc = False,
        clock_domain = ":fixture_clk",
        memory_mapping = {"SEG_A": "0x40001000"},
        tags = ["manual"],
    )

    fpga_ip_inst(
        name = "fixture_inst_inline_3",
        ip = ":fixture_ip",
        instance_name = "u_inline_3",
        generics = {"WIDTH": "32"},  # Different generic -> 2nd group
        ooc = False,
        clock_domain = ":fixture_clk",
        tags = ["manual"],
    )

    fpga_ip_inst_inline_test(
        name = name + "_ip_inst_inline_test",
        target_under_test = ":fixture_inst_inline_1",
    )

    fpga_ip_inst_keys_test(
        name = name + "_ip_inst_keys_test",
        target_under_test = ":fixture_inst_inline_1",
    )

    # 4. OOC IP instance fixture (tests OOC provider behavior without calling _hdl_name)
    fpga_ip_inst(
        name = "fixture_inst_ooc_1",
        ip = ":fixture_ip",
        instance_name = "u_ooc_1",
        generics = {"WIDTH": "32"},
        ooc = True,
        clock_domain = ":fixture_clk",
        tags = ["manual"],
    )

    fpga_ip_inst_ooc_test(
        name = name + "_ip_inst_ooc_test",
        target_under_test = ":fixture_inst_ooc_1",
    )

    # 5. FPGA Design fixture (both inline and OOC instances)
    fpga_design(
        name = "fixture_design",
        top = "top_wrapper",
        part = "xc7z020clg400-1",
        ips = [
            ":fixture_inst_inline_1",
            ":fixture_inst_inline_2",
            ":fixture_inst_ooc_1",
        ],
        pre_bd_hook = "dummy_hook.tcl",
        post_bd_hook = "dummy_hook.tcl",
        tags = ["manual"],
    )

    fpga_design_test(
        name = name + "_fpga_design_test",
        target_under_test = ":fixture_design",
    )
