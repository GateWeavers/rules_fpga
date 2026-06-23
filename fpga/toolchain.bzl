FpgaToolchainInfo = provider(
    doc = "Defines the interface for FPGA tools.",
    fields = {
        "type": "The type of the toolchain (e.g. vivado, yosys)",
        "setup_cmd": "Optional setup command to run before the main command (e.g. source settings64.sh)",
        "cmd": "The main command to run the tool (e.g. vivado)",
        "create_project": "Function(ctx, toolchain_info, source_info, part, top) -> FpgaProjectInfo",
        "synthesis": "Function(ctx, toolchain_info, project_info, source_info, top, part) -> FpgaSynthesisInfo",
        "implementation": "Function(ctx, toolchain_info, synthesis_info, project_info, part) -> FpgaImplementationInfo",
        "bitstream": "Function(ctx, toolchain_info, implementation_info, project_info, part) -> FpgaBitstreamInfo",
        "templates": "Optional struct of tool-specific templates",
    },
)
