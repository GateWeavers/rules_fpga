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
