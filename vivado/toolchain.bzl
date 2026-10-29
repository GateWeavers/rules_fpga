"""Vivado FPGA toolchain definition for rules_fpga.

This module defines `vivado_toolchain`, which packages the Vivado-specific
implementation callbacks and TCL script templates into an `FpgaToolchainInfo`
provider wrapped inside Bazel's standard `platform_common.ToolchainInfo`.

When targets such as `fpga_synthesis`, `fpga_implementation`, `fpga_bitstream`,
`fpga_project`, or `fpga_design` resolve the `//fpga:toolchain_type` toolchain,
they obtain this provider and delegate action generation and TCL emission
to the functions configured here.
"""

load("//fpga:toolchain.bzl", "FpgaToolchainInfo")
load(
    ":vivado.bzl",
    "vivado_bitstream",
    "vivado_create_project",
    "vivado_dcp_gui",
    "vivado_generate_design",
    "vivado_implementation",
    "vivado_project_gui",
    "vivado_synthesis",
)

def _vivado_toolchain_impl(ctx):
    """Initializes the Vivado FPGA toolchain provider."""
    return [
        platform_common.ToolchainInfo(
            fpga_info = FpgaToolchainInfo(
                type = "vivado",
                setup_cmd = ctx.attr.setup_cmd,
                cmd = ctx.attr.cmd,
                create_project = vivado_create_project,
                generate_design = vivado_generate_design,
                synthesis = vivado_synthesis,
                implementation = vivado_implementation,
                bitstream = vivado_bitstream,
                project_gui = vivado_project_gui,
                dcp_gui = vivado_dcp_gui,
                templates = struct(
                    create_project = ctx.file.create_project_tpl,
                    synthesis = ctx.file.synthesis_tpl,
                    implementation = ctx.file.implementation_tpl,
                    bitstream = ctx.file.bitstream_tpl,
                    clock_domain = ctx.file.clock_domain_tpl,
                ),
            ),
        ),
    ]

vivado_toolchain = rule(
    implementation = _vivado_toolchain_impl,
    doc = """Defines a Vivado FPGA toolchain instance.

Packages executable paths, environment setup commands, and TCL workflow
templates required to run AMD/Xilinx Vivado flows in batch mode and GUI mode.

In modern Bzlmod setups, instances of this rule are generated automatically by
the `vivado_toolchains` module extension (from `//vivado:extensions.bzl`).
However, this rule may also be instantiated manually in a `BUILD` file to define
a bespoke Vivado toolchain with customized TCL templates or invocation wrappers.

Example (manual definition):
```bzl
load("@gateweavers_rules_fpga//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "custom_vivado_impl",
    cmd = "vivado",
    setup_cmd = "source /opt/Xilinx/Vivado/2024.2/settings64.sh",
    synthesis_tpl = "//my_custom_templates:synthesis.tcl",
)

toolchain(
    name = "custom_vivado",
    toolchain = ":custom_vivado_impl",
    toolchain_type = "@gateweavers_rules_fpga//fpga:toolchain_type",
)
```
""",
    attrs = {
        "setup_cmd": attr.string(
            doc = "Optional shell command executed prior to invoking Vivado (e.g. 'source /opt/Xilinx/Vivado/2024.2/settings64.sh').",
        ),
        "cmd": attr.string(
            default = "vivado",
            doc = "The command name or absolute path to the Vivado binary (default: 'vivado').",
        ),
        "create_project_tpl": attr.label(
            allow_single_file = [".tcl"],
            default = "//vivado/templates:create_project.tcl",
            doc = "TCL template used by `fpga_project` to generate the project creation script.",
        ),
        "synthesis_tpl": attr.label(
            allow_single_file = [".tcl"],
            default = "//vivado/templates:synthesis.tcl",
            doc = "TCL template used by `fpga_synthesis` to run standalone in-memory or project-based synthesis.",
        ),
        "implementation_tpl": attr.label(
            allow_single_file = [".tcl"],
            default = "//vivado/templates:implementation.tcl",
            doc = "TCL template used by `fpga_implementation` for Place & Route (opt, place, phys_opt, route).",
        ),
        "bitstream_tpl": attr.label(
            allow_single_file = [".tcl"],
            default = "//vivado/templates:bitstream.tcl",
            doc = "TCL template used by `fpga_bitstream` to generate bitstreams (.bit), debug probes (.ltx), and hardware platforms (.xsa).",
        ),
        "clock_domain_tpl": attr.label(
            allow_single_file = [".tcl"],
            default = "//vivado/templates:clock_domain.tcl",
            doc = "TCL template providing clock/reset automation and AXI connection procedures used by `fpga_design`.",
        ),
    },
)
