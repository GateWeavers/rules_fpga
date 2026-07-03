load("//fpga:providers.bzl", "FpgaSourceInfo", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")
load("//fpga:toolchain.bzl", "FpgaToolchainInfo")
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo")

def _collect_sources(ctx):
    # (keeping the same logic but ensuring it's accessible)
    vhdl_libs = []
    verilog_srcs = []
    constraints = []

    for dep in ctx.attr.deps:
        if VhdlLibraryInfo in dep:
            info = dep[VhdlLibraryInfo]
            for lib_struct in info.libraries.values():
                vhdl_libs.append(struct(
                    library = lib_struct.library_name,
                    sources = lib_struct.sources,
                    vhdl_version = lib_struct.vhdl_version,
                ))
        elif FpgaSourceInfo in dep:
            # Propagate sources from other FPGA rules if needed
            pass

    for f in ctx.files.srcs:
        if f.extension == "v" or f.extension == "sv":
            verilog_srcs.append(f)
        elif f.extension == "xdc" or f.extension == "sdc":
            constraints.append(f)

    return FpgaSourceInfo(
        vhdl_libs = vhdl_libs,
        verilog_srcs = depset(verilog_srcs),
        constraints = depset(constraints + ctx.files.constraints),
    )

def _fpga_project_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    source_info = _collect_sources(ctx)
    return toolchain.create_project(ctx, toolchain, source_info, ctx.attr.part, ctx.attr.top)

FpgaConfigInfo = provider(
    doc = "Provider for FPGA configuration flags.",
    fields = {"value": "The current value of the flag."}
)

def _config_flag_impl(ctx):
    return FpgaConfigInfo(value = ctx.build_setting_value)

config_flag = rule(
    implementation = _config_flag_impl,
    build_setting = config.string(flag = True),
    doc = "A string flag used to configure FPGA toolchain parameters.",
)

def _fpga_toolchain_transition_impl(settings, attr):
    toolchain = settings["@gateweavers_rules_fpga//fpga/config:fpga_toolchain"]
    version = settings["@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version"]
    if hasattr(attr, "toolchain") and attr.toolchain:
        tc_name = attr.toolchain.name
        if "_" in tc_name:
            parts = tc_name.split("_", 1)
            toolchain = parts[0]
            version = parts[1].replace("_", ".")
        else:
            toolchain = tc_name
            version = "default"
    else:
        if hasattr(attr, "fpga_toolchain") and attr.fpga_toolchain:
            toolchain = attr.fpga_toolchain
        if hasattr(attr, "fpga_toolchain_version") and attr.fpga_toolchain_version:
            version = attr.fpga_toolchain_version
    return {
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain": toolchain,
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version": version,
    }

fpga_toolchain_transition = transition(
    implementation = _fpga_toolchain_transition_impl,
    inputs = [
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain",
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version",
    ],
    outputs = [
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain",
        "@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version",
    ],
)

fpga_project = rule(
    implementation = _fpga_project_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "constraints": attr.label_list(allow_files = True),
        "part": attr.string(mandatory = True),
        "top": attr.string(),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_synthesis_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    source_info = _collect_sources(ctx)
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    if project_info and hasattr(project_info, "sources") and project_info.sources:
        source_info = project_info.sources
    return toolchain.synthesis(
        ctx,
        toolchain,
        project_info,
        source_info,
        ctx.attr.top,
        ctx.attr.part,
        generics = ctx.attr.generics,
        defines = ctx.attr.defines,
        max_threads = ctx.attr.max_threads,
        synth_options = ctx.attr.synth_options,
        pre_synth_tcl = ctx.file.pre_synth_tcl,
        post_synth_tcl = ctx.file.post_synth_tcl,
    )

fpga_synthesis = rule(
    implementation = _fpga_synthesis_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "constraints": attr.label_list(allow_files = True),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "top": attr.string(mandatory = True),
        "part": attr.string(mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "generics": attr.string_dict(default = {}),
        "defines": attr.string_dict(default = {}),
        "max_threads": attr.int(default = 8),
        "synth_options": attr.string_list(default = []),
        "pre_synth_tcl": attr.label(allow_single_file = [".tcl"]),
        "post_synth_tcl": attr.label(allow_single_file = [".tcl"]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_implementation_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    synthesis_info = ctx.attr.synthesis[FpgaSynthesisInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    return toolchain.implementation(
        ctx,
        toolchain,
        synthesis_info,
        project_info,
        ctx.attr.part,
        max_threads = ctx.attr.max_threads,
        impl_options = ctx.attr.impl_options,
        pre_impl_tcl = ctx.file.pre_impl_tcl,
        post_impl_tcl = ctx.file.post_impl_tcl,
    )

fpga_implementation = rule(
    implementation = _fpga_implementation_impl,
    attrs = {
        "synthesis": attr.label(mandatory = True, providers = [FpgaSynthesisInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "max_threads": attr.int(default = 8),
        "impl_options": attr.string_list_dict(default = {}),
        "pre_impl_tcl": attr.label(allow_single_file = [".tcl"]),
        "post_impl_tcl": attr.label(allow_single_file = [".tcl"]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_bitstream_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    implementation_info = ctx.attr.implementation[FpgaImplementationInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    return toolchain.bitstream(
        ctx,
        toolchain,
        implementation_info,
        project_info,
        ctx.attr.part,
        bit_options = ctx.attr.bit_options,
        pre_bit_tcl = ctx.file.pre_bit_tcl,
        post_bit_tcl = ctx.file.post_bit_tcl,
    )

fpga_bitstream = rule(
    implementation = _fpga_bitstream_impl,
    attrs = {
        "implementation": attr.label(mandatory = True, providers = [FpgaImplementationInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "bit_options": attr.string_list(default = []),
        "pre_bit_tcl": attr.label(allow_single_file = [".tcl"]),
        "post_bit_tcl": attr.label(allow_single_file = [".tcl"]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = ["//fpga:toolchain_type"],
)

def fpga_flow(
    name,
    top,
    part,
    srcs = [],
    deps = [],
    constraints = [],
    fpga_toolchain = None,
    fpga_toolchain_version = None,
    toolchain = None,
    generics = {},
    defines = {},
    max_threads = 8,
    synth_options = [],
    impl_options = {},
    bit_options = [],
    pre_synth_tcl = None,
    post_synth_tcl = None,
    pre_impl_tcl = None,
    post_impl_tcl = None,
    pre_bit_tcl = None,
    post_bit_tcl = None,
):
    fpga_project(
        name = name + "_project",
        part = part,
        top = top,
        srcs = srcs,
        deps = deps,
        constraints = constraints,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
    )

    fpga_synthesis(
        name = name + "_synthesis",
        top = top,
        part = part,
        project = ":" + name + "_project",
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        generics = generics,
        defines = defines,
        max_threads = max_threads,
        synth_options = synth_options,
        pre_synth_tcl = pre_synth_tcl,
        post_synth_tcl = post_synth_tcl,
    )

    fpga_implementation(
        name = name + "_implementation",
        synthesis = ":" + name + "_synthesis",
        project = ":" + name + "_project",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        max_threads = max_threads,
        impl_options = impl_options,
        pre_impl_tcl = pre_impl_tcl,
        post_impl_tcl = post_impl_tcl,
    )

    fpga_bitstream(
        name = name,
        implementation = ":" + name + "_implementation",
        project = ":" + name + "_project",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        bit_options = bit_options,
        pre_bit_tcl = pre_bit_tcl,
        post_bit_tcl = post_bit_tcl,
    )
