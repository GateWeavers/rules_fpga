load("//fpga:providers.bzl", "FpgaIpInfo", "FpgaSourceInfo")

def _serialize_ip_config(ip_info):
    # Generics: sort keys alphabetically
    sorted_generics = sorted(ip_info.generics.items())
    generics_str = ",".join(["%s=%s" % (k, v) for k, v in sorted_generics])
    
    # Sources:
    vhdl_libs_str = []
    # Sort VHDL libraries by name
    sorted_libs = sorted(ip_info.sources.vhdl_libs, key = lambda x: x.library)
    for lib in sorted_libs:
        files = sorted([f.path for f in lib.sources.to_list()])
        vhdl_libs_str.append("%s:%s:%s" % (lib.library, lib.vhdl_version, ",".join(files)))
    
    verilog_files = sorted([f.path for f in ip_info.sources.verilog_srcs.to_list()])
    constraint_files = sorted([f.path for f in ip_info.sources.constraints.to_list()])
    
    sources_str = "VHDL:[%s]|Verilog:[%s]|Constrs:[%s]" % (
        ";".join(vhdl_libs_str),
        ",".join(verilog_files),
        ",".join(constraint_files),
    )
    
    return "Entity:%s|Generics:{%s}|Sources:{%s}" % (ip_info.entity_name, generics_str, sources_str)

def _mock_ooc_synthesis(ctx, group_hash, group_data):
    # Declare the output DCP file
    dcp_file = ctx.actions.declare_file("ooc_%s_%s.dcp" % (group_data["entity_name"], group_hash))
    tcl_file = ctx.actions.declare_file("ooc_%s_%s_synth.tcl" % (group_data["entity_name"], group_hash))
    
    # Generate mock TCL contents
    tcl_content = "# Mock TCL for OOC Synthesis of {}\n".format(group_data["entity_name"])
    tcl_content += "# Instances: {}\n".format(", ".join(group_data["instances"]))
    tcl_content += "synth_design -mode out_of_context -top {}\n".format(group_data["entity_name"])
    
    ctx.actions.write(
        output = tcl_file,
        content = tcl_content,
    )
    
    # Generate a mock output DCP
    ctx.actions.write(
        output = dcp_file,
        content = "Mock DCP checkpoint for entity {}\n".format(group_data["entity_name"]),
    )
    
    return dcp_file, tcl_file

def _deduplicate_ip_configs(ip_configs):
    ooc_groups = {}
    non_ooc_groups = {}
    
    for target in ip_configs:
        ip_info = target[FpgaIpInfo]
        serialized = _serialize_ip_config(ip_info)
        h = hash(serialized)
        hash_str = str(h if h >= 0 else -h)
        
        group_dict = ooc_groups if ip_info.ooc else non_ooc_groups
        
        if hash_str in group_dict:
            group_dict[hash_str]["instances"].append(ip_info.instance_name)
        else:
            group_dict[hash_str] = {
                "entity_name": ip_info.entity_name,
                "generics": ip_info.generics,
                "sources": ip_info.sources,
                "hash": hash_str,
                "instances": [ip_info.instance_name],
                "inst_tcl": getattr(ip_info, "inst_tcl", None),
                "memory_mapping": getattr(ip_info, "memory_mapping", None),
                "clock_domain": getattr(ip_info, "clock_domain", None),
            }
            
    return ooc_groups, non_ooc_groups

def _generate_ooc_synthesis_actions(ctx, ooc_groups):
    ooc_dcps = []
    ooc_tcls = []
    for h, group in ooc_groups.items():
        dcp, tcl = _mock_ooc_synthesis(ctx, h, group)
        ooc_dcps.append(dcp)
        ooc_tcls.append(tcl)
        group["output_dcp"] = dcp
    return ooc_dcps, ooc_tcls

def _generate_top_level_synthesis(ctx, ooc_groups, non_ooc_groups):
    top_tcl = ctx.actions.declare_file(ctx.label.name + "_top_synth.tcl")
    top_dcp = ctx.actions.declare_file(ctx.label.name + "_top.dcp")
    
    top_tcl_content = "# Top-level Synthesis script\n"
    top_tcl_content += "# Linking OOC modules:\n"
    for h, group in ooc_groups.items():
        top_tcl_content += "read_checkpoint {}\n".format(group["output_dcp"].path)
    top_tcl_content += "# Non-OOC modules directly processed:\n"
    for h, group in non_ooc_groups.items():
        top_tcl_content += "# Non-OOC Entity: {}, Instances: {}\n".format(group["entity_name"], ", ".join(group["instances"]))
    top_tcl_content += "synth_design -top {}\n".format(ctx.attr.top)
    
    ctx.actions.write(
        output = top_tcl,
        content = top_tcl_content,
    )
    
    ctx.actions.write(
        output = top_dcp,
        content = "Mock Top DCP for {}\n".format(ctx.attr.top),
    )
    
    return top_dcp, top_tcl

def _generate_bd_instantiation(ctx, non_ooc_groups):
    bd_inst_tcl = ctx.actions.declare_file(ctx.label.name + "_bd_inst.tcl")
    bd_tcl_content = "# Block Design Instantiation Script\n\n"
    bd_inputs = []
    
    # Source each unique instantiation script once
    bd_tcl_content += "# Source VHDL module instantiation procedures:\n"
    for h, group in non_ooc_groups.items():
        if group["inst_tcl"]:
            bd_tcl_content += "source {}\n".format(group["inst_tcl"].path)
            bd_inputs.append(group["inst_tcl"])
    bd_tcl_content += "\n# Instantiate cells:\n"
    
    # Call the instantiation procedure for each cell instance
    for h, group in non_ooc_groups.items():
        if not group["inst_tcl"]:
            continue
        for inst in group["instances"]:
            generics_list = []
            for k in sorted(group["generics"].keys()):
                v = group["generics"][k]
                generics_list.append("\"{}\" \"{}\"".format(k, v))
            generics_arg = "[list {}]".format(" ".join(generics_list)) if generics_list else ""
            bd_tcl_content += "vivado_inst_{} \"{}\" {}\n".format(group["entity_name"], inst, generics_arg)
            
    ctx.actions.write(
        output = bd_inst_tcl,
        content = bd_tcl_content,
    )
    
    return bd_inst_tcl, bd_inputs

def _generate_memory_mapping(ctx, non_ooc_groups):
    mem_map_tcl = ctx.actions.declare_file(ctx.label.name + "_memory_mapping.tcl")
    mem_tcl_content = "# Memory Mapping Script\n\n"
    mem_tcl_content += "# Source VHDL module procedures:\n"
    for h, group in non_ooc_groups.items():
        if group["inst_tcl"]:
            mem_tcl_content += "source {}\n".format(group["inst_tcl"].path)
    mem_tcl_content += "\n# Memory mapping configurations:\n"
    
    for h, group in non_ooc_groups.items():
        if not group["inst_tcl"] or not group["memory_mapping"]:
            continue
        segments = [seg.strip() for seg in group["memory_mapping"].split(",") if seg.strip()]
        if segments:
            segment_args = "[list {}]".format(" ".join(["\"{}\"".format(seg) for seg in segments]))
            for inst in group["instances"]:
                mem_tcl_content += "vivado_memory_mapping_{} \"{}\" {}\n".format(group["entity_name"], inst, segment_args)
                
    ctx.actions.write(
        output = mem_map_tcl,
        content = mem_tcl_content,
    )
    
    return mem_map_tcl

def _generate_clock_domain_connections(ctx, ooc_groups, non_ooc_groups):
    clk_dom_tcl = ctx.actions.declare_file(ctx.label.name + "_clock_domain.tcl")
    clk_tcl_content = "# Clock Domain Connection Script\n\n"
    clk_tcl_content += "source {}\n\n".format(ctx.file._clock_domain_tpl.path)
    
    clk_rst_groups = {}
    for group in ooc_groups.values() + non_ooc_groups.values():
        clk_info = group["clock_domain"]
        if not clk_info:
            continue
        key = (clk_info.clock_pin, clk_info.reset_pin, clk_info.reset_type)
        if key not in clk_rst_groups:
            clk_rst_groups[key] = []
        clk_rst_groups[key].extend(group["instances"])
        
    idx = 0
    for key in sorted(clk_rst_groups.keys()):
        instances = clk_rst_groups[key]
        clk_pin, rst_pin, rst_type = key
        active_low_val = 1 if rst_type == "active_low" else 0
        clk_tcl_content += "connect_axi_lite \\\n"
        clk_tcl_content += "    [list {}] \\\n".format(" ".join(["\"{}\"".format(inst) for inst in sorted(instances)]))
        clk_tcl_content += "    {} \\\n".format(clk_pin)
        clk_tcl_content += "    {} \\\n".format(rst_pin)
        clk_tcl_content += "    \"s_axi_aclk\" \\\n"
        clk_tcl_content += "    \"s_axi_aresetn\" \\\n"
        clk_tcl_content += "    \"axi_lite_interconnect_{}\" \\\n".format(idx)
        clk_tcl_content += "    \"proc_sys_reset_{}\" \\\n".format(idx)
        clk_tcl_content += "    \"S_AXI\" \\\n"
        clk_tcl_content += "    {}\n\n".format(active_low_val)
        idx += 1
        
    ctx.actions.write(
        output = clk_dom_tcl,
        content = clk_tcl_content,
    )
    
    return clk_dom_tcl

def _vivado_design_impl(ctx):
    # 1. Deduplicate
    ooc_groups, non_ooc_groups = _deduplicate_ip_configs(ctx.attr.ip_configs)
            
    # 2. OOC synthesis actions
    ooc_dcps, ooc_tcls = _generate_ooc_synthesis_actions(ctx, ooc_groups)
        
    # 3. Top-level linkage and synthesis
    top_dcp, top_tcl = _generate_top_level_synthesis(ctx, ooc_groups, non_ooc_groups)
    
    # 4. BD Instantiation
    bd_inst_tcl, bd_inputs = _generate_bd_instantiation(ctx, non_ooc_groups)
    
    # 5. Memory mapping
    mem_map_tcl = _generate_memory_mapping(ctx, non_ooc_groups)
    
    # 6. Clock domain connection
    clk_dom_tcl = _generate_clock_domain_connections(ctx, ooc_groups, non_ooc_groups)
    
    # Return all outputs in DefaultInfo
    all_outputs = [
        top_dcp,
        top_tcl,
        bd_inst_tcl,
        mem_map_tcl,
        clk_dom_tcl,
        ctx.file._clock_domain_tpl,
    ] + ooc_dcps + ooc_tcls + bd_inputs
    
    return [
        DefaultInfo(files = depset(all_outputs)),
    ]

vivado_design = rule(
    implementation = _vivado_design_impl,
    attrs = {
        "ip_configs": attr.label_list(providers = [FpgaIpInfo]),
        "top": attr.string(mandatory = True),
        "part": attr.string(mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "constraints": attr.label_list(allow_files = True),
        "_clock_domain_tpl": attr.label(allow_single_file = True, default = "//vivado/templates:clock_domain.tcl"),
    },
)
