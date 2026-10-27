"""
Canonical providers for the FPGA rules.
"""

_RESET_TYPES = ["active_low", "active_high"]

def _depset_or_empty(name, value, order = "default"):
    if value == None:
        return depset(order = order)
    if type(value) != "depset":
        fail("%s must be a depset, got %s" % (name, type(value)))
    return value

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

def _source_info_init(
        *,
        vhdl_libs = None,
        vhdl_files = None,
        verilog_srcs = None,
        verilog_headers = None,
        constraints = None,
        data = None):
    return {
        # Depset of VhdlLibraryUnitInfo to store vhdl files.
        "vhdl_libs": _depset_or_empty("vhdl_libs", vhdl_libs, "postorder"),
        # Same files, flat: use this for action inputs / DefaultInfo
        "vhdl_files": _depset_or_empty("vhdl_files", vhdl_files),
        "verilog_srcs": _depset_or_empty("verilog_srcs", verilog_srcs),
        "verilog_headers": _depset_or_empty("verilog_headers", verilog_headers),
        "constraints": _depset_or_empty("constraints", constraints),
        # Anything else a flow needs in the sandbox: .mem/.coe/.dat/.xci/...
        "data": _depset_or_empty("data", data),
    }

FpgaSourceInfo, _FpgaSourceInfo = provider(
    doc = "All HDL, constraint and auxiliary inputs of a target (transitive).",
    fields = {
        "vhdl_libs": "depset[VhdlLibraryUnitInfo], postorder: dependencies before dependents.",
        "vhdl_files": "depset[File]: every VHDL file in vhdl_libs (flat, for action inputs).",
        "verilog_srcs": "depset[File]: .v/.sv sources.",
        "verilog_headers": "depset[File]: .vh/.svh headers (inputs only).",
        "constraints": "depset[File]: .xdc/.sdc.",
        "data": "depset[File]: any other file that must be present in the sandbox.",
    },
    init = _source_info_init,
)

# ---------------------------------------------------------------------------
# Block design metadata
# ---------------------------------------------------------------------------

def _clock_domain_init(*, clock_pin, reset_pin, reset_type = "active_low", clock_frequency = ""):
    if reset_type not in _RESET_TYPES:
        fail("reset_type must be one of %s, got '%s'" % (_RESET_TYPES, reset_type))
    return {
        "clock_pin": clock_pin,
        "clock_frequency": clock_frequency,
        "reset_pin": reset_pin,
        "reset_type": reset_type,
    }

FpgaClockDomainInfo, _FpgaClockDomainInfo = provider(
    doc = "Clock domain metadata.",
    fields = {
        "clock_pin": "String: Tcl expression or pin name of the clock.",
        "clock_frequency": "String: clock frequency (informational).",
        "reset_pin": "String: Tcl expression or pin name of the reset.",
        "reset_type": "String: active_low or active_high.",
    },
    init = _clock_domain_init,
)

_INTERFACE_ROLES = ["master", "slave"]

def _fmt_generics(generics):
    return ";".join(["%s=%s" % (k, generics[k]) for k in sorted(generics.keys())])

def _ip_init(
        *,
        label,
        entity_name,
        sources,
        generics = None,
        # required_generics = None,
        inst_tcl = None,
        wrapper_template = None,
        clock_port = "aclk",
        reset_port = "aresetn",
        reset_type = "active_low",
        interfaces = None):
    generics = generics or {}
    # required_generics = required_generics or []
    interfaces = interfaces or {}
    # both = [g for g in required_generics if g in generics]
    # if both:
        # fail("%s: generics %s are both defaulted and required" % (label, both))
    if reset_type not in _RESET_TYPES:
        fail("%s: reset_type must be one of %s" % (label, _RESET_TYPES))
    for name, role in interfaces.items():
        if role not in _INTERFACE_ROLES:
            fail("%s: interface '%s' has role '%s', expected one of %s" % (
                label,
                name,
                role,
                _INTERFACE_ROLES,
            ))
    return {
        "label": label,
        "entity_name": entity_name,
        "sources": sources,
        "generics": generics,
        # "required_generics": required_generics,
        "inst_tcl": inst_tcl,
        "wrapper_template": wrapper_template,
        "clock_port": clock_port,
        "reset_port": reset_port,
        "reset_type": reset_type,
        "interfaces": interfaces,
    }

FpgaIpInfo, _FpgaIpInfo = provider(
    doc = "Declaration of an IP (module). Holds what is shared by all its instances.",
    fields = {
        "label": "String: package-relative identity of the fpga_ip target (repo-independent).",
        "entity_name": "String: top-level entity/module of the IP.",
        "sources": "FpgaSourceInfo: RTL/constraints of the IP. Never exported through the target itself.",
        "generics": "dict[str, str]: declared generics with default values.",
        "inst_tcl": "File or None: BD instantiation procedure (inline instances).",
        "wrapper_template": "File or None: hand-written wrapper template (OOC instances). " +
                            "Placeholders are {{<generic name>}} plus {{WRAPPER_NAME}} and {{OOC_SYNTH_NAME}}.",
        "clock_port": "String: clock port name.",
        "reset_port": "String: reset port name.",
        "reset_type": "String: active_low or active_high.",
        "interfaces": "dict[str, str]: wired memory-mapped interfaces and their role (master/slave).",
    },
    init = _ip_init,
)

def _ip_inst_init(
        *,
        ip,
        instance_name,
        ooc,
        generics = None,
        clock_domain = None,
        memory_mapping = None):
    overrides = generics or {}
    declared = list(ip.generics.keys()) #+ list(ip.required_generics)
    unknown = [g for g in overrides if g not in declared]
    if unknown:
        fail("%s: unknown generics %s for IP %s (declared: %s)" % (
            instance_name,
            unknown,
            ip.label,
            declared,
        ))
    resolved = dict(ip.generics)
    resolved.update(overrides)
    # missing = [g for g in ip.required_generics if g not in resolved]
    # if missing:
        # fail("%s: required generics %s of IP %s are not set" % (instance_name, missing, ip.label))
    if ooc and not ip.wrapper_template:
        fail("%s: OOC instance requires IP %s to declare wrapper_template" % (instance_name, ip.label))
    if not ooc and not ip.inst_tcl:
        fail("%s: inline instance requires IP %s to declare inst_tcl" % (instance_name, ip.label))
    memory_mapping = memory_mapping or {}
    return {
        "ip": ip,
        "instance_name": instance_name,
        "ooc": ooc,
        "generics": resolved,
        "clock_domain": clock_domain,
        "memory_mapping": memory_mapping,
        # Instances with equal synth_key share one synthesis. It contains the
        # IP identity, the RESOLVED generics (an explicit default and an omitted
        # one dedup) and the ooc flag, so OOC and inline never share a group.
        "synth_key": "%s|%s|ooc=%s" % (ip.label, _fmt_generics(resolved), ooc),
        # Unique per instance (name + generics); basis of the wrapper name.
        "inst_key": "%s|%s" % (instance_name, _fmt_generics(resolved)),
    }

FpgaIpInstInfo, _FpgaIpInstInfo = provider(
    doc = "One instance of an fpga_ip.",
    fields = {
        "ip": "FpgaIpInfo.",
        "instance_name": "String: instance name inside the top-level design.",
        "ooc": "bool: synthesize out-of-context and instantiate through a wrapper.",
        "generics": "dict[str, str]: resolved generics (defaults overlaid with instance values).",
        "clock_domain": "FpgaClockDomainInfo or None.",
        "memory_mapping": "dict[str, str]: interface name -> address segment.",
        "synth_key": "String: grouping key for shared synthesis (computed).",
        "inst_key": "String: unique instance key (computed).",
    },
    init = _ip_inst_init,
)

FpgaDesignInfo = provider(
    doc = "Generated block design.",
    fields = {
        "design_name": "String.",
        "top_entity": "String: top module or wrapper entity.",
        "design_script": "File: master BD script (consumers read THIS, not DefaultInfo).",
        "generated_files": "depset[File]: all scripts/artifacts needed to run design_script.",
        "ooc_ips": "list[struct(synth_key, ooc_synth_name, entity_name, generics, dcp, instances)]",
        "non_ooc_ips": "list[struct(synth_key, entity_name, generics, instances)]",
        "sources": "FpgaSourceInfo: aggregated sources of the design (includes generated wrappers).",
    },
)

# ---------------------------------------------------------------------------
# Flow results
# ---------------------------------------------------------------------------

FpgaProjectInfo = provider(
    doc = "An initialized FPGA project.",
    fields = {
        "project_script": "File: project creation script (Tcl).",
        "project_name": "String.",
        "tool_name": "String: tool that created it.",
        "sources": "FpgaSourceInfo.",
        "files": "depset[File]: everything needed to `source` project_script.",
    },
)

FpgaSynthesisInfo = provider(
    doc = "Synthesized netlist/checkpoint.",
    fields = {
        "netlist": "File: synthesized netlist/checkpoint.",
        "netlist_type": "String: dcp, edif, verilog.",
        "top_entity": "String.",
        "part": "String.",
        "constraints": "depset[File]: constraints used.",
        "reports": "depset[File]: timing/utilization/etc.",
        "log": "File: tool log.",
    },
)

FpgaImplementationInfo = provider(
    doc = "Placed and routed design.",
    fields = {
        "design_checkpoint": "File: routed checkpoint.",
        "top_entity": "String.",
        "part": "String.",
        "reports": "depset[File].",
        "log": "File.",
    },
)

FpgaBitstreamInfo = provider(
    doc = "Final bitstream and hardware platform.",
    fields = {
        "bitstream": "File: .bit/.bin.",
        "debug_probes": "File: .ltx.",
        "platform": "File: .xsa/.hdf.",
        "log": "File.",
    },
)

# FpgaSourceInfo = provider(
#     doc = "Collects FPGA source files including HDL and constraints.",
#     fields = {
#         "vhdl_libs": "depset[VhdlLibraryUnitInfo] of VHDL library units in topological postorder",
#         "verilog_srcs": "Depset of Verilog source files",
#         "constraints": "Depset of constraint files (e.g. XDC)",
#     },
# )

# FpgaProjectInfo = provider(
#     doc = "Represents an initialized FPGA project.",
#     fields = {
#         "project_script": "The project creation script (TCL)",
#         "project_name": "Name of the project",
#         "tool_name": "Name of the tool that created it",
#         "sources": "FpgaSourceInfo: The source files associated with this project",
#         "files": "Depset of all project files and scripts",
#     },
# )

# FpgaSynthesisInfo = provider(
#     doc = "Represents synthesized netlist or checkpoint.",
#     fields = {
#         "netlist": "The synthesized netlist file",
#         "netlist_type": "String (e.g., dcp, edif, verilog)",
#         "top_entity": "The top-level entity name",
#         "constraints": "Depset of constraint files to be used in implementation",
#     },
# )

# FpgaImplementationInfo = provider(
#     doc = "Represents placed and routed design.",
#     fields = {
#         "design_checkpoint": "The routed design (e.g., .dcp)",
#         "bitstream_ready": "Boolean or file indicator",
#     },
# )

# FpgaBitstreamInfo = provider(
#     doc = "Represents final bitstream files and hardware platform.",
#     fields = {
#         "bitstream": "The final bitstream file (.bit, .bin)",
#         "debug_probes": "Probes file (.ltx)",
#         "platform": "Hardware export file for software toolchains (.hdf, .xsa)",
#     },
# )

# FpgaClockDomainInfo = provider(
#     doc = "Provider for clock domain metadata.",
#     fields = {
#         "clock_pin": "String: Clock pin object.",
#         "clock_frequency": "String: Clock frequency.",
#         "reset_pin": "String: Reset pin object.",
#         "reset_type": "String: active_low or active_high.",
#     },
# )

# FpgaIpInfo = provider(
#     doc = "Configuration metadata for an Out-of-Context FPGA IP module.",
#     fields = {
#         "entity_name": "The name of the IP's top-level entity/module.",
#         "instance_name": "The unique instance name used inside the top-level design.",
#         "generics": "Dictionary of generic parameter configurations.",
#         "sources": "FpgaSourceInfo: RTL and constraint files for the IP.",
#         "memory_mapping": "Optional memory mapping details (e.g., register specifications).",
#         "ooc": "Boolean flag determining if out-of-context synthesis is needed.",
#         "inst_tcl": "File: Optional TCL script template for BD instantiation.",
#         "clock_domain": "FpgaClockDomainInfo: Optional reference clock domain info.",
#     },
# )

# FpgaDesignInfo = provider(
#     doc = "Structured FPGA system/block design metadata and generated scripts.",
#     fields = {
#         "design_name": "String: Name of the design.",
#         "top_entity": "String: Top module or wrapper entity.",
#         "design_script": "File: The master design generation script (e.g., _bd.tcl).",
#         "generated_files": "Depset of all generated support scripts and artifacts.",
#         "ooc_groups": "Dict of Out-of-Context deduplicated IP groups.",
#         "non_ooc_groups": "Dict of In-Context deduplicated IP groups.",
#         "sources": "FpgaSourceInfo: Aggregated sources and libraries.",
#     },
# )

VerilogInfo = provider(
    doc = "Collects Verilog and SystemVerilog sources.",
    fields = {
        "sources": "Depset of Verilog/SystemVerilog source files",
    },
)

ConstraintInfo = provider(
    doc = "Collects FPGA constraint files (e.g. XDC, SDC).",
    fields = {
        "sources": "Depset of constraint files (e.g. XDC, SDC)",
    },
)

