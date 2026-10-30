# gateweavers_rules_fpga

`gateweavers_rules_fpga` provides production-grade Bazel rules and toolchain integrations for FPGA development, synthesis, implementation (Place & Route), bitstream generation, and interactive GUI debugging. It natively supports **AMD/Xilinx Vivado** and **Yosys** backends.

---

## Key Features

- **End-to-End Workflows**: Orchestrate complete FPGA builds with [`fpga_flow`](#fpga_flow) or compose fine-grained pipeline steps ([`fpga_project`](#fpga_project), [`fpga_synthesis`](#fpga_synthesis), [`fpga_implementation`](#fpga_implementation), [`fpga_bitstream`](#fpga_bitstream)).
- **Block Design & IP Management**: Declare reusable IP cores with [`fpga_ip`](#fpga_ip), instantiate them inline or Out-of-Context (OOC) with [`fpga_ip_inst`](#fpga_ip_inst), and generate block designs automatically using [`fpga_design`](#fpga_design).
- **Interactive GUI Debugging**: Inspect projects and routed checkpoints in Vivado GUI directly via `bazel run <target>.gui` without manual environment setup.
- **Hermetic & Bzlmod-Ready**: Modular toolchain resolution via Bzlmod (`vivado_toolchains`), seamless interop with [`@gateweavers_rules_vhdl`](https://github.com/GateWeavers/rules_vhdl).
- **Multi FPGA TOolchain**: By default Vivado is fully supported, Yosys and Lattice toolchains are work in progress.
---

## Setup (`MODULE.bazel`)

Add `gateweavers_rules_fpga` and `@gateweavers_rules_vhdl` to your `MODULE.bazel`:

```bzl
module(
    name = "my_fpga_project",
    version = "0.1.0",
)

bazel_dep(name = "gateweavers_rules_fpga", version = "0.3.0")
bazel_dep(name = "gateweavers_rules_vhdl", version = "0.1.0")

# 1. Configure Vivado Toolchain Backend
vivado_toolchains = use_extension("@gateweavers_rules_fpga//vivado:extensions.bzl", "vivado_toolchains")
vivado_toolchains.vivado(
    name = "vivado_2024_2",
    path = "/opt/Xilinx/Vivado/2024.2/",
    version = "2024.2",
    is_default = True,
)
use_repo(vivado_toolchains, "fpga_toolchains")

# 2. Register Toolchains
register_toolchains("@fpga_toolchains//:all")
```

---

## Toolchain Reference (`vivado/toolchain.bzl`)

### `vivado_toolchain`

Defines a Vivado FPGA toolchain instance. It packages environment setup commands, command binaries, and TCL workflow templates into an `FpgaToolchainInfo` provider wrapped within Bazel's standard `platform_common.ToolchainInfo`.

When targets such as `fpga_synthesis`, `fpga_implementation`, `fpga_bitstream`, `fpga_project`, or `fpga_design` resolve the `//fpga:toolchain_type` toolchain, they obtain this provider and delegate action generation and TCL emission to the functions configured here.

Instances of `vivado_toolchain` are generated automatically by the `vivado_toolchains` module extension (from `//vivado:extensions.bzl`). However, this rule may also be instantiated manually in a `BUILD` file to define a bespoke Vivado toolchain with customized TCL templates or invocation wrappers.

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | A unique name for this target. |
| `cmd` | `string` | No | `"vivado"` | The command name or absolute path to the Vivado executable. |
| `setup_cmd` | `string` | No | `""` | Optional shell command executed prior to running Vivado (e.g. `'source /opt/Xilinx/Vivado/2024.2/settings64.sh'`). |
| `create_project_tpl` | `label` | No | `//vivado/templates:create_project.tcl` | TCL template used by `fpga_project` to generate the project creation script. |
| `synthesis_tpl` | `label` | No | `//vivado/templates:synthesis.tcl` | TCL template used by `fpga_synthesis` to execute in-memory or project-based synthesis. |
| `implementation_tpl` | `label` | No | `//vivado/templates:implementation.tcl` | TCL template used by `fpga_implementation` for Place & Route (`opt_design`, `place_design`, `phys_opt_design`, `route_design`). |
| `bitstream_tpl` | `label` | No | `//vivado/templates:bitstream.tcl` | TCL template used by `fpga_bitstream` to generate bitstreams (`.bit`), debug probes (`.ltx`), and hardware platforms (`.xsa`). |
| `clock_domain_tpl` | `label` | No | `//vivado/templates:clock_domain.tcl` | TCL template providing clock/reset automation and AXI connection procedures used by `fpga_design`. |

#### Example: Custom Vivado Toolchain

```bzl
load("@gateweavers_rules_fpga//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "custom_vivado_impl",
    cmd = "vivado",
    setup_cmd = "source /opt/Xilinx/Vivado/2024.2/settings64.sh",
    synthesis_tpl = "//my_toolchain_templates:synthesis.tcl",
    implementation_tpl = "//my_toolchain_templates:implementation.tcl",
)

toolchain(
    name = "custom_vivado",
    toolchain = ":custom_vivado_impl",
    toolchain_type = "@gateweavers_rules_fpga//fpga:toolchain_type",
)
```

---

## Examples

### 1. Pure RTL Flow with `fpga_flow` (PYNQ-Z1 Blinky)

```bzl
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "vhdl_library")
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_flow")

vhdl_library(
    name = "blinky_lib",
    srcs = ["vhdl/blinky.vhd"],
    library_name = "blinky_lib",
    vhdl_version = "2008",
)

fpga_flow(
    name = "blinky_pynq_z1",
    top = "blinky",
    part = "xc7z020clg400-1",
    deps = [":blinky_lib"],
    constraints = ["constraints/pynq_z1.xdc"],
    generics = {
        "CLK_PERIOD_NS": "10",
    },
    synth_options = ["-flatten_hierarchy none"],
    impl_options = {
        "opt": ["-directive Explore"],
        "place": ["-directive Explore"],
    },
    bit_options = ["-bin_file"],
)
```

Build commands:
```bash
# Build bitstream (.bit, .ltx, .xsa)
bazel build //examples/blinky:blinky_pynq_z1

# Open project in GUI
bazel run //examples/blinky:blinky_pynq_z1.gui
```

---

### 2. Zynq SoC System with Vivado Block Design (`examples/zynq`)

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl",
    "fpga_clock_domain",
    "fpga_ip",
    "fpga_ip_inst",
    "fpga_design",
    "fpga_flow",
)

# 1. Define clock domain
fpga_clock_domain(
    name = "main_clk",
    clock_frequency = "100MHz",
    clock_pin = "ps7_0/FCLK_CLK0",
    reset_pin = "ps7_0/FCLK_RESET0_N",
    reset_type = "active_low",
)

# 2. Declare IP module
fpga_ip(
    name = "crc_ip",
    entity_name = "crc_top_wrapper",
    clock_port = "s_axi_aclk",
    reset_port = "s_axi_aresetn",
    generics = {"C_S_AXI_ADDR_WIDTH": "6"},
    inst_tcl = "//examples/zynq/ip/ip-crc/src:vivado_inst_crc.tcl",
    interfaces = {
        "s_axi": "slave",
        "M_AXI": "master",
    },
    deps = ["//examples/zynq/ip/ip-crc/src:src"],
)

# 3. Create IP instances
fpga_ip_inst(
    name = "crc_0",
    ip = ":crc_ip",
    clock_domain = ":main_clk",
    generics = {"C_S_AXI_ADDR_WIDTH": "7"},
    memory_mapping = {
        "SEG_CRC": "0x43DB0000",
        "SEG_CRC_DMA": "0x43DC0000",
    },
    ooc = False,
)

fpga_ip_inst(
    name = "crc_1",
    ip = ":crc_ip",
    clock_domain = ":main_clk",
    memory_mapping = {
        "SEG_CRC": "0x43D90000",
        "SEG_CRC_DMA": "0x43D60000",
    },
    ooc = False,
)

# 4. Generate block design
fpga_design(
    name = "zynq_design",
    top = "zynq_design_wrapper",
    part = "xc7z010clg400-1",
    ips = [":crc_0", ":crc_1"],
    pre_bd_hook = ":ps.tcl",
    post_bd_hook = ":ps_master.tcl",
)

# 5. Run complete flow
fpga_flow(
    name = "zynq_flow",
    top = "zynq_design_wrapper",
    part = "xc7z010clg400-1",
    design = ":zynq_design",
    max_threads = 4,
)
```

---

### 3. Fine-Grained Step-by-Step Flow

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl",
    "fpga_sources",
    "fpga_project",
    "fpga_synthesis",
    "fpga_implementation",
    "fpga_bitstream",
)

fpga_sources(
    name = "core_srcs",
    srcs = ["src/core.vhd"],
    constraints = ["constraints/pins.xdc"],
    library_name = "core_lib",
)

fpga_project(
    name = "core_project",
    top = "core_top",
    part = "xc7z020clg400-1",
    deps = [":core_srcs"],
)

fpga_synthesis(
    name = "core_synthesis",
    top = "core_top",
    part = "xc7z020clg400-1",
    project = ":core_project",
    synth_options = ["-flatten_hierarchy full"],
)

fpga_implementation(
    name = "core_implementation",
    part = "xc7z020clg400-1",
    synthesis = ":core_synthesis",
    impl_options = {
        "opt": ["-directive Explore"],
        "place": ["-directive Explore"],
    },
)

fpga_bitstream(
    name = "core_bitstream",
    part = "xc7z020clg400-1",
    implementation = ":core_implementation",
    bit_options = ["-bin_file"],
)
```

---

## Testing & CI/CD

`rules_fpga` includes a comprehensive test suite using `@bazel_skylib//lib:unittest.bzl`:
* **Pure Starlark Tests**: File classification, depset merging, VHDL library unit extraction.
* **Analysis Tests**: Validates provider propagation, lazy TCL script writing, Out-of-Context deduplication, template expansion actions, and action inputs/outputs.
* **Hermetic Execution**: All tests execute during the analysis phase without invoking Vivado or requiring EDA licenses.

Run the test suite locally:
```bash
bazel test //fpga/tests:all //vivado/tests:all
```

Validate examples without hardware tools:
```bash
bazel build //examples/blinky:all //examples/zynq/... --nobuild
```

---

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.
