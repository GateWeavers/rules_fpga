FpgaSourceInfo = provider(
    doc = "Collects FPGA source files including HDL and constraints.",
    fields = {
        "vhdl_libs": "List of structs {library, sources, vhdl_version}",
        "verilog_srcs": "Depset of Verilog source files",
        "constraints": "Depset of constraint files (e.g. XDC)",
    },
)

FpgaProjectInfo = provider(
    doc = "Represents an initialized FPGA project.",
    fields = {
        "project_file": "The tool-specific project file (e.g., .xpr)",
        "tool_name": "Name of the tool that created it",
    },
)

FpgaSynthesisInfo = provider(
    doc = "Represents synthesized netlist or checkpoint.",
    fields = {
        "netlist": "The synthesized netlist file",
        "netlist_type": "String (e.g., dcp, edif, verilog)",
        "top_entity": "The top-level entity name",
        "constraints": "Depset of constraint files to be used in implementation",
    },
)

FpgaImplementationInfo = provider(
    doc = "Represents placed and routed design.",
    fields = {
        "design_checkpoint": "The routed design (e.g., .dcp)",
        "bitstream_ready": "Boolean or file indicator",
    },
)

FpgaBitstreamInfo = provider(
    doc = "Represents final bitstream files and hardware platform.",
    fields = {
        "bitstream": "The final bitstream file (.bit, .bin)",
        "debug_probes": "Probes file (.ltx)",
        "platform": "Hardware export file for software toolchains (.hdf, .xsa)",
    },
)
