load("//fpga:toolchain.bzl", "FpgaToolchainInfo")
load(":vivado.bzl", "vivado_create_project","vivado_synthesis", "vivado_implementation", "vivado_bitstream")

def _vivado_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            fpga_info = FpgaToolchainInfo(
                type = "vivado",
                setup_cmd = ctx.attr.setup_cmd,
                cmd = ctx.attr.cmd,
                create_project = vivado_create_project,
                synthesis = vivado_synthesis,
                implementation = vivado_implementation,
                bitstream = vivado_bitstream,
                templates = struct(
                    create_project = ctx.file.create_project_tpl,
                    synthesis = ctx.file.synthesis_tpl,
                    implementation = ctx.file.implementation_tpl,
                    bitstream = ctx.file.bitstream_tpl,
                ),
            ),
        ),
    ]

vivado_toolchain = rule(
    implementation = _vivado_toolchain_impl,
    attrs = {
        "setup_cmd": attr.string(doc = "Optional setup command (e.g. source settings64.sh)"),
        "cmd": attr.string(default = "vivado", doc = "Vivado command name"),
        "create_project_tpl": attr.label(allow_single_file = [".tcl"], default = "//vivado/templates:create_project.tcl"),
        "synthesis_tpl": attr.label(allow_single_file = [".tcl"], default = "//vivado/templates:synthesis.tcl"),
        "implementation_tpl": attr.label(allow_single_file = [".tcl"], default = "//vivado/templates:implementation.tcl"),
        "bitstream_tpl": attr.label(allow_single_file = [".tcl"], default = "//vivado/templates:bitstream.tcl"),
    },
)
