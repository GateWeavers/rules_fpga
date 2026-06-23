load("//fpga:providers.bzl", "FpgaSourceInfo", "FpgaProjectInfo", "FpgaSynthesisInfo", "FpgaImplementationInfo", "FpgaBitstreamInfo")
load("//fpga:toolchain.bzl", "FpgaToolchainInfo")

def _collect_sources(ctx):
    # (keeping the same logic but ensuring it's accessible)
    vhdl_libs = []
    verilog_srcs = []
    constraints = []

    for dep in ctx.attr.deps:
        if hasattr(dep, "VhdlLibraryInfo"):
            info = dep.VhdlLibraryInfo
            vhdl_libs.append(struct(
                library = info.library_name,
                sources = info.srcs,
                vhdl_version = info.vhdl_version,
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
    return [toolchain.create_project(ctx, toolchain, source_info, ctx.attr.part, ctx.attr.top)]

fpga_project = rule(
    implementation = _fpga_project_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "constraints": attr.label_list(allow_files = True),
        "part": attr.string(mandatory = True),
        "top": attr.string(),
    },
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_synthesis_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    source_info = _collect_sources(ctx)
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    return [toolchain.synthesis(ctx, toolchain, project_info, source_info, ctx.attr.top, ctx.attr.part)]

fpga_synthesis = rule(
    implementation = _fpga_synthesis_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "constraints": attr.label_list(allow_files = True),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "top": attr.string(mandatory = True),
        "part": attr.string(mandatory = True),
    },
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_implementation_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    synthesis_info = ctx.attr.synthesis[FpgaSynthesisInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    return [toolchain.implementation(ctx, toolchain, synthesis_info, project_info, ctx.attr.part)]

fpga_implementation = rule(
    implementation = _fpga_implementation_impl,
    attrs = {
        "synthesis": attr.label(mandatory = True, providers = [FpgaSynthesisInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
    },
    toolchains = ["//fpga:toolchain_type"],
)

def _fpga_bitstream_impl(ctx):
    toolchain = ctx.toolchains["//fpga:toolchain_type"].fpga_info
    implementation_info = ctx.attr.implementation[FpgaImplementationInfo]
    project_info = ctx.attr.project[FpgaProjectInfo] if ctx.attr.project else None
    return [toolchain.bitstream(ctx, toolchain, implementation_info, project_info, ctx.attr.part)]

fpga_bitstream = rule(
    implementation = _fpga_bitstream_impl,
    attrs = {
        "implementation": attr.label(mandatory = True, providers = [FpgaImplementationInfo]),
        "project": attr.label(providers = [FpgaProjectInfo]),
        "part": attr.string(mandatory = True),
    },
    toolchains = ["//fpga:toolchain_type"],
)

def fpga_flow(name, top, part, srcs = [], deps = [], constraints = []):
    fpga_project(
        name = name + "_project",
        part = part,
        top = top,
        srcs = srcs,
        deps = deps,
        constraints = constraints,
    )

    fpga_synthesis(
        name = name + "_synthesis",
        top = top,
        part = part,
        project = ":" + name + "_project",
    )

    fpga_implementation(
        name = name + "_implementation",
        synthesis = ":" + name + "_synthesis",
        project = ":" + name + "_project",
        part = part,
    )

    fpga_bitstream(
        name = name,
        implementation = ":" + name + "_implementation",
        project = ":" + name + "_project",
        part = part,
    )
