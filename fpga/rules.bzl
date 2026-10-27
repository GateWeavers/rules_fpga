load(
    "//fpga:providers.bzl",
    "ConstraintInfo",
    "FpgaBitstreamInfo",
    "FpgaClockDomainInfo",
    "FpgaDesignInfo",
    "FpgaImplementationInfo",
    "FpgaIpInfo",
    "FpgaProjectInfo",
    "FpgaSourceInfo",
    "FpgaSynthesisInfo",
    "VerilogInfo",
)
load("//fpga:toolchain.bzl", "FpgaToolchainInfo")
load("//fpga:flags.bzl", "fpga_toolchain_transition")
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "VhdlLibraryUnitInfo")
load("//fpga:source.bzl","collect_sources")

load("//fpga:design.bzl","fpga_design")
# ,"fpga_clock_domain", "fpga_ip_config")
load("//fpga:common.bzl","SOURCE_ATTRS","TOOLCHAIN_ATTRS","TOOLCHAIN_TYPE","VHDL_VERSIONS")
# fpga_design = fpga_design
# fpga_clock_domain = fpga_clock_domain
# fpga_ip_config = fpga_ip_config


def _own_sources(ctx, extra_deps = []):
    return collect_sources(
        ctx,
        srcs = ctx.files.srcs,
        constraints = ctx.files.constraints,
        deps = ctx.attr.deps + extra_deps,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
    )


def _fpga_project_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info

    # design BD scripts are provided by FpgaDesignInfo if present.
    design = ctx.attr.design
    design_info = design[FpgaDesignInfo] if design else None
    source_info = _own_sources(ctx, [design] if design else [])

    return toolchain.create_project(ctx, toolchain, source_info, design_info)

fpga_project = rule(
    implementation = _fpga_project_impl,
    doc = "Creates an FPGA project from sources and an optional generated design.",
    attrs = dict(
        SOURCE_ATTRS,
        design = attr.label(
            providers = [[FpgaDesignInfo, FpgaSourceInfo]],
            doc = "Optional fpga_design whose block design script is sourced by the project.",
        ),
        part = attr.string(mandatory = True),
        top = attr.string(),
        top_bd_script = attr.label(allow_files = True),
        **TOOLCHAIN_ATTRS
    ),
    cfg = fpga_toolchain_transition,
    toolchains = [TOOLCHAIN_TYPE],
)

def _fpga_synthesis_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info

    has_own_sources = bool(ctx.files.srcs or ctx.files.constraints or ctx.attr.deps)
    if ctx.attr.project:
        if has_own_sources:
            fail(("%s: 'project' is mutually exclusive with srcs/constraints/deps; " +
                  "sources come from the project.") % ctx.label)
        source_info = ctx.attr.project[FpgaProjectInfo].sources
    else:
        source_info = _own_sources(ctx)

    return toolchain.synthesis(ctx, toolchain, source_info)

fpga_synthesis = rule(
    implementation = _fpga_synthesis_impl,
    doc = "Synthesizes either an fpga_project, or standalone sources (in-memory project).",
    attrs = dict(
        SOURCE_ATTRS,
        project = attr.label(
            providers = [FpgaProjectInfo],
            doc = "Mutually exclusive with srcs/constraints/deps.",
        ),
        top = attr.string(mandatory = True),
        part = attr.string(mandatory = True),
        generics = attr.string_dict(),
        defines = attr.string_dict(),
        max_threads = attr.int(default = 4),
        memory = attr.int(default = 4000),
        synth_options = attr.string_list(),
        pre_synth_tcl = attr.label(allow_single_file = [".tcl"]),
        post_synth_tcl = attr.label(allow_single_file = [".tcl"]),
        **TOOLCHAIN_ATTRS
    ),
    cfg = fpga_toolchain_transition,
    toolchains = [TOOLCHAIN_TYPE],
)

def _fpga_implementation_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info
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
        "max_threads": attr.int(default = 4),
        "memory": attr.int(default = 4000),
        "impl_options": attr.string_list_dict(default = {}),
        "pre_impl_tcl": attr.label(allow_single_file = [".tcl"]),
        "post_impl_tcl": attr.label(allow_single_file = [".tcl"]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = [TOOLCHAIN_TYPE],
)

def _fpga_bitstream_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info
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
        "max_threads": attr.int(default = 1),
        "memory": attr.int(default = 1000),
        "bit_options": attr.string_list(default = []),
        "pre_bit_tcl": attr.label(allow_single_file = [".tcl"]),
        "post_bit_tcl": attr.label(allow_single_file = [".tcl"]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = fpga_toolchain_transition,
    toolchains = [TOOLCHAIN_TYPE],
)

def _fpga_project_gui_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info
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
    toolchains = [TOOLCHAIN_TYPE],
)

def _fpga_dcp_gui_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info
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
    toolchains = [TOOLCHAIN_TYPE],
)

def fpga_flow(
        name,
        top,
        part,
        srcs = [],
        deps = [],
        constraints = [],
        design = None,
        ips = [],
        library_name = "work",
        vhdl_version = "2008",
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
        pre_bd_hook = None,
        post_bd_hook = None,
        tags = []):
    """Full flow.

    Args:
      design: an existing fpga_design target. Mutually exclusive with `ips`.
      ips: fpga_ip_inst targets. When given (and no `design`), a design
        `<name>_design` is created from them.
    """
    if design and ips:
        fail("fpga_flow %s: 'design' and 'ips' are mutually exclusive" % name)
    if design and (pre_bd_hook or post_bd_hook):
        fail("fpga_flow %s: bd hooks belong on the fpga_design when 'design' is given" % name)

    if ips:
        design_name = name + "_design"
        fpga_design(
            name = design_name,
            top = top,
            part = part,
            ips = ips,
            deps = deps,
            library_name = library_name,
            vhdl_version = vhdl_version,
            pre_bd_hook = pre_bd_hook,
            post_bd_hook = post_bd_hook,
            fpga_toolchain = fpga_toolchain,
            fpga_toolchain_version = fpga_toolchain_version,
            toolchain = toolchain,
            tags = tags,
        )
        design = ":" + design_name

    fpga_project(
        name = name + "_project",
        part = part,
        top = top,
        srcs = srcs,
        deps = deps,
        constraints = constraints,
        design = design,
        library_name = library_name,
        vhdl_version = vhdl_version,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        tags = tags,
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
        tags = tags,
    )

    fpga_implementation(
        name = name + "_implementation",
        synthesis = ":" + name + "_synthesis",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        max_threads = max_threads,
        memory = memory,
        impl_options = impl_options,
        pre_impl_tcl = pre_impl_tcl,
        post_impl_tcl = post_impl_tcl,
        tags = tags,
    )

    fpga_bitstream(
        name = name,
        implementation = ":" + name + "_implementation",
        part = part,
        fpga_toolchain = fpga_toolchain,
        fpga_toolchain_version = fpga_toolchain_version,
        toolchain = toolchain,
        max_threads = bit_max_threads,
        memory = bit_memory,
        bit_options = bit_options,
        pre_bit_tcl = pre_bit_tcl,
        post_bit_tcl = post_bit_tcl,
        tags = tags,
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