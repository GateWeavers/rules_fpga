load("//fpga:providers.bzl","FpgaSourceInfo","VerilogInfo")
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "VhdlLibraryUnitInfo")

VHDL_VERSIONS = ["1993", "2002", "2008", "2019"]

TOOLCHAIN_TYPE = Label("//fpga:toolchain_type")

SOURCE_ATTRS = {
    "srcs": attr.label_list(
        allow_files = True,
        doc = "HDL sources. Accepts glob() results and filegroups. Unknown " +
              "extensions are kept as sandbox inputs.",
    ),
    "constraints": attr.label_list(
        allow_files = True,
        doc = "Constraint files (.xdc/.sdc). Accepts glob() and filegroups.",
    ),
    "deps": attr.label_list(
        providers = [[FpgaSourceInfo], [VhdlLibraryInfo], [VerilogInfo]],
        doc = "fpga_sources, fpga_ip_config (ooc = False), fpga_design, upstream " +
              "vhdl_library or rules_hdl verilog_library targets.",
    ),
    "library_name": attr.string(
        default = "work",
        doc = "VHDL library for the VHDL files in `srcs`.",
    ),
    "vhdl_version": attr.string(
        default = "2008",
        values = VHDL_VERSIONS,
        doc = "VHDL standard for the VHDL files in `srcs`.",
    ),
}

TOOLCHAIN_ATTRS = {
    "fpga_toolchain": attr.string(),
    "fpga_toolchain_version": attr.string(),
    "toolchain": attr.label(),
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}

