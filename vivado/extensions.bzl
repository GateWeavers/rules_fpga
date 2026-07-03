# Vivado Toolchain Module Extension and Hub Repository

_HUB_HEADER = """
package(default_visibility = ["//visibility:public"])

# Matchers for default values
config_setting(
    name = "match_version_default",
    flag_values = {"@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version": "default"},
)
"""

_VIVADO_TC_TEMPLATE = """
# --- Toolchain: {name} (Vivado) ---
load("@gateweavers_rules_fpga//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "{name}_impl",
    cmd = "{cmd}",
    setup_cmd = "{setup_cmd}",
)

config_setting(
    name = "{name}_match_version",
    flag_values = {{"@gateweavers_rules_fpga//fpga/config:fpga_toolchain_version": "{version}"}},
)

config_setting(
    name = "{name}_match_toolchain",
    flag_values = {{"@gateweavers_rules_fpga//fpga/config:fpga_toolchain": "vivado"}},
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_fpga//fpga:toolchain_type",
    target_settings = [
        ":{name}_match_toolchain",
        ":{name}_match_version",
    ],
)

{default_rule}

alias(
    name = "{name}",
    actual = ":{name}_toolchain",
)
"""

def _local_vivado_repo_impl(ctx):
    path = ctx.attr.path
    if not path.startswith("/"):
        workspace_root = ctx.path(Label("@//:MODULE.bazel")).dirname
        path = str(workspace_root.get_child(path))

    ctx.symlink(path, "vivado_home")

    vitis_path = ctx.attr.vitis_path
    if not vitis_path:
        vitis_path = path.replace("Vivado", "Vitis").replace("vivado", "vitis")

    if vitis_path != path:
        vitis_dir = ctx.path(vitis_path)
        if vitis_dir.exists:
            ctx.symlink(vitis_path, "vitis_home")

    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "bin", srcs = ["vivado_home/bin/vivado"])
""")

local_vivado_repository = repository_rule(
    implementation = _local_vivado_repo_impl,
    attrs = {
        "path": attr.string(mandatory = True),
        "vitis_path": attr.string(),
    },
)

def _fpga_hub_repo_impl(ctx):
    tools = json.decode(ctx.attr.tools_json)
    default_toolchain = ctx.attr.default_toolchain

    registry_content = "TOOLCHAIN_REGISTRY = {\n"
    build_content = _HUB_HEADER

    for tool in tools:
        name = tool["name"]
        type = tool["type"]

        registry_content += '    "{}": struct(toolchain="{}", version="{}"),\n'.format(
            name, type, tool["version"]
        )

        if type == "vivado":
            default_rule = ""
            if name == default_toolchain:
                default_rule = """
toolchain(
    name = "{name}_default_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_fpga//fpga:toolchain_type",
    target_settings = [
        ":{name}_match_toolchain",
        ":match_version_default",
    ],
)
""".format(name = name)

            build_content += _VIVADO_TC_TEMPLATE.format(
                name = name,
                cmd = tool["cmd"],
                setup_cmd = tool["setup_cmd"],
                version = tool["version"],
                default_rule = default_rule,
            )

    registry_content += "}\n\n"
    registry_content += 'DEFAULT_TOOLCHAIN = "{}"\n'.format(default_toolchain)

    ctx.file("registry.bzl", registry_content)
    ctx.file("BUILD", build_content)

fpga_hub_repo = repository_rule(
    implementation = _fpga_hub_repo_impl,
    attrs = {
        "tools_json": attr.string(mandatory = True),
        "default_toolchain": attr.string(),
    },
)

_vivado_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "vitis_path": attr.string(),
        "version": attr.string(mandatory = True),
        "is_default": attr.bool(default = False),
    }
)

def _vivado_extension_impl(ctx):
    tools = []
    default_toolchain = ""

    for mod in ctx.modules:
        for tool in mod.tags.vivado:
            if tool.is_default:
                if default_toolchain:
                    fail("Only one Vivado toolchain can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            # Instantiate local repository
            local_vivado_repository(
                name = tool.name,
                path = tool.path,
                vitis_path = tool.vitis_path,
            )

            # Compute command and setup command from path
            path_stripped = tool.path.rstrip("/")
            cmd = "vivado"
            setup_cmd = "source " + path_stripped + "/settings64.sh"

            tools.append({
                "name": tool.name,
                "type": "vivado",
                "version": tool.version,
                "cmd": cmd,
                "setup_cmd": setup_cmd,
            })

    fpga_hub_repo(
        name = "fpga_toolchains",
        tools_json = json.encode(tools),
        default_toolchain = default_toolchain,
    )

    return ctx.extension_metadata(
        reproducible = True,
    )

vivado_toolchains = module_extension(
    implementation = _vivado_extension_impl,
    tag_classes = {
        "vivado": _vivado_tag,
    },
)
