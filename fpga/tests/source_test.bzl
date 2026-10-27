load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//fpga:providers.bzl", "FpgaSourceInfo")
load(
    "//fpga:source.bzl",
    "classify_files",
    "fpga_sources",
    "merge_source_infos",
    "source_files",
    "to_vhdl_library_info",
)
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "vhdl_library")

# ---------------------------------------------------------------------------
# Pure Starlark Unit Tests
# ---------------------------------------------------------------------------

def _classify_files_test_impl(ctx):
    env = unittest.begin(ctx)

    mock_files = [
        struct(path = "a.vhd", extension = "vhd"),
        struct(path = "b.vhdl", extension = "vhdl"),
        struct(path = "c.v", extension = "v"),
        struct(path = "d.sv", extension = "sv"),
        struct(path = "e.vh", extension = "vh"),
        struct(path = "f.svh", extension = "svh"),
        struct(path = "g.xdc", extension = "xdc"),
        struct(path = "h.sdc", extension = "sdc"),
        struct(path = "i.mem", extension = "mem"),
        struct(path = "j.dat", extension = "dat"),
    ]

    res = classify_files(mock_files)

    asserts.equals(env, ["a.vhd", "b.vhdl"], [f.path for f in res.vhdl])
    asserts.equals(env, ["c.v", "d.sv"], [f.path for f in res.verilog])
    asserts.equals(env, ["e.vh", "f.svh"], [f.path for f in res.headers])
    asserts.equals(env, ["g.xdc", "h.sdc"], [f.path for f in res.constraints])
    asserts.equals(env, ["i.mem", "j.dat"], [f.path for f in res.data])

    return unittest.end(env)

classify_files_test = unittest.make(_classify_files_test_impl)

def _merge_source_infos_test_impl(ctx):
    env = unittest.begin(ctx)

    f1 = struct(path = "f1.v")
    f2 = struct(path = "f2.v")
    c1 = struct(path = "c1.xdc")
    c2 = struct(path = "c2.xdc")

    info1 = FpgaSourceInfo(
        verilog_srcs = depset([f1]),
        constraints = depset([c1]),
    )
    info2 = FpgaSourceInfo(
        verilog_srcs = depset([f2]),
        constraints = depset([c2]),
    )

    merged = merge_source_infos([info1, info2])

    v_paths = [f.path for f in merged.verilog_srcs.to_list()]
    c_paths = [f.path for f in merged.constraints.to_list()]

    asserts.true(env, "f1.v" in v_paths)
    asserts.true(env, "f2.v" in v_paths)
    asserts.true(env, "c1.xdc" in c_paths)
    asserts.true(env, "c2.xdc" in c_paths)

    # Merging a single info returns itself
    single_merged = merge_source_infos([info1])
    asserts.equals(env, info1, single_merged)

    return unittest.end(env)

merge_source_infos_test = unittest.make(_merge_source_infos_test_impl)

# ---------------------------------------------------------------------------
# Analysis Tests
# ---------------------------------------------------------------------------

def _fpga_sources_direct_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check providers
    asserts.true(env, FpgaSourceInfo in target, "Should provide FpgaSourceInfo")
    asserts.true(env, DefaultInfo in target, "Should provide DefaultInfo")

    src = target[FpgaSourceInfo]

    # 2. Check VHDL library info
    units = src.vhdl_libs.to_list()
    asserts.equals(env, 1, len(units), "Should have exactly 1 VHDL unit")
    asserts.equals(env, "custom_lib", units[0].library_name)
    asserts.equals(env, "2008", units[0].vhdl_version)
    vhdl_unit_files = [f.basename for f in units[0].sources.to_list()]
    asserts.true(env, "dummy.vhd" in vhdl_unit_files)

    # 3. Check direct files
    asserts.true(env, "dummy.vhd" in [f.basename for f in src.vhdl_files.to_list()])
    asserts.true(env, "dummy.v" in [f.basename for f in src.verilog_srcs.to_list()])
    asserts.true(env, "dummy_header.vh" in [f.basename for f in src.verilog_headers.to_list()])
    asserts.true(env, "dummy.xdc" in [f.basename for f in src.constraints.to_list()])
    asserts.true(env, "dummy_data.mem" in [f.basename for f in src.data.to_list()])

    # 4. Check DefaultInfo files
    default_files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "dummy.vhd" in default_files)
    asserts.true(env, "dummy.v" in default_files)
    asserts.true(env, "dummy_header.vh" in default_files)
    asserts.true(env, "dummy.xdc" in default_files)
    asserts.true(env, "dummy_data.mem" in default_files)

    return analysistest.end(env)

fpga_sources_direct_test = analysistest.make(_fpga_sources_direct_test_impl)

def _fpga_sources_dep_chain_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    src = target[FpgaSourceInfo]

    # Postorder check: child dependencies must appear before parent
    units = src.vhdl_libs.to_list()
    asserts.equals(env, 2, len(units), "Should contain both child and parent VHDL units")
    asserts.equals(env, "child_lib", units[0].library_name, "Dependency unit must come first (postorder)")
    asserts.equals(env, "parent_lib", units[1].library_name, "Parent unit must come last")

    all_vhdl = [f.basename for f in src.vhdl_files.to_list()]
    asserts.true(env, "dummy.vhd" in all_vhdl)

    all_verilog = [f.basename for f in src.verilog_srcs.to_list()]
    asserts.true(env, "dummy.v" in all_verilog)

    return analysistest.end(env)

fpga_sources_dep_chain_test = analysistest.make(_fpga_sources_dep_chain_test_impl)

def _rules_vhdl_interop_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    src = target[FpgaSourceInfo]
    units = src.vhdl_libs.to_list()
    lib_names = [u.library_name for u in units]

    asserts.true(env, "ext_vhdl_lib" in lib_names, "Should absorb vhdl_library dependency from @gateweaver_rules_vhdl")

    return analysistest.end(env)

rules_vhdl_interop_test = analysistest.make(_rules_vhdl_interop_test_impl)

# ---------------------------------------------------------------------------
# Suite Definition
# ---------------------------------------------------------------------------

def source_test_suite(name):
    # Pure unit tests
    classify_files_test(name = name + "_classify_files_test")
    merge_source_infos_test(name = name + "_merge_source_infos_test")

    # Target: Direct sources
    fpga_sources(
        name = "fixture_direct_sources",
        srcs = [
            "dummy.vhd",
            "dummy.v",
            "dummy_header.vh",
            "dummy_data.mem",
        ],
        constraints = ["dummy.xdc"],
        library_name = "custom_lib",
        vhdl_version = "2008",
        tags = ["manual"],
    )

    fpga_sources_direct_test(
        name = name + "_direct_sources_test",
        target_under_test = ":fixture_direct_sources",
    )

    # Target: Dependency chain (child -> parent)
    fpga_sources(
        name = "fixture_child_sources",
        srcs = ["dummy.vhd"],
        library_name = "child_lib",
        vhdl_version = "2008",
        tags = ["manual"],
    )

    fpga_sources(
        name = "fixture_parent_sources",
        srcs = ["dummy.vhd", "dummy.v"],
        deps = [":fixture_child_sources"],
        library_name = "parent_lib",
        vhdl_version = "2008",
        tags = ["manual"],
    )

    fpga_sources_dep_chain_test(
        name = name + "_dep_chain_test",
        target_under_test = ":fixture_parent_sources",
    )

    # Target: rules_vhdl interop (vhdl_library -> fpga_sources)
    vhdl_library(
        name = "fixture_rules_vhdl_lib",
        srcs = ["dummy.vhd"],
        library_name = "ext_vhdl_lib",
        vhdl_version = "2008",
        tags = ["manual"],
    )

    fpga_sources(
        name = "fixture_interop_sources",
        deps = [":fixture_rules_vhdl_lib"],
        library_name = "top_work",
        tags = ["manual"],
    )

    rules_vhdl_interop_test(
        name = name + "_interop_test",
        target_under_test = ":fixture_interop_sources",
    )
