load("//fpga:providers.bzl", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")

def vivado_create_project(ctx, toolchain_info, source_info, part, top):
    project_file = ctx.actions.declare_file(ctx.label.name + ".xpr")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_create_project.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_create_project.log")

    # ... (rest of function body)
    # I need to provide the full body or at least the part that changed.
    # Actually, I'll just rewrite it correctly.

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
            "{PART_NAME}": part,
            "{ADD_VHDL_SOURCES}": "\n".join(vhdl_content),
            "{ADD_VERILOG_SOURCES}": "\n".join(verilog_content),
            "{ADD_CONSTRAINTS}": "\n".join(constraint_content),
            "{TOP_MODULE}": top if top else "top",
        },
    )

    inputs = []
    for lib in source_info.vhdl_libs:
        inputs.extend(lib.sources.to_list())
    inputs.extend(source_info.verilog_srcs.to_list())
    inputs.extend(source_info.constraints.to_list())

    ctx.actions.run(
        outputs = [project_file, log_file],
        inputs = inputs + [tcl_script],
        executable = toolchain_info.cmd,
        arguments = ["-mode", "batch", "-source", tcl_script.path, "-log", log_file.path, "-nojournal"],
        mnemonic = "VivadoProject",
        progress_message = "Creating Vivado project %s" % ctx.label.name,
    )

    return FpgaProjectInfo(
        project_file = project_file,
        tool_name = "vivado",
    )

def vivado_synthesis(ctx, toolchain_info, project_info, source_info, top, part):
    netlist = ctx.actions.declare_file(ctx.label.name + ".dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_synth.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_synth.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_synth_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_synth_utilization.rpt")

    open_project_or_in_memory = ""
    read_sources_if_memory = ""
    inputs = []

    if project_info:
        open_project_or_in_memory = "open_project %s" % project_info.project_file.path
        inputs.append(project_info.project_file)
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

    ctx.actions.expand_template(
        template = toolchain_info.templates.synthesis,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{PART_NAME}": part,
            "{TOP_MODULE}": top,
            "{OPEN_PROJECT_OR_IN_MEMORY}": open_project_or_in_memory,
            "{READ_SOURCES_IF_MEMORY}": read_sources_if_memory,
            "{SYNTH_ARGS}": "", # Can add more later
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
    )

    return FpgaSynthesisInfo(
        netlist = netlist,
        netlist_type = "dcp",
        top_entity = top,
        constraints = source_info.constraints if source_info else depset(),
    )

def vivado_implementation(ctx, toolchain_info, synthesis_info, project_info, part):
    checkpoint = ctx.actions.declare_file(ctx.label.name + "_routed.dcp")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_impl.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_impl.log")
    report_timing = ctx.actions.declare_file(ctx.label.name + "_impl_timing.rpt")
    report_utilization = ctx.actions.declare_file(ctx.label.name + "_impl_utilization.rpt")
    report_route_status = ctx.actions.declare_file(ctx.label.name + "_route_status.rpt")

    open_project_or_open_checkpoint = ""
    inputs = [synthesis_info.netlist]

    if project_info:
        open_project_or_open_checkpoint = "open_project %s\nopen_checkpoint %s" % (project_info.project_file.path, synthesis_info.netlist.path)
        inputs.append(project_info.project_file)
    else:
        open_project_or_open_checkpoint = "open_checkpoint %s" % synthesis_info.netlist.path

    ctx.actions.expand_template(
        template = toolchain_info.templates.implementation,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OPEN_PROJECT_OR_OPEN_CHECKPOINT}": open_project_or_open_checkpoint,
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
    )

    return FpgaImplementationInfo(
        design_checkpoint = checkpoint,
        bitstream_ready = True,
    )

def vivado_bitstream(ctx, toolchain_info, implementation_info, project_info, part):
    bitstream = ctx.actions.declare_file(ctx.label.name + ".bit")
    probes = ctx.actions.declare_file(ctx.label.name + ".ltx")
    platform = ctx.actions.declare_file(ctx.label.name + ".xsa")
    tcl_script = ctx.actions.declare_file(ctx.label.name + "_bit.tcl")
    log_file = ctx.actions.declare_file(ctx.label.name + "_bit.log")

    open_project_or_open_checkpoint = ""
    inputs = [implementation_info.design_checkpoint]

    if project_info:
        open_project_or_open_checkpoint = "open_project %s\nopen_checkpoint %s" % (project_info.project_file.path, implementation_info.design_checkpoint.path)
        inputs.append(project_info.project_file)
    else:
        open_project_or_open_checkpoint = "open_checkpoint %s" % implementation_info.design_checkpoint.path

    ctx.actions.expand_template(
        template = toolchain_info.templates.bitstream,
        output = tcl_script,
        substitutions = {
            "{PROJECT_NAME}": ctx.label.name,
            "{OPEN_PROJECT_OR_OPEN_CHECKPOINT}": open_project_or_open_checkpoint,
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
    )

    return FpgaBitstreamInfo(
        bitstream = bitstream,
        debug_probes = probes,
        platform = platform,
    )
