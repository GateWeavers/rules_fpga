load(
    "//fpga:providers.bzl",
    "ConstraintInfo",
    "FpgaSourceInfo",
    "VerilogInfo",
)
load("@gateweavers_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "VhdlLibraryUnitInfo")


"""Source collection for the FPGA rules.

One aggregation function (collect_sources), one canonical provider
(FpgaSourceInfo), and adapters only at the upstream boundary.
"""


_VHDL = ["vhd", "vhdl"]
_VERILOG = ["v", "sv"]
_VERILOG_HEADERS = ["vh", "svh"]
_CONSTRAINTS = ["xdc", "sdc"]

VHDL_VERSIONS = ["93", "2008", "2019"]

def _vhdl_flag(version):
    """read_vhdl flag for a version string; fails on what Vivado cannot read.

    Vivado reads VHDL-93 (default, no flag), -vhdl2008 and -vhdl2019.
    """
    v = str(version).lower().strip()
    if v.startswith("vhdl"):
        v = v[4:]
    if v in ["93", "1993"]:
        return ""
    if v in ["08", "2008"]:
        return "-vhdl2008"
    if v in ["19", "2019"]:
        return "-vhdl2019"
    fail("unsupported VHDL version '%s' (Vivado reads 93, 2008 and 2019)" % version)


def classify_files(files):
    """Splits files by extension. Unknown extensions are kept as `data`."""
    vhdl, verilog, headers, constraints, data = [], [], [], [], []
    for f in files:
        ext = f.extension.lower()
        if ext in _VHDL:
            vhdl.append(f)
        elif ext in _VERILOG:
            verilog.append(f)
        elif ext in _VERILOG_HEADERS:
            headers.append(f)
        elif ext in _CONSTRAINTS:
            constraints.append(f)
        else:
            data.append(f)
    return struct(
        vhdl = vhdl,
        verilog = verilog,
        headers = headers,
        constraints = constraints,
        data = data,
    )

def merge_source_infos(infos):
    """Merges FpgaSourceInfo values."""
    if len(infos) == 1:
        return infos[0]
    return FpgaSourceInfo(
        vhdl_libs = depset(transitive = [i.vhdl_libs for i in infos], order = "postorder"),
        vhdl_files = depset(transitive = [i.vhdl_files for i in infos]),
        verilog_srcs = depset(transitive = [i.verilog_srcs for i in infos]),
        verilog_headers = depset(transitive = [i.verilog_headers for i in infos]),
        constraints = depset(transitive = [i.constraints for i in infos]),
        data = depset(transitive = [i.data for i in infos]),
    )


def _from_vhdl_library_info(vinfo):
    # Interop edge: wrap vhdl_library nodes into an FpgaSourceInfo.
    libs = vinfo.all_libs
    return FpgaSourceInfo(
        vhdl_libs = libs,
        vhdl_files = depset(transitive = [u.sources for u in libs.to_list()]),
    )

def _from_verilog_info(vinfo, label):
    """rules_hdl VerilogInfo -> FpgaSourceInfo.

    VerilogInfo.dag is a depset of per-library structs that each carry `srcs`.

    """

    files = []
    for node in vinfo.dag.to_list():
        files.extend(node.srcs)

        # Only present in some rules_hdl versions: check your pinned providers.bzl.
        files.extend(getattr(node, "hdrs", []))
        files.extend(getattr(node, "data", []))
    cls = classify_files(files)
    if cls.vhdl:
        fail("%s: VerilogInfo contains VHDL files %s; wrap them in a vhdl_library" % (
            label,
            [f.short_path for f in cls.vhdl],
        ))
    return FpgaSourceInfo(
        verilog_srcs = depset(cls.verilog),
        verilog_headers = depset(cls.headers),
        constraints = depset(cls.constraints),
        data = depset(cls.data),
    )

def _source_info_from_dep(target):
    """Target -> FpgaSourceInfo. The only place that knows about upstream providers.

    A target may carry several upstream providers (a mixed-language library),
    so all present ones are merged.
    """

    if FpgaSourceInfo in target:
        return target[FpgaSourceInfo]
    parts = []
    if VhdlLibraryInfo in target:
        parts.append(_from_vhdl_library_info(target[VhdlLibraryInfo]))
    if VerilogInfo in target:
        parts.append(_from_verilog_info(target[VerilogInfo], target.label))
    if not parts:
        fail("%s provides none of FpgaSourceInfo, VhdlLibraryInfo, VerilogInfo" % target.label)
    return merge_source_infos(parts)

def collect_sources(
        ctx,
        *,
        srcs = [],
        constraints = [],
        deps = [],
        library_name = "work",
        vhdl_version = "2008"):
    """Aggregates direct files and deps into one FpgaSourceInfo.

    Ordering: dependencies first, this target's own unit last. A postorder
    depset emits `transitive` before `direct`, so the own unit goes in `direct`.
    """
    if vhdl_version not in VHDL_VERSIONS:
        fail("unsupported vhdl_version '%s', expected one of %s" % (vhdl_version, VHDL_VERSIONS))

    own = classify_files(srcs + constraints)
    dep_infos = [_source_info_from_dep(d) for d in deps]

    own_units = []
    if own.vhdl:
        own_units.append(VhdlLibraryUnitInfo(
            library_name = library_name,
            vhdl_version = vhdl_version,
            sources = depset(own.vhdl),
        ))

    return FpgaSourceInfo(
        vhdl_libs = depset(
            direct = own_units,
            transitive = [i.vhdl_libs for i in dep_infos],
            order = "postorder",
        ),
        vhdl_files = depset(own.vhdl, transitive = [i.vhdl_files for i in dep_infos]),
        verilog_srcs = depset(own.verilog, transitive = [i.verilog_srcs for i in dep_infos]),
        verilog_headers = depset(own.headers, transitive = [i.verilog_headers for i in dep_infos]),
        # Files from the `constraints` attr are constraints whatever their extension.
        constraints = depset(
            own.constraints + [f for f in constraints if f not in own.constraints],
            transitive = [i.constraints for i in dep_infos],
        ),
        data = depset(own.data, transitive = [i.data for i in dep_infos]),
    )

def source_files(src):
    """Every file of an FpgaSourceInfo as one depset: use for action inputs / DefaultInfo."""
    return depset(transitive = [
        src.vhdl_files,
        src.verilog_srcs,
        src.verilog_headers,
        src.constraints,
        src.data,
    ])

# ---------------------------------------------------------------------------
# Upstream boundary (use only where an upstream rules_vhdl consumer needs it)
# ---------------------------------------------------------------------------

def to_vhdl_library_info(src):
    """FpgaSourceInfo -> VhdlLibraryInfo with the work/non-work split preserved.

    Flattens vhdl_libs, so call it only on leaf rules that must interoperate
    with rules_vhdl, not on every node of the FPGA graph.
    """
    units = src.vhdl_libs.to_list()
    return VhdlLibraryInfo(
        all_libs = src.vhdl_libs,
        work_libs = depset([u for u in units if u.library_name == "work"], order = "postorder"),
        vhdl_libs = depset([u for u in units if u.library_name != "work"], order = "postorder"),
    )

# ---------------------------------------------------------------------------
# Leaf rule: the single owner of srcs/constraints
# ---------------------------------------------------------------------------

def _fpga_sources_impl(ctx):
    src = collect_sources(
        ctx,
        srcs = ctx.files.srcs,
        constraints = ctx.files.constraints,
        deps = ctx.attr.deps,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
    )
    return [
        DefaultInfo(files = source_files(src)),
        src,
    ]

fpga_sources = rule(
    implementation = _fpga_sources_impl,
    doc = "HDL + constraint sources. Project/synthesis/design rules take this via deps.",
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "constraints": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [[FpgaSourceInfo], [VhdlLibraryInfo]]),
        "library_name": attr.string(default = "work"),
        "vhdl_version": attr.string(default = "2008", values = VHDL_VERSIONS),
    },
)

# ---------------------------------------------------------------------------
# Lazy Tcl emission (replaces _format_sources + .to_list() in vivado.bzl)
# ---------------------------------------------------------------------------

def _vhdl_unit_cmds(unit):
    # Runs at execution time (Args expansion), not during analysis.
    flag = _vhdl_flag(unit.vhdl_version)
    flag_str = (" " + flag) if flag else ""
    return [
        "read_vhdl -library %s%s {%s}" % (unit.library_name, flag_str, f.path)
        for f in unit.sources.to_list()
    ]

def write_read_sources_tcl(ctx, src, output, in_memory):
    """Writes a Tcl file that reads all sources. Nothing is flattened at analysis time.

    The project/synthesis templates then just `source` this file instead of
    receiving {ADD_VHDL_SOURCES} / {ADD_VERILOG_SOURCES} / {ADD_CONSTRAINTS}
    substitutions. Add source_files(src) (and `output`) to the action inputs.
    """
    args = ctx.actions.args()
    args.set_param_file_format("multiline")  # one command per line; verify against your Bazel version
    args.add_all(src.vhdl_libs, map_each = _vhdl_unit_cmds)
    if in_memory:
        args.add_all(src.verilog_srcs, format_each = "read_verilog {%s}")
        args.add_all(src.constraints, format_each = "read_xdc {%s}")
    else:
        args.add_all(src.verilog_srcs, format_each = "add_files -norecurse {%s}")
        args.add_all(src.constraints, format_each = "add_files -fileset constrs_1 -norecurse {%s}")
    ctx.actions.write(output = output, content = args)
