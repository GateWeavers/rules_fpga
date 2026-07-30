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
        "project_script": "The project creation script (TCL)",
        "project_name": "Name of the project",
        "tool_name": "Name of the tool that created it",
        "sources": "FpgaSourceInfo: The source files associated with this project",
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

FpgaClockDomainInfo = provider(
    doc = "Structured clock domain metadata.",
    fields = {
        "clock_pin": "String: Clock pin object.",
        "clock_frequency": "String: Clock frequency.",
        "reset_pin": "String: Reset pin object.",
        "reset_type": "String: active_low or active_high.",
    },
)

FpgaIpInfo = provider(
    doc = "Configuration metadata for an Out-of-Context FPGA IP module.",
    fields = {
        "entity_name": "The name of the IP's top-level entity/module.",
        "instance_name": "The unique instance name used inside the top-level design.",
        "generics": "Dictionary of generic parameter configurations.",
        "sources": "FpgaSourceInfo: RTL and constraint files for the IP.",
        "memory_mapping": "Optional memory mapping details (e.g., register specifications).",
        "ooc": "Boolean flag determining if out-of-context synthesis is needed.",
        "inst_tcl": "File: Optional TCL script template for BD instantiation.",
        "clock_domain": "FpgaClockDomainInfo: Optional reference clock domain info.",
    },
)
