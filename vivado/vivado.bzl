load("//fpga:providers.bzl", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")
load("//fpga:source.bzl", "source_files","write_read_sources_tcl")
load("//fpga:utility.bzl", "get_resource_set")
load("@gateweavers_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo")

def _write_gui_runner(ctx, toolchain_info, tcl_script):
    runner = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    script_content = "#!/bin/bash\n"
    if toolchain_info.setup_cmd:
        script_content += toolchain_info.setup_cmd + "\n"
    script_content += "{cmd} -mode gui -source {tcl}\n".format(
        cmd = toolchain_info.cmd,
        tcl = tcl_script.short_path,
    )

    ctx.actions.write(
        output = runner,
        content = script_content,
        is_executable = True,
    )
    return runner

def _shell_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _vivado_batch_command(toolchain_info, tcl_script, log_file):
    run = "%s -mode batch -source %s -log %s -nojournal" % (
        toolchain_info.cmd,
        _shell_quote(tcl_script.path),
        _shell_quote(log_file.path),
    )

    # setup_cmd may be empty: never emit a dangling "&&".
    if toolchain_info.setup_cmd:
        return "%s && %s" % (toolchain_info.setup_cmd, run)
    return run

def vivado_create_project(ctx, toolchain_info, source_info, design_info = None):
    """Creates the project script. Sources are written lazily, nothing is flattened.

    Args:
      source_info: FpgaSourceInfo (own sources + deps + design sources).
      design_info: FpgaDesignInfo or None. Its design_script is sourced after
        the sources, and its generated files become inputs.
    """
    part = ctx.attr.part
    top = ctx.attr.top

    tcl_script = ctx.actions.declare_file(ctx.label.name + "_create_project.tcl")

    # One Tcl file with all read_vhdl / add_files commands, expanded at
    # execution time from the depsets (see sources.bzl).
    sources_tcl = ctx.actions.declare_file(ctx.label.name + "_read_sources.tcl")
    write_read_sources_tcl(ctx, source_info, sources_tcl, in_memory = False)

    source_bd_line = ""
    design_files = depset()
    if design_info:
        source_bd_line = "source %s" % design_info.design_script.path
        design_files = design_info.generated_files

    ctx.actions.expand_template(
        template = toolchain_info.templates.create_project,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OUTPUT_DIR}": ".",
            "{PART_NAME}": part,
            "{READ_SOURCES}": "source %s" % sources_tcl.path,
            "{SOURCE_BD_SCRIPT}": source_bd_line,
            "{TOP_MODULE}": top if top else "top",
        },
    )

    project_files = depset(
        [tcl_script, sources_tcl],
        transitive = [source_files(source_info), design_files],
    )
    return [
        FpgaProjectInfo(
            project_script = tcl_script,
            project_name = ctx.label.name,
            tool_name = "vivado",
            sources = source_info,
            files = project_files,
        ),
        DefaultInfo(files = project_files),
    ]

def vivado_synthesis(ctx, toolchain_info, source_info):
    """Synthesizes from a project, or from in-memory sources.

    source_info is already resolved by fpga_synthesis: the project's sources
    when `project` is set, otherwise the rule's own.
    """
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    top = ctx.attr.top
    part = ctx.attr.part
    generics = ctx.attr.generics
    defines = ctx.attr.defines
    synth_options = ctx.attr.synth_options
    pre_synth_tcl = ctx.file.pre_synth_tcl
    post_synth_tcl = ctx.file.post_synth_tcl
    max_threads = ctx.attr.max_threads
    memory = ctx.attr.memory

    netlist = ctx.actions.declare_file(ctx.label.name + ".dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_synth.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_synth.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_synth_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_synth_utilization.rpt")

    read_sources_if_memory = ""
    direct_inputs = [tcl_script]
    transitive_inputs = []

    if project_info:
        open_project_or_in_memory = "source %s" % project_info.project_script.path
        transitive_inputs.append(project_info.files)
    else:
        open_project_or_in_memory = "create_project -in_memory -part %s" % part

        # In-memory flow: read_* commands live in a generated Tcl file,
        # written lazily from the depsets.
        sources_tcl = ctx.actions.declare_file(ctx.label.name + "_read_sources.tcl")
        write_read_sources_tcl(ctx, source_info, sources_tcl, in_memory = True)
        read_sources_if_memory = "source %s" % sources_tcl.path
        direct_inputs.append(sources_tcl)
        transitive_inputs.append(source_files(source_info))

    if pre_synth_tcl:
        direct_inputs.append(pre_synth_tcl)
    if post_synth_tcl:
        direct_inputs.append(post_synth_tcl)

    synth_args_list = []
    if generics:
        gen_strs = []
        for k, v in generics.items():
            gen_strs.append("{}={}".format(k, v))
        synth_args_list.append("-generic {{{}}}".format(" ".join(gen_strs)))

    if defines:
        def_strs = []
        for k, v in defines.items():
            if v:
                def_strs.append("{}={}".format(k, v))
            else:
                def_strs.append(k)
        synth_args_list.append("-verilog_define {{{}}}".format(" ".join(def_strs)))

    if synth_options:
        synth_args_list.extend(synth_options)

    synth_args = " ".join(synth_args_list)

    pre_synth_line = "source %s" % pre_synth_tcl.path if pre_synth_tcl else ""
    post_synth_line = "source %s" % post_synth_tcl.path if post_synth_tcl else ""

    ctx.actions.expand_template(
        template = toolchain_info.templates.synthesis,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{PART_NAME}": part,
            "{TOP_MODULE}": top,
            "{OPEN_PROJECT_OR_IN_MEMORY}": open_project_or_in_memory,
            "{READ_SOURCES_IF_MEMORY}": read_sources_if_memory,
            "{SYNTH_ARGS}": synth_args,
            "{MAX_THREADS}": str(max_threads),
            "{PRE_SYNTH_TCL}": pre_synth_line,
            "{POST_SYNTH_TCL}": post_synth_line,
            "{REPORT_TIMING}": report_timing.path,
            "{REPORT_UTILIZATION}": report_utilization.path,
            "{OUTPUT_CHECKPOINT}": netlist.path,
        },
    )

    ctx.actions.run_shell(
        outputs = [netlist, log_file, report_timing, report_utilization],
        inputs = depset(direct_inputs, transitive = transitive_inputs),
        command = _vivado_batch_command(toolchain_info, tcl_script, log_file),
        mnemonic = "VivadoSynth",
        progress_message = "Synthesizing %s with Vivado" % top,
        env = {"HOME": "/tmp"},
        resource_set = get_resource_set(max_threads, memory),
    )

    reports = depset([report_timing, report_utilization])
    return [
        FpgaSynthesisInfo(
            netlist = netlist,
            netlist_type = "dcp",
            top_entity = top,
            part = part,
            constraints = source_info.constraints,
            reports = reports,
            log = log_file,
        ),
        DefaultInfo(files = depset([netlist])),
        OutputGroupInfo(reports = reports, logs = depset([log_file])),
    ]

def vivado_implementation(ctx, toolchain_info):
    synthesis_info = ctx.attr.synthesis[FpgaSynthesisInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if getattr(ctx.attr, "project", None) else None
    part = ctx.attr.part
    impl_options = getattr(ctx.attr, "impl_options", {})
    pre_impl_tcl = getattr(ctx.file, "pre_impl_tcl", None)
    post_impl_tcl = getattr(ctx.file, "post_impl_tcl", None)
    max_threads = getattr(ctx.attr, "max_threads", 4)
    memory = getattr(ctx.attr, "memory", 4000)

    checkpoint = ctx.actions.declare_file(ctx.label.name + "_routed.dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_impl.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_impl.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_impl_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_impl_utilization.rpt")
    report_route_status = ctx.actions.declare_file(ctx.label.name + "_route_status.rpt")

    direct_inputs = [synthesis_info.netlist, tcl_script]
    transitive_inputs = []
    if synthesis_info.constraints:
        transitive_inputs.append(synthesis_info.constraints)

    open_project_or_open_checkpoint = "open_checkpoint %s" % synthesis_info.netlist.path

    if pre_impl_tcl:
        direct_inputs.append(pre_impl_tcl)
    if post_impl_tcl:
        direct_inputs.append(post_impl_tcl)

    pre_impl_line = "source %s" % pre_impl_tcl.path if pre_impl_tcl else ""
    post_impl_line = "source %s" % post_impl_tcl.path if post_impl_tcl else ""

    opt_options = " ".join(impl_options.get("opt", []))
    place_options = " ".join(impl_options.get("place", []))
    phys_opt_options = " ".join(impl_options.get("phys_opt", []))
    route_options = " ".join(impl_options.get("route", []))

    ctx.actions.expand_template(
        template = toolchain_info.templates.implementation,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OPEN_PROJECT_OR_OPEN_CHECKPOINT}": open_project_or_open_checkpoint,
            "{MAX_THREADS}": str(max_threads),
            "{PRE_IMPL_TCL}": pre_impl_line,
            "{OPT_OPTIONS}": opt_options,
            "{PLACE_OPTIONS}": place_options,
            "{PHYS_OPT_OPTIONS}": phys_opt_options,
            "{ROUTE_OPTIONS}": route_options,
            "{POST_IMPL_TCL}": post_impl_line,
            "{REPORT_TIMING}": report_timing.path,
            "{REPORT_UTILIZATION}": report_utilization.path,
            "{REPORT_ROUTE_STATUS}": report_route_status.path,
            "{OUTPUT_CHECKPOINT}": checkpoint.path,
        },
    )

    command = "%s && %s -mode batch -source %s -log %s -nojournal" % (
        toolchain_info.setup_cmd,
        toolchain_info.cmd,
        tcl_script.path,
        log_file.path,
    )

    ctx.actions.run_shell(
        outputs = [checkpoint, log_file, report_timing, report_utilization, report_route_status],
        inputs = depset(direct_inputs, transitive = transitive_inputs),
        command = command,
        mnemonic = "VivadoImpl",
        progress_message = "Implementing %s with Vivado" % synthesis_info.top_entity,
        env = {"HOME": "/tmp"},
        resource_set = get_resource_set(max_threads, memory),
    )

    return [
        FpgaImplementationInfo(
            design_checkpoint = checkpoint,
            top_entity = synthesis_info.top_entity,
            part = synthesis_info.part,
            reports = depset([report_timing, report_utilization, report_route_status]),
            log = log_file,
        ),
        DefaultInfo(files = depset([checkpoint])),
    ]

def vivado_bitstream(ctx, toolchain_info):
    implementation_info = ctx.attr.implementation[FpgaImplementationInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if getattr(ctx.attr, "project", None) else None
    part = ctx.attr.part
    bit_options = getattr(ctx.attr, "bit_options", [])
    pre_bit_tcl = getattr(ctx.file, "pre_bit_tcl", None)
    post_bit_tcl = getattr(ctx.file, "post_bit_tcl", None)
    max_threads = getattr(ctx.attr, "max_threads", 1)
    memory = getattr(ctx.attr, "memory", 1000)

    bitstream = ctx.actions.declare_file(ctx.label.name + ".bit")
    probes = ctx.actions.declare_file(ctx.label.name + ".ltx")
    platform = ctx.actions.declare_file(ctx.label.name + ".xsa")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_bit.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_bit.log")

    inputs = [implementation_info.design_checkpoint, tcl_script]
    open_project_or_open_checkpoint = "open_checkpoint %s" % implementation_info.design_checkpoint.path

    if pre_bit_tcl:
        inputs.append(pre_bit_tcl)
    if post_bit_tcl:
        inputs.append(post_bit_tcl)

    pre_bit_line = "source %s" % pre_bit_tcl.path if pre_bit_tcl else ""
    post_bit_line = "source %s" % post_bit_tcl.path if post_bit_tcl else ""
    bit_args = " ".join(bit_options) if bit_options else ""

    ctx.actions.expand_template(
        template = toolchain_info.templates.bitstream,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OPEN_PROJECT_OR_OPEN_CHECKPOINT}": open_project_or_open_checkpoint,
            "{PRE_BIT_TCL}": pre_bit_line,
            "{BIT_OPTIONS}": bit_args,
            "{POST_BIT_TCL}": post_bit_line,
            "{BITSTREAM}": bitstream.path,
            "{PROBES}": probes.path,
            "{PLATFORM}": platform.path,
        },
    )

    command = "%s && %s -mode batch -source %s -log %s -nojournal" % (
        toolchain_info.setup_cmd,
        toolchain_info.cmd,
        tcl_script.path,
        log_file.path,
    )

    ctx.actions.run_shell(
        outputs = [bitstream, probes, platform, log_file],
        inputs = inputs,
        command = command,
        mnemonic = "VivadoBitstream",
        progress_message = "Generating bitstream with Vivado",
        env = {"HOME": "/tmp"},
        resource_set = get_resource_set(max_threads, memory),
    )

    return [
        FpgaBitstreamInfo(
            bitstream = bitstream,
            debug_probes = probes,
            platform = platform,
        ),
        DefaultInfo(files = depset([bitstream, probes, platform])),
    ]

def _manifest_line(f):
    # "<execroot path>\t<runfiles short_path>", one line per file.
    return "%s\t%s" % (f.path, f.short_path)

def _write_project_gui_runner(ctx, toolchain_info, project_info, manifest):
    """Runner that rebuilds an execroot-like tree from the runfiles.

    The project script, the sources script and the design scripts reference
    each other with execroot-relative `.path`s. Generated files do not live
    under those paths inside the runfiles tree (bazel-out/... vs <ws>/pkg/...),
    so instead of generating a second set of scripts with short_paths, the
    runner symlinks every file of the project to its `.path` in a work
    directory and runs the very same project script from there.

    Work directory:
      $FPGA_GUI_WORKDIR                                   if set (never cleaned)
      $BUILD_WORKSPACE_DIRECTORY/.fpga_gui/<package>/<name>  under `bazel run`
                                                          (recreated on each run)
      a mktemp -d directory                               otherwise
    """
    runner = ctx.actions.declare_file(ctx.label.name + "_runner.sh")

    setup = ""
    if toolchain_info.setup_cmd:
        # Vendor settings scripts are not nounset/errexit clean (they read
        # unset variables such as PYTHONPATH): relax the shell around them.
        setup = "set +eu\n%s\nset -eu\n" % toolchain_info.setup_cmd

    content = """#!/bin/bash
set -euo pipefail
RF="${RUNFILES_DIR:-$0.runfiles}"
MF="${RUNFILES_MANIFEST_FILE:-$RF/MANIFEST}"
WS="%s"

# Resolves a short_path to a real file: runfiles tree first, manifest second
# (manifest-only runfiles, e.g. --noenable_runfiles).
rf() {
  local k
  case "$1" in
    ../*) k="${1#../}" ;;
    *) k="$WS/$1" ;;
  esac
  if [ -e "$RF/$k" ]; then
    echo "$RF/$k"
  elif [ -f "$MF" ]; then
    awk -v k="$k" '$1 == k { sub(/^[^ ]+ /, ""); print; exit }' "$MF"
  else
    echo "cannot resolve runfile: $k" >&2
    return 1
  fi
}

if [ -n "${FPGA_GUI_WORKDIR:-}" ]; then
  WORK="$FPGA_GUI_WORKDIR"
elif [ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]; then
  WORK="$BUILD_WORKSPACE_DIRECTORY/.fpga_gui/%s/%s"
  rm -rf "$WORK"
else
  WORK="$(mktemp -d)"
fi
mkdir -p "$WORK"
echo "Vivado work directory: $WORK" >&2

while IFS=$'\\t' read -r p s; do
  src="$(rf "$s")"
  mkdir -p "$WORK/$(dirname "$p")"
  ln -sfn "$src" "$WORK/$p"
done < "$(rf "%s")"

cd "$WORK"
%s%s -mode gui -source %s
""" % (
        ctx.workspace_name,
        ctx.label.package,
        ctx.label.name,
        manifest.short_path,
        setup,
        toolchain_info.cmd,
        project_info.project_script.path,
    )
    ctx.actions.write(output = runner, content = content, is_executable = True)
    return runner

def vivado_project_gui(ctx, toolchain_info):
    project_info = ctx.attr.project[FpgaProjectInfo]

    # Lazily expanded: no flattening of project_info.files at analysis time.
    manifest = ctx.actions.declare_file(ctx.label.name + "_files.manifest")
    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add_all(project_info.files, map_each = _manifest_line)
    ctx.actions.write(output = manifest, content = args)

    runner = _write_project_gui_runner(ctx, toolchain_info, project_info, manifest)

    return [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(
                transitive_files = depset([manifest], transitive = [project_info.files]),
            ),
        ),
    ]

def vivado_dcp_gui(ctx, toolchain_info):
    dcp = ctx.file.dcp
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_gui.tcl")

    # Generate a TCL script to open the checkpoint
    tcl_content = "open_checkpoint {}\n".format(dcp.short_path)
    ctx.actions.write(
        output = tcl_script,
        content = tcl_content,
    )

    # Generate bash script
    runner = _write_gui_runner(ctx, toolchain_info, tcl_script)

    return [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(files = [dcp, tcl_script]),
        )
    ]

# ---------------------------------------------------------------------------
# Design generation. Consumes the structs built by fpga_design:
#
#   group:    struct(synth_key, entity_name, ip, sources, generics, ooc,
#                    ooc_synth_name, instances)
#   instance: struct(instance_name, inst_key, wrapper_name, generics,
#                    clock_domain, memory_mapping, inst_tcl, clock_port,
#                    reset_port, reset_type, interfaces)
#
# Inline instance (ooc = False): the BD references the entity directly through
#   the IP's vivado_inst_<entity> procedure, with generics.
# OOC instance (ooc = True): the BD references a generated wrapper module
#   (instance.wrapper_name) that instantiates the renamed OOC netlist
#   (group.ooc_synth_name). Both kinds are BD cells.
# ---------------------------------------------------------------------------

_OOC_MAX_THREADS = 4
_OOC_MEMORY_MB = 4000

def _tcl_list(items):
    if not items:
        return "[list]"
    return "[list %s]" % " ".join(['"%s"' % i for i in items])

def _tcl_pairs(d):
    flat = []
    for k in sorted(d.keys()):
        flat.extend([k, d[k]])
    return _tcl_list(flat)

def _distinct_inst_tcls(instances):
    seen = {}
    files = []
    for inst in instances:
        f = inst.inst_tcl
        if f and f.path not in seen:
            seen[f.path] = True
            files.append(f)
    return files

def _all_instances(groups):
    return [inst for group in groups for inst in group.instances]

def _generate_ooc_synthesis_actions(ctx, toolchain_info, ooc_groups, part):
    """One out-of-context synthesis per OOC group.

    Returns (dcps: dict[synth_key, File], tcls: list[File]).
    The checkpoint's top is renamed to group.ooc_synth_name, so it can never
    clash with the original entity defined by an inline instance elsewhere.
    """
    dcps = {}
    tcls = []
    for key, group in ooc_groups.items():
        name = group.ooc_synth_name
        prefix = "%s_ooc/%s" % (ctx.label.name, name)
        dcp = ctx.actions.declare_file(prefix + ".dcp")
        tcl = ctx.actions.declare_file(prefix + "_synth.tcl")
        sources_tcl = ctx.actions.declare_file(prefix + "_read_sources.tcl")
        log = ctx.actions.declare_file(prefix + "_synth.log")

        write_read_sources_tcl(ctx, group.sources, sources_tcl, in_memory = True)

        generics_arg = ""
        if group.generics:
            generics_arg = " -generic {%s}" % " ".join(
                ["%s=%s" % (k, group.generics[k]) for k in sorted(group.generics.keys())],
            )

        content = "\n".join([
            "# Out-of-context synthesis of %s (instances: %s)" % (
                group.entity_name,
                ", ".join([i.instance_name for i in group.instances]),
            ),
            "set_param general.maxThreads %d" % _OOC_MAX_THREADS,
            "create_project -in_memory -part %s" % part,
            "source %s" % sources_tcl.path,
            # Flatten: a single module in the netlist, so renaming the top is
            # enough to keep every module name unique.
            "synth_design -mode out_of_context -flatten_hierarchy full -top %s -part %s%s" % (
                group.entity_name,
                part,
                generics_arg,
            ),
            "# Unique top name = ooc_synth_name (referenced by the wrapper).",
            "rename_ref -ref %s -to %s" % (group.entity_name, name),
            "write_checkpoint -force %s" % dcp.path,
            "",
        ])
        ctx.actions.write(output = tcl, content = content)

        ctx.actions.run_shell(
            outputs = [dcp, log],
            inputs = depset([tcl, sources_tcl], transitive = [source_files(group.sources)]),
            command = _vivado_batch_command(toolchain_info, tcl, log),
            mnemonic = "VivadoOocSynth",
            progress_message = "OOC synthesis of %s (%s)" % (group.entity_name, name),
            env = {"HOME": "/tmp"},
            resource_set = get_resource_set(_OOC_MAX_THREADS, _OOC_MEMORY_MB),
        )

        dcps[key] = dcp
        tcls.append(tcl)
    return dcps, tcls

def _generate_bd_instantiation(ctx, ooc_groups, non_ooc_groups):
    bd_inst_tcl = ctx.actions.declare_file(ctx.label.name + "_bd_inst.tcl")
    inline = _all_instances(non_ooc_groups.values())
    wrapped = _all_instances(ooc_groups.values())

    lines = ["# Block Design Instantiation Script", ""]

    inst_tcls = _distinct_inst_tcls(inline)
    lines.append("# Source IP instantiation procedures:")
    for f in inst_tcls:
        lines.append("source %s" % f.path)

    lines.extend(["", "# Instantiate inline cells:"])
    for group in non_ooc_groups.values():
        for inst in group.instances:
            lines.append('vivado_inst_%s "%s" %s' % (
                group.entity_name,
                inst.instance_name,
                _tcl_pairs(inst.generics),
            ))

    if wrapped:
        lines.extend([
            "",
            "# OOC instances: module references to the generated wrappers",
            "update_compile_order -fileset sources_1",
        ])
        for inst in wrapped:
            lines.append("create_bd_cell -type module -reference %s %s" % (
                inst.wrapper_name,
                inst.instance_name,
            ))

    ctx.actions.write(output = bd_inst_tcl, content = "\n".join(lines) + "\n")
    return bd_inst_tcl, inst_tcls

def _generate_memory_mapping(ctx, ooc_groups, non_ooc_groups):
    mem_map_tcl = ctx.actions.declare_file(ctx.label.name + "_memory_mapping.tcl")

    mapped = []
    for group in non_ooc_groups.values() + ooc_groups.values():
        for inst in group.instances:
            if not inst.memory_mapping:
                continue
            if not inst.inst_tcl:
                fail(("%s: instance '%s' has a memory_mapping but its IP declares no " +
                      "inst_tcl providing vivado_memory_mapping_%s") % (
                    ctx.label,
                    inst.instance_name,
                    group.entity_name,
                ))
            mapped.append((group, inst))

    inst_tcls = _distinct_inst_tcls([inst for _, inst in mapped])

    lines = ["# Memory Mapping Script", "", "# Source IP procedures:"]
    for f in inst_tcls:
        lines.append("source %s" % f.path)
    lines.extend(["", "# Memory mapping configurations:"])
    for group, inst in mapped:
        lines.append('vivado_memory_mapping_%s "%s" %s' % (
            group.entity_name,
            inst.instance_name,
            _tcl_pairs(inst.memory_mapping),
        ))

    ctx.actions.write(output = mem_map_tcl, content = "\n".join(lines) + "\n")
    return mem_map_tcl, inst_tcls

def _format_bd_pin(pin):
    if not pin:
        return '""'
    if pin.startswith("[") or pin.startswith('"'):
        return pin
    if pin.startswith("get_bd_pins"):
        return "[%s]" % pin
    return "[get_bd_pins -quiet %s]" % pin

_CONNECT_AXI_LITE_TPL = """# --- Clock Domain Group {idx} ---
connect_axi_lite \\
    [list {ip_list}] \\
    {clk_pin} \\
    {rst_pin} \\
    "{clk_port}" \\
    "{rst_port}" \\
    "axi_lite_interconnect_{idx}" \\
    "proc_sys_reset_{idx}" \\
    {slave_list} \\
    {active_low_val}
"""

_CONNECT_MASTERS_TPL = """
set sc_master_pins [connect_axi_masters_to_smartconnect \\
    [list {ip_list}] \\
    {clk_pin} \\
    {rst_pin} \\
    "{master_pattern}" \\
    "smartconnect_dma_{idx}" \\
    1]
"""

def _generate_clock_domain_connections(ctx, ooc_groups, non_ooc_groups, clock_domain_tpl):
    clk_dom_tcl = ctx.actions.declare_file(ctx.label.name + "_clock_domain.tcl")

    # Instances are connected together only if they share the clock domain AND
    # the port names / interfaces the connection procedures are called with.
    clk_rst_groups = {}
    for inst in _all_instances(non_ooc_groups.values() + ooc_groups.values()):
        clk_info = inst.clock_domain
        if not clk_info:
            continue
        slaves = tuple(sorted([n for n, role in inst.interfaces.items() if role == "slave"]))
        masters = sorted([n for n, role in inst.interfaces.items() if role == "master"])
        if len(masters) > 1:
            fail(("%s: instance '%s' declares several master interfaces %s; " +
                  "declare a single master as a glob pattern (e.g. \"M_AXI*\")") % (
                ctx.label,
                inst.instance_name,
                masters,
            ))
        key = (
            clk_info.clock_pin,
            clk_info.reset_pin,
            clk_info.reset_type,
            inst.clock_port,
            inst.reset_port,
            slaves,
            masters[0] if masters else "",
        )
        clk_rst_groups.setdefault(key, []).append(inst.instance_name)

    group_blocks = []
    for idx, key in enumerate(sorted(clk_rst_groups.keys())):
        clk_pin, rst_pin, rst_type, clk_port, rst_port, slaves, master_pattern = key
        common = dict(
            idx = idx,
            ip_list = " ".join(['"%s"' % n for n in sorted(clk_rst_groups[key])]),
            clk_pin = _format_bd_pin(clk_pin),
            rst_pin = _format_bd_pin(rst_pin),
        )
        block = ""
        if slaves:
            block += _CONNECT_AXI_LITE_TPL.format(
                clk_port = clk_port,
                rst_port = rst_port,
                slave_list = _tcl_list(list(slaves)),
                active_low_val = 1 if rst_type == "active_low" else 0,
                **common
            )
        if master_pattern:
            block += _CONNECT_MASTERS_TPL.format(master_pattern = master_pattern, **common)
        if block:
            group_blocks.append(block)

    clk_tcl_content = """# Clock Domain Connection Script

source {tpl_path}

{blocks}
""".format(
        tpl_path = clock_domain_tpl.path,
        blocks = "\n".join(group_blocks),
    )

    ctx.actions.write(output = clk_dom_tcl, content = clk_tcl_content)
    return clk_dom_tcl

def _generate_bd_script(ctx, bd_inst_tcl, mem_map_tcl, clk_dom_tcl, ooc_dcps, pre_bd_hook = None, post_bd_hook = None):
    bd_tcl = ctx.actions.declare_file(ctx.label.name + "_bd.tcl")

    bd_content = "# Block Design Creation Script for Vivado IPI\n"

    if ooc_dcps:
        bd_content += "# OOC netlists referenced by the generated wrappers:\n"
        for dcp in ooc_dcps:
            bd_content += "add_files -norecurse {}\n".format(dcp.path)
        bd_content += "\n"

    bd_content += "create_bd_design \"{}\"\n".format(ctx.label.name)

    if pre_bd_hook:
        bd_content += "\n# Block Design Hook (e.g. PS configuration):\nsource {}\n\n".format(pre_bd_hook.path)

    bd_content += "# Source generated scripts:\n"
    bd_content += "source {}\n".format(bd_inst_tcl.path)
    bd_content += "source {}\n".format(clk_dom_tcl.path)

    if post_bd_hook:
        bd_content += "# Post-Block Design Hook :\n"
        bd_content += "source {}\n\n".format(post_bd_hook.path)

    bd_content += "source {}\n\n".format(mem_map_tcl.path)

    bd_content += "save_bd_design\n"
    bd_content += "set bd_file [get_files [current_bd_design].bd]\n"
    bd_content += "set_property synth_checkpoint_mode None $bd_file\n"
    bd_content += "generate_target all $bd_file\n"
    bd_content += "set wrapper_file [make_wrapper -files $bd_file -top]\n"
    bd_content += "add_files -norecurse $wrapper_file\n"
    bd_content += "update_compile_order -fileset sources_1\n"

    ctx.actions.write(output = bd_tcl, content = bd_content)
    return bd_tcl

def vivado_generate_design(ctx, toolchain_info, design_data):
    ooc_groups = design_data.ooc_groups
    non_ooc_groups = design_data.non_ooc_groups
    pre_bd_hook = design_data.pre_bd_hook
    post_bd_hook = design_data.post_bd_hook
    clock_domain_tpl = toolchain_info.templates.clock_domain

    # 1 OOC synthesis: dict[synth_key, dcp]
    ooc_dcps, ooc_tcls = _generate_ooc_synthesis_actions(ctx, toolchain_info, ooc_groups, design_data.part)

    # 2 BD instantiation (inline cells + OOC wrapper cells)
    bd_inst_tcl, inst_inputs = _generate_bd_instantiation(ctx, ooc_groups, non_ooc_groups)

    # 3 memory mapping
    mem_map_tcl, mem_inputs = _generate_memory_mapping(ctx, ooc_groups, non_ooc_groups)

    # 4 clock domain connection
    clk_dom_tcl = _generate_clock_domain_connections(ctx, ooc_groups, non_ooc_groups, clock_domain_tpl)

    # 5 top bd script
    bd_tcl = _generate_bd_script(
        ctx,
        bd_inst_tcl,
        mem_map_tcl,
        clk_dom_tcl,
        ooc_dcps.values(),
        pre_bd_hook,
        post_bd_hook,
    )

    bd_inputs = inst_inputs + mem_inputs
    generated_files = [
        bd_inst_tcl,
        mem_map_tcl,
        clk_dom_tcl,
        bd_tcl,
        clock_domain_tpl,
    ] + ooc_dcps.values() + bd_inputs

    if pre_bd_hook:
        generated_files.append(pre_bd_hook)
    if post_bd_hook:
        generated_files.append(post_bd_hook)

    return struct(
        design_script = bd_tcl,
        generated_files = depset(generated_files),
        ooc_dcps = ooc_dcps,  # dict[synth_key, File]
        ooc_tcls = ooc_tcls,
        bd_inst_tcl = bd_inst_tcl,
        mem_map_tcl = mem_map_tcl,
        clk_dom_tcl = clk_dom_tcl,
        bd_inputs = bd_inputs,
    )