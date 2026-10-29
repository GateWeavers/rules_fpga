## Rule API Reference

### `fpga_flow`

Macro that instantiates an entire FPGA development pipeline from sources or a block design.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_flow")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Base target name. |
| `top` | `string` | Yes | - | Top-level entity/module name. |
| `part` | `string` | Yes | - | Target FPGA part number (e.g. `xc7z020clg400-1`). |
| `srcs` | `label_list` | No | `[]` | Direct HDL source files (`.vhd`, `.vhdl`, `.v`, `.sv`) or data files. |
| `deps` | `label_list` | No | `[]` | Upstream libraries (`fpga_sources` or `vhdl_library`). |
| `constraints` | `label_list` | No | `[]` | Physical and timing constraint files (`.xdc`, `.sdc`). |
| `design` | `label` | No | `None` | Pre-existing `fpga_design` target. Mutually exclusive with `ips`. |
| `ips` | `label_list` | No | `[]` | List of `fpga_ip_inst` targets. When provided, automatically creates `<name>_design`. Mutually exclusive with `design`. |
| `generics` | `string_dict` | No | `{}` | Top-level generics/parameters passed to synthesis. |
| `defines` | `string_dict` | No | `{}` | Verilog macro definitions. |
| `synth_options` | `string_list` | No | `[]` | Additional flags passed to synthesis (e.g. `["-flatten_hierarchy full"]`). |
| `impl_options` | `string_list_dict` | No | `{}` | Stage-specific options for implementation (keys: `"opt"`, `"place"`, `"phys_opt"`, `"route"`). |
| `bit_options` | `string_list` | No | `[]` | Options passed to bitstream generation (e.g. `["-bin_file"]`). |
| `pre_synth_tcl` / `post_synth_tcl` | `label` | No | `None` | TCL scripts executed before/after synthesis. |
| `pre_impl_tcl` / `post_impl_tcl` | `label` | No | `None` | TCL scripts executed before/after implementation. |
| `pre_bit_tcl` / `post_bit_tcl` | `label` | No | `None` | TCL scripts executed before/after bitstream generation. |
| `pre_bd_hook` / `post_bd_hook` | `label` | No | `None` | TCL scripts sourced before/after block design generation (e.g., PS configuration). |
| `max_threads` | `int` | No | `4` | Maximum parallel threads for synthesis and implementation. |
| `memory` | `int` | No | `4000` | Estimated memory resource in MB. |
| `toolchain` | `label` | No | `None` | Explicit toolchain target override. |

#### Generated Targets

* `<name>`: The primary `fpga_bitstream` target producing `.bit`, `.ltx`, and `.xsa`.
* `<name>_project`: `fpga_project` target creating the project scripts.
* `<name>_synthesis`: `fpga_synthesis` target creating the synthesized DCP.
* `<name>_implementation`: `fpga_implementation` target creating the routed DCP.
* `<name>_design`: `fpga_design` target (created when `ips` is specified).
* `<name>.gui`: Interactive launcher to open the project in the Vivado GUI (`bazel run :<name>.gui`).
* `<name>_synth.gui`: Interactive launcher to inspect the synthesized checkpoint (`bazel run :<name>_synth.gui`).
* `<name>_impl.gui`: Interactive launcher to inspect the routed checkpoint (`bazel run :<name>_impl.gui`).

---

### `fpga_synthesis`

Synthesizes RTL sources into netlist checkpoints (`.dcp`) using the resolved FPGA toolchain.

Can run either as a **standalone in-memory project** (from `srcs`, `deps`, `constraints`) or from an existing **`fpga_project`** (via `project`).

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_synthesis")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `top` | `string` | Yes | - | Top-level entity/module name. |
| `part` | `string` | Yes | - | FPGA part number. |
| `project` | `label` | No | `None` | Pre-initialized `fpga_project`. Mutually exclusive with `srcs`/`deps`/`constraints`. |
| `srcs` | `label_list` | No | `[]` | Direct HDL files (`.vhd`, `.vhdl`, `.v`, `.sv`). |
| `deps` | `label_list` | No | `[]` | Upstream libraries (`fpga_sources` or `vhdl_library`). |
| `constraints` | `label_list` | No | `[]` | Constraints (`.xdc`, `.sdc`). |
| `generics` | `string_dict` | No | `{}` | Generic parameters passed as `-generic {K=V ...}`. |
| `defines` | `string_dict` | No | `{}` | Verilog macro defines. |
| `synth_options` | `string_list` | No | `[]` | Additional synthesis command flags. |
| `pre_synth_tcl` / `post_synth_tcl` | `label` | No | `None` | Pre- and post-synthesis TCL scripts. |
| `max_threads` | `int` | No | `4` | Thread allocation for synthesis action. |
| `memory` | `int` | No | `4000` | Estimated RAM allocation in MB. |

#### Outputs

* `<name>.dcp`: Synthesized netlist design checkpoint.
* `<name>_synth.log`: Tool synthesis execution log.
* `<name>_synth_timing.rpt`: Post-synthesis timing report.
* `<name>_synth_utilization.rpt`: Post-synthesis resource utilization report.

---

### `fpga_implementation`

Executes Place & Route (`opt_design`, `place_design`, `phys_opt_design`, `route_design`) starting from a synthesized checkpoint.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_implementation")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `synthesis` | `label` | Yes | - | Target providing `FpgaSynthesisInfo` (e.g. `fpga_synthesis`). |
| `part` | `string` | Yes | - | FPGA part number. |
| `impl_options` | `string_list_dict` | No | `{}` | Dictionary of stage options: `"opt"`, `"place"`, `"phys_opt"`, `"route"`. |
| `pre_impl_tcl` / `post_impl_tcl` | `label` | No | `None` | Pre- and post-implementation TCL hooks. |
| `max_threads` | `int` | No | `4` | Parallel thread limit. |
| `memory` | `int` | No | `4000` | Estimated RAM allocation in MB. |

#### Outputs

* `<name>_routed.dcp`: Fully placed and routed checkpoint.
* `<name>_impl.log`: Place and route log file.
* `<name>_impl_timing.rpt`: Post-route timing summary report.
* `<name>_impl_utilization.rpt`: Post-route device utilization report.
* `<name>_route_status.rpt`: Route status report.

---

### `fpga_bitstream`

Generates device bitstreams, hardware platforms, and debug probe files from a routed checkpoint.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_bitstream")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `implementation` | `label` | Yes | - | Target providing `FpgaImplementationInfo` (e.g. `fpga_implementation`). |
| `part` | `string` | Yes | - | FPGA part number. |
| `bit_options` | `string_list` | No | `[]` | Extra options passed to `write_bitstream` (e.g. `["-bin_file"]`). |
| `pre_bit_tcl` / `post_bit_tcl` | `label` | No | `None` | TCL hooks executed before/after bitstream generation. |

#### Outputs

* `<name>.bit`: FPGA programming bitstream.
* `<name>.ltx`: Integrated Logic Analyzer (ILA) debug probes file.
* `<name>.xsa`: Hardware platform archive for embedded software development in Vitis.
* `<name>_bit.log`: Bitstream generation log.

---

### `fpga_project`

Creates an FPGA project script and lazy sources manifest. Used when a project directory structure is needed for synthesis or interactive inspection.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_project")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `part` | `string` | Yes | - | FPGA part number. |
| `top` | `string` | No | `""` | Top-level entity/module name. |
| `design` | `label` | No | `None` | Optional `fpga_design` target to integrate into the project. |
| `srcs` | `label_list` | No | `[]` | Direct HDL files. |
| `deps` | `label_list` | No | `[]` | Upstream library dependencies. |
| `constraints` | `label_list` | No | `[]` | Constraint files (`.xdc`, `.sdc`). |
| `library_name` | `string` | No | `"work"` | VHDL library name for direct sources. |
| `vhdl_version` | `string` | No | `"2008"` | VHDL version standard (`"93"`, `"2008"`, `"2019"`). |

#### Outputs

* `<name>_create_project.tcl`: Master project creation script.
* `<name>_read_sources.tcl`: Lazy source file ingestion script.

---

### `fpga_design`

Generates an AMD/Xilinx Vivado Block Design (`.bd`) from IP instances, wires clock/reset networks, handles memory mappings, and synthesizes Out-of-Context (OOC) IP modules.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_design")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `top` | `string` | Yes | - | Wrapper entity/module name. |
| `part` | `string` | Yes | - | FPGA part number. |
| `ips` | `label_list` | No | `[]` | List of `fpga_ip_inst` targets included in the block design. |
| `deps` | `label_list` | No | `[]` | Extra source dependencies. |
| `pre_bd_hook` | `label` | No | `None` | TCL hook script sourced immediately after `create_bd_design` (e.g. PS7 / Zynq MPSoC automation). |
| `post_bd_hook` | `label` | No | `None` | TCL hook script sourced after cells and memory mappings are configured. |

#### Outputs

* `<name>_bd.tcl`: Master Block Design generation script.
* `<name>_bd_inst.tcl`: Cell instantiation script.
* `<name>_memory_mapping.tcl`: AXI address segment assignment script.
* `<name>_clock_domain.tcl`: Automated clock and reset wiring script.
* `<name>_wrappers/<wrapper_name>.vhd`: Expanded wrapper modules for OOC IP instances.

---

### `fpga_ip`

Declares an IP module definition shared across multiple instances.

`fpga_ip` encapsulates the RTL and constraints: it deliberately **does not** export `FpgaSourceInfo` directly, ensuring the IP cannot be accidentally swallowed into the top-level project unless instantiated through `fpga_ip_inst`.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_ip")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `entity_name` | `string` | Yes | - | Hardware module/entity name. |
| `generics` | `string_dict` | No | `{}` | Declared generic parameters and their default values. |
| `clock_port` | `string` | No | `"s_axi_aclk"` | Clock port name. |
| `reset_port` | `string` | No | `"s_axi_aresetn"`| Reset port name. |
| `reset_type` | `string` | No | `"active_low"` | Reset polarity: `"active_low"` or `"active_high"`. |
| `interfaces` | `string_dict` | No | `{}` | Memory-mapped interfaces and roles (`"master"` or `"slave"`). E.g. `{"s_axi": "slave", "M_AXI*": "master"}`. |
| `inst_tcl` | `label` | No | `None` | TCL script containing `vivado_inst_<entity>` and `vivado_memory_mapping_<entity>` procedures (used for inline instances). |
| `wrapper_template` | `label` | No | `None` | Hand-written wrapper HDL template used when synthesizing out-of-context. Placeholders: `{{WRAPPER_NAME}}`, `{{OOC_SYNTH_NAME}}`, and `{{<generic_name>}}`. |
| `srcs` / `deps` | `label_list` | No | `[]` | RTL source files and upstream libraries. |

---

### `fpga_ip_inst`

Instantiates an `fpga_ip` core within a design.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_ip_inst")
```

* **Inline Mode (`ooc = False`)**: Re-exports the IP's RTL sources so they are compiled directly as part of the project. The block design references the entity directly via `inst_tcl`.
* **Out-of-Context Mode (`ooc = True`)**: Withholds the RTL from the project sources. The design synthesizes the IP into a separate `.dcp` netlist under a collision-free name and generates a wrapper matching `wrapper_template`. Instances with identical entity and generics automatically share the same OOC synthesis.

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `ip` | `label` | Yes | - | The `fpga_ip` target being instantiated. |
| `instance_name` | `string` | No | `""` | Name of the instance inside the block design (defaults to target name). |
| `generics` | `string_dict` | No | `{}` | Parameter values overriding the IP defaults. |
| `ooc` | `bool` | No | `False` | Whether to synthesize Out-of-Context. |
| `clock_domain` | `label` | No | `None` | Target providing `FpgaClockDomainInfo` (e.g. `fpga_clock_domain`). |
| `memory_mapping` | `string_dict` | No | `{}` | Segment name to address assignments (e.g. `{"SEG_REG": "0x43DB0000"}`). |

---

### `fpga_clock_domain`

Declares clock and reset pins and polarities used to automate Block Design interconnects.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_clock_domain")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `clock_pin` | `string` | Yes | - | TCL pin expression (e.g. `"ps7_0/FCLK_CLK0"` or `"clk_wiz/clk_out1"`). |
| `reset_pin` | `string` | Yes | - | TCL pin expression (e.g. `"ps7_0/FCLK_RESET0_N"`). |
| `clock_frequency` | `string` | No | `""` | Informational frequency string (e.g. `"100MHz"`). |
| `reset_type` | `string` | No | `"active_low"` | Polarity: `"active_low"` or `"active_high"`. |

---

### `fpga_sources`

Aggregates HDL source files and constraints into a canonical `FpgaSourceInfo` provider.

```bzl
load("@gateweavers_rules_fpga//fpga:rules.bzl", "fpga_sources")
```

#### Attributes

| Attribute | Type | Mandatory | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | - | Target name. |
| `srcs` | `label_list` | No | `[]` | HDL files (`.vhd`, `.vhdl`, `.v`, `.sv`) or data files (`.mem`, `.dat`). |
| `constraints` | `label_list` | No | `[]` | Constraint files (`.xdc`, `.sdc`). |
| `deps` | `label_list` | No | `[]` | Upstream libraries (`fpga_sources` or `vhdl_library`). |
| `library_name` | `string` | No | `"work"` | VHDL compilation library name. |
| `vhdl_version` | `string` | No | `"2008"` | VHDL standard: `"93"`, `"2008"`, `"2019"`. |

---

### `fpga_project_gui` & `fpga_dcp_gui`

Executable rules that generate wrapper runners to launch Vivado GUI directly:

```bzl
# Open project in Vivado GUI
bazel run //my_design:my_flow.gui

# Open routed checkpoint in Vivado GUI
bazel run //my_design:my_flow_impl.gui
```

---
