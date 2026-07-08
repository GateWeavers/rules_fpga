load("//fpga:providers.bzl", "FpgaSourceInfo", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")
load("//fpga:toolchain.bzl", "FpgaToolchainInfo")
load("//fpga:flags.bzl", "fpga_toolchain_transition")
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo")


def _collect_sources(ctx):
    # (keeping the same logic but ensuring it's accessible)
    vhdl_libs = []
    verilog_srcs = []
    constraints = []

    for dep in ctx.attr.deps:
        if VhdlLibraryInfo in dep:
            info = dep[VhdlLibraryInfo]
            print(info)

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

    print(vhdl_libs)

    return FpgaSourceInfo(
        vhdl_libs = vhdl_libs,
        verilog_srcs = depset(verilog_srcs),
        constraints = depset(constraints + ctx.files.constraints),
    )


def _fpga_project_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    source_info = _collect_sources(ctx)
    return toolchain.create_project(ctx, toolchain, source_info)

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
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None

    #todo review collect sources logic and separation between fpga generic logic and toolchain specific logic.
    if project_info:
        source_info = project_info.sources
    else:
        source_info = _collect_sources(ctx)

    return toolchain.synthesis(
        ctx,
        toolchain,
        source_info,
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
        "max_threads": attr.int(),
        "memory": attr.int(),
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
    return toolchain.implementation(ctx, toolchain)

fpga_implementation = rule(
    implementation = _fpga_implementation_impl,
    attrs = {
        "synthesis": attr.label(mandatory = True, providers = [FpgaSynthesisInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "max_threads": attr.int(),
        "memory": attr.int(),
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
    return toolchain.bitstream(ctx, toolchain)

fpga_bitstream = rule(
    implementation = _fpga_bitstream_impl,
    attrs = {
        "implementation": attr.label(mandatory = True, providers = [FpgaImplementationInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "max_threads": attr.int(),
        "memory": attr.int(),
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

def _fpga_project_gui_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    return toolchain.project_gui(ctx, toolchain)

fpga_project_gui = rule(
    implementation = _fpga_project_gui_impl,
    attrs = {
        "project": attr.label(mandatory = True, providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
        "top": attr.string(),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
    cfg = fpga_toolchain_transition,
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_dcp_gui_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    return toolchain.dcp_gui(ctx, toolchain)

fpga_dcp_gui = rule(
    implementation = _fpga_dcp_gui_impl,
    attrs = {
        "dcp": attr.label(allow_single_file = [".dcp"], mandatory = True),
        "fpga_toolchain": attr.string(),
        "fpga_toolchain_version": attr.string(),
        "toolchain": attr.label(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
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
    max_threads = 4,
    memory = 4000,
    bit_max_threads = 1,
    bit_memory = 1000,
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
        memory = memory,
        synth_options = synth_options,
        pre_synth_tcl = pre_synth_tcl,
        post_synth_tcl = post_synth_tcl,
    )

    fpga_implementation(
        name = name + "_implementation",
        synthesis = ":" + name + "_synthesis",
        # project = ":" + name + "_project",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        max_threads = max_threads,
        memory = memory,
        impl_options = impl_options,
        pre_impl_tcl = pre_impl_tcl,
        post_impl_tcl = post_impl_tcl,
    )

    fpga_bitstream(
        name = name,
        implementation = ":" + name + "_implementation",
        # project = ":" + name + "_project",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        max_threads = bit_max_threads,
        memory = bit_memory,
        bit_options = bit_options,
        pre_bit_tcl = pre_bit_tcl,
        post_bit_tcl = post_bit_tcl,
    )

    fpga_project_gui(
        name = name + ".gui",
        project = ":" + name + "_project",
        part = part,
        top = top,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        tags = ["manual"],
    )

    fpga_dcp_gui(
        name = name + "_synth.gui",
        dcp = ":" + name + "_synthesis",
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        tags = ["manual"],
    )

    fpga_dcp_gui(
        name = name + "_impl.gui",
        dcp = ":" + name + "_implementation",
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        tags = ["manual"],
    )
