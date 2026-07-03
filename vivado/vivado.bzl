load("//fpga:providers.bzl", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")

def vivado_create_project(ctx, toolchain_info, source_info, part, top):
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_create_project.tcl")

    vhdl_content = []
    for lib in source_info.vhdl_libs:
        files = [f.path for f in lib.sources.to_list()]
        vhdl_content.append("add_files -norecurse {%s}" % " ".join(files))
        vhdl_content.append("set_property library %s [get_files {%s}]" % (lib.library, " ".join(files)))
        vhdl_content.append("set_property file_type {VHDL 2008} [get_files {%s}]" % " ".join(files))

    verilog_files = [f.path for f in source_info.verilog_srcs.to_list()]
    verilog_content = ["add_files -norecurse {%s}" % " ".join(verilog_files)] if verilog_files else []

    constraint_files = [f.path for f in source_info.constraints.to_list()]
    constraint_content = ["add_files -fileset constrs_1 -norecurse {%s}" % " ".join(constraint_files)] if constraint_files else []

    ctx.actions.expand_template(
        template = toolchain_info.templates.create_project,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OUTPUT_DIR}": ".",
            "{PART_NAME}": part,
            "{ADD_VHDL_SOURCES}": "\n".join(vhdl_content),
            "{ADD_VERILOG_SOURCES}": "\n".join(verilog_content),
            "{ADD_CONSTRAINTS}": "\n".join(constraint_content),
            "{TOP_MODULE}": top if top else "top",
        },
    )

    return [
        FpgaProjectInfo(
            project_script = tcl_script,
            project_name = ctx.label.name,
            tool_name = "vivado",
            sources = source_info,
        ),
        DefaultInfo(files = depset([tcl_script])),
    ]

def vivado_synthesis(
    ctx,
    toolchain_info,
    project_info,
    source_info,
    top,
    part,
    generics = {},
    defines = {},
    max_threads = 4,
    synth_options = [],
    pre_synth_tcl = None,
    post_synth_tcl = None,
):
    netlist = ctx.actions.declare_file(ctx.label.name + ".dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_synth.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_synth.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_synth_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_synth_utilization.rpt")

    open_project_or_in_memory = ""
    read_sources_if_memory = ""
    inputs = []

    if project_info:
        open_project_or_in_memory = "source %s\nopen_project %s.xpr" % (project_info.project_script.path, project_info.project_name)
        inputs.append(project_info.project_script)
        if source_info:
            for lib in source_info.vhdl_libs:
                inputs.extend(lib.sources.to_list())
            inputs.extend(source_info.verilog_srcs.to_list())
            inputs.extend(source_info.constraints.to_list())
    else:
        open_project_or_in_memory = "create_project -in_memory -part %s" % part

        vhdl_content = []
        for lib in source_info.vhdl_libs:
            files = [f.path for f in lib.sources.to_list()]
            vhdl_content.append("read_vhdl -library %s -vhdl2008 {%s}" % (lib.library, " ".join(files)))
            inputs.extend(lib.sources.to_list())

        verilog_files = [f.path for f in source_info.verilog_srcs.to_list()]
        verilog_content = ["read_verilog {%s}" % " ".join(verilog_files)] if verilog_files else []
        inputs.extend(source_info.verilog_srcs.to_list())

        constraint_files = [f.path for f in source_info.constraints.to_list()]
        constraint_content = ["read_xdc {%s}" % " ".join(constraint_files)] if constraint_files else []
        inputs.extend(source_info.constraints.to_list())

        read_sources_if_memory = "\n".join(vhdl_content + verilog_content + constraint_content)

    if pre_synth_tcl:
        inputs.append(pre_synth_tcl)
    if post_synth_tcl:
        inputs.append(post_synth_tcl)

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

    ctx.actions.run(
        outputs = [netlist, log_file, report_timing, report_utilization],
        inputs = inputs + [tcl_script],
        executable = toolchain_info.cmd,
        arguments = ["-mode", "batch", "-source", tcl_script.path, "-log", log_file.path, "-nojournal"],
        mnemonic = "VivadoSynth",
        progress_message = "Synthesizing %s with Vivado" % top,
        env = {"HOME": "/tmp"},
    )

    return [
        FpgaSynthesisInfo(
            netlist = netlist,
            netlist_type = "dcp",
            top_entity = top,
            constraints = source_info.constraints if source_info else depset(),
        ),
        DefaultInfo(files = depset([netlist])),
    ]

def vivado_implementation(
    ctx,
    toolchain_info,
    synthesis_info,
    project_info,
    part,
    max_threads = 8,
    impl_options = {},
    pre_impl_tcl = None,
    post_impl_tcl = None,
):
    checkpoint = ctx.actions.declare_file(ctx.label.name + "_routed.dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_impl.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_impl.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_impl_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_impl_utilization.rpt")
    report_route_status = ctx.actions.declare_file(ctx.label.name + "_route_status.rpt")

    open_project_or_open_checkpoint = ""
    inputs = [synthesis_info.netlist]
    if synthesis_info.constraints:
        inputs.extend(synthesis_info.constraints.to_list())

    if project_info:
        open_project_or_open_checkpoint = "source %s\nopen_project %s.xpr\nopen_checkpoint %s" % (
            project_info.project_script.path,
            project_info.project_name,
            synthesis_info.netlist.path
        )
        inputs.append(project_info.project_script)
        if hasattr(project_info, "sources") and project_info.sources:
            for lib in project_info.sources.vhdl_libs:
                inputs.extend(lib.sources.to_list())
            inputs.extend(project_info.sources.verilog_srcs.to_list())
            inputs.extend(project_info.sources.constraints.to_list())
    else:
        open_project_or_open_checkpoint = "open_checkpoint %s" % synthesis_info.netlist.path

    if pre_impl_tcl:
        inputs.append(pre_impl_tcl)
    if post_impl_tcl:
        inputs.append(post_impl_tcl)

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

    ctx.actions.run(
        outputs = [checkpoint, log_file, report_timing, report_utilization, report_route_status],
        inputs = inputs + [tcl_script],
        executable = toolchain_info.cmd,
        arguments = ["-mode", "batch", "-source", tcl_script.path, "-log", log_file.path, "-nojournal"],
        mnemonic = "VivadoImpl",
        progress_message = "Implementing %s with Vivado" % synthesis_info.top_entity,
        env = {"HOME": "/tmp"},
    )

    return [
        FpgaImplementationInfo(
            design_checkpoint = checkpoint,
            bitstream_ready = True,
        ),
        DefaultInfo(files = depset([checkpoint])),
    ]

def vivado_bitstream(
    ctx,
    toolchain_info,
    implementation_info,
    project_info,
    part,
    bit_options = [],
    pre_bit_tcl = None,
    post_bit_tcl = None,
):
    bitstream = ctx.actions.declare_file(ctx.label.name + ".bit")
    probes = ctx.actions.declare_file(ctx.label.name + ".ltx")
    platform = ctx.actions.declare_file(ctx.label.name + ".xsa")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_bit.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_bit.log")

    open_project_or_open_checkpoint = ""
    inputs = [implementation_info.design_checkpoint]

    if project_info:
        open_project_or_open_checkpoint = "source %s\nopen_project %s.xpr\nopen_checkpoint %s" % (
            project_info.project_script.path,
            project_info.project_name,
            implementation_info.design_checkpoint.path
        )
        inputs.append(project_info.project_script)
        if hasattr(project_info, "sources") and project_info.sources:
            for lib in project_info.sources.vhdl_libs:
                inputs.extend(lib.sources.to_list())
            inputs.extend(project_info.sources.verilog_srcs.to_list())
            inputs.extend(project_info.sources.constraints.to_list())
    else:
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

    ctx.actions.run(
        outputs = [bitstream, probes, platform, log_file],
        inputs = inputs + [tcl_script],
        executable = toolchain_info.cmd,
        arguments = ["-mode", "batch", "-source", tcl_script.path, "-log", log_file.path, "-nojournal"],
        mnemonic = "VivadoBitstream",
        progress_message = "Generating bitstream with Vivado",
        env = {"HOME": "/tmp"},
    )

    return [
        FpgaBitstreamInfo(
            bitstream = bitstream,
            debug_probes = probes,
            platform = platform,
        ),
        DefaultInfo(files = depset([bitstream, probes, platform])),
    ]
