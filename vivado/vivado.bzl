load("//fpga:providers.bzl", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")
load("//fpga:utility.bzl", "get_resource_set")

def _get_vhdl_flag(version):
    if not version:
        return ""
    # Normalize version string
    v = str(version).lower().strip()
    if v in "2008":
        return "-vhdl2008"
    if v in "2019":
        return "-vhdl2019"
    return ""

def _format_sources(source_info, use_short_path = False, use_read_cmd = False):
    inputs = []
    vhdl_content = []
    for lib in source_info.vhdl_libs:
        files = [f.short_path if use_short_path else f.path for f in lib.sources.to_list()]
        flag = _get_vhdl_flag(getattr(lib, "vhdl_version", None))
        flag_str = " " + flag if flag else ""
        vhdl_content.append("read_vhdl -library %s%s {%s}" % (lib.library, flag_str, " ".join(files)))
        inputs.extend(lib.sources.to_list())

    verilog_files = [f.short_path if use_short_path else f.path for f in source_info.verilog_srcs.to_list()]
    if verilog_files:
        if use_read_cmd:
            verilog_content = ["read_verilog {%s}" % " ".join(verilog_files)]
        else:
            verilog_content = ["add_files -norecurse {%s}" % " ".join(verilog_files)]
    else:
        verilog_content = []
    inputs.extend(source_info.verilog_srcs.to_list())

    constraint_files = [f.short_path if use_short_path else f.path for f in source_info.constraints.to_list()]
    if constraint_files:
        if use_read_cmd:
            constraint_content = ["read_xdc {%s}" % " ".join(constraint_files)]
        else:
            constraint_content = ["add_files -fileset constrs_1 -norecurse {%s}" % " ".join(constraint_files)]
    else:
        constraint_content = []
    inputs.extend(source_info.constraints.to_list())

    return vhdl_content, verilog_content, constraint_content, inputs

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

def vivado_create_project(ctx, toolchain_info, source_info):
    part = ctx.attr.part
    top = getattr(ctx.attr, "top", None)

    tcl_script = ctx.actions.declare_file(ctx.label.name + "_create_project.tcl")

    vhdl_content, verilog_content, constraint_content, inputs = _format_sources(source_info, use_short_path = False, use_read_cmd = False)

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
        DefaultInfo(files = depset([tcl_script] + inputs)),
    ]

def vivado_synthesis(ctx, toolchain_info, source_info):
    project_info = ctx.attr.project[FpgaProjectInfo] if getattr(ctx.attr, "project", None) else None
    top = ctx.attr.top
    part = ctx.attr.part
    generics = getattr(ctx.attr, "generics", {})
    defines = getattr(ctx.attr, "defines", {})
    synth_options = getattr(ctx.attr, "synth_options", [])
    pre_synth_tcl = getattr(ctx.file, "pre_synth_tcl", None)
    post_synth_tcl = getattr(ctx.file, "post_synth_tcl", None)
    max_threads = getattr(ctx.attr, "max_threads", 4)
    memory = getattr(ctx.attr, "memory", 4000)

    netlist = ctx.actions.declare_file(ctx.label.name + ".dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_synth.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_synth.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_synth_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_synth_utilization.rpt")

    open_project_or_in_memory = ""
    read_sources_if_memory = ""
    inputs = []

    if project_info:
        open_project_or_in_memory = "source %s" % (project_info.project_script.path)
        inputs.extend(ctx.attr.project[DefaultInfo].files.to_list())
    else:
        open_project_or_in_memory = "create_project -in_memory -part %s" % part

        vhdl_content, verilog_content, constraint_content, source_inputs = _format_sources(source_info, use_short_path = False, use_read_cmd = True)
        inputs.extend(source_inputs)

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

    command = "%s && %s -mode batch -source %s -log %s -nojournal" % (
        toolchain_info.setup_cmd,
        toolchain_info.cmd,
        tcl_script.path,
        log_file.path,
    )

    ctx.actions.run_shell(
        outputs = [netlist, log_file, report_timing, report_utilization],
        inputs = inputs + [tcl_script],
        command = command,
        mnemonic = "VivadoSynth",
        progress_message = "Synthesizing %s with Vivado" % top,
        env = {"HOME": "/tmp"},
        resource_set = get_resource_set(max_threads, memory),
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

    open_project_or_open_checkpoint = ""
    inputs = [synthesis_info.netlist]
    if synthesis_info.constraints:
        inputs.extend(synthesis_info.constraints.to_list())

    # if project_info:
    #     open_project_or_open_checkpoint = "source %s\nopen_project %s.xpr\nopen_checkpoint %s" % (
    #         project_info.project_script.path,
    #         project_info.project_name,
    #         synthesis_info.netlist.path
    #     )
    #     inputs.append(project_info.project_script)
    #     if hasattr(project_info, "sources") and project_info.sources:
    #         for lib in project_info.sources.vhdl_libs:
    #             inputs.extend(lib.sources.to_list())
    #         inputs.extend(project_info.sources.verilog_srcs.to_list())
    #         inputs.extend(project_info.sources.constraints.to_list())
    # else:
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

    command = "%s && %s -mode batch -source %s -log %s -nojournal" % (
        toolchain_info.setup_cmd,
        toolchain_info.cmd,
        tcl_script.path,
        log_file.path,
    )

    ctx.actions.run_shell(
        outputs = [checkpoint, log_file, report_timing, report_utilization, report_route_status],
        inputs = inputs + [tcl_script],
        command = command,
        mnemonic = "VivadoImpl",
        progress_message = "Implementing %s with Vivado" % synthesis_info.top_entity,
        env = {"HOME": "/tmp"},
        resource_set = get_resource_set(max_threads, memory),
    )

    return [
        FpgaImplementationInfo(
            design_checkpoint = checkpoint,
            bitstream_ready = True,
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

    open_project_or_open_checkpoint = ""
    inputs = [implementation_info.design_checkpoint]
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
        inputs = inputs + [tcl_script],
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

def vivado_project_gui(ctx, toolchain_info):
    project_info = ctx.attr.project[FpgaProjectInfo]
    source_info = project_info.sources
    part = ctx.attr.part
    top = getattr(ctx.attr, "top", None)

    # Generate a TCL script using short_path to work inside runfiles tree
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_gui.tcl")

    vhdl_content, verilog_content, constraint_content, inputs = _format_sources(source_info, use_short_path = True, use_read_cmd = False)

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

    # Generate bash script
    runner = _write_gui_runner(ctx, toolchain_info, tcl_script)

    inputs.append(tcl_script)

    return [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(files = inputs),
        )
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