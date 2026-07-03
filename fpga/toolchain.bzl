FpgaToolchainInfo = provider(
    doc = "Defines the interface for FPGA tools.",
    fields = {
        "type": "The type of the toolchain (e.g. vivado, yosys)",
        "setup_cmd": "Optional setup command to run before the main command (e.g. source settings64.sh)",
        "cmd": "The main command to run the tool (e.g. vivado)",
        "create_project": "Function(ctx, toolchain_info, source_info, part, top) -> FpgaProjectInfo",
        "synthesis": "Function(ctx, toolchain_info, project_info, source_info, top, part, generics, defines, max_threads, synth_options, pre_synth_tcl, post_synth_tcl) -> FpgaSynthesisInfo",
        "implementation": "Function(ctx, toolchain_info, synthesis_info, project_info, part, max_threads, impl_options, pre_impl_tcl, post_impl_tcl) -> FpgaImplementationInfo",
        "bitstream": "Function(ctx, toolchain_info, implementation_info, project_info, part, bit_options, pre_bit_tcl, post_bit_tcl) -> FpgaBitstreamInfo",
        "templates": "Optional struct of tool-specific templates",
    },
)
