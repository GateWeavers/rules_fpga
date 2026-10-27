"""fpga_ip, fpga_ip_inst, the fpga_ip_config macro and fpga_design.

fpga_ip       declares a module: entity, sources, generic names (+ defaults),
              clock/reset ports, wired interfaces, inst_tcl, wrapper_template.
              It NEVER exports FpgaSourceInfo: its RTL is only reachable
              through FpgaIpInfo.sources.
fpga_ip_inst  one instance: generic values, instance_name, clock domain,
              memory map and `ooc`.
                ooc = False -> re-exports the IP's FpgaSourceInfo (RTL goes into
                               the project; the BD references the entity directly).
                ooc = True  -> export the ooc synthesis netlist, stub and wrappers (WIP).

"""

load("//fpga:common.bzl", "SOURCE_ATTRS", "TOOLCHAIN_ATTRS")
load("//fpga:flags.bzl", "fpga_toolchain_transition")
load(
    "//fpga:providers.bzl",
    "FpgaClockDomainInfo",
    "FpgaDesignInfo",
    "FpgaIpInfo",
    "FpgaIpInstInfo",
)
load("//fpga:source.bzl", "collect_sources", "source_files")

_WRAPPER_EXTENSIONS = ["vhd", "vhdl", "v", "sv"]

TOOLCHAIN_TYPE = Label("//fpga:toolchain_type")

def _fpga_clock_domain_impl(ctx):
    return [
        DefaultInfo(files = depset()),
        FpgaClockDomainInfo(
            clock_pin = ctx.attr.clock_pin,
            clock_frequency = ctx.attr.clock_frequency,
            reset_pin = ctx.attr.reset_pin,
            reset_type = ctx.attr.reset_type,
        ),
    ]

fpga_clock_domain = rule(
    implementation = _fpga_clock_domain_impl,
    attrs = {
        "clock_pin": attr.string(mandatory = True),
        "clock_frequency": attr.string(default = ""),
        "reset_pin": attr.string(mandatory = True),
        "reset_type": attr.string(default = "active_low"),
    },
)

# ---------------------------------------------------------------------------
# Naming helpers
# ---------------------------------------------------------------------------

def _check_identifier(ctx, what, name):
    ok = name != "" and name[0:1].isalpha() and "__" not in name and not name.endswith("_")
    if ok:
        for c in name.elems():
            if not (c.isalnum() or c == "_"):
                ok = False
                break
    if not ok:
        fail("%s: %s '%s' is not a valid HDL identifier" % (ctx.label, what, name))

def _hdl_name(base, tag, key):
    # Stable across unrelated edits, so an unchanged instance keeps its name
    # (and its cached OOC synthesis). hash() is only 32 bits: collisions are
    # detected by _claim_name.
    return "%s_%s_%08x" % (base, tag, hash(key) & 0xffffffff)

def _claim_name(ctx, claimed, name, key):
    prev = claimed.get(name)
    if prev != None and prev != key:
        fail("%s: generated HDL name '%s' collides for keys '%s' and '%s'" % (
            ctx.label,
            name,
            prev,
            key,
        ))
    claimed[name] = key

# ---------------------------------------------------------------------------
# fpga_ip
# ---------------------------------------------------------------------------

def _fpga_ip_impl(ctx):
    _check_identifier(ctx, "entity_name", ctx.attr.entity_name)
    for g in list(ctx.attr.generics.keys()) :
        _check_identifier(ctx, "generic name", g)

    src = collect_sources(
        ctx,
        srcs = ctx.files.srcs,
        constraints = ctx.files.constraints,
        deps = ctx.attr.deps,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
    )
    extra = [f for f in [ctx.file.inst_tcl, ctx.file.wrapper_template] if f]

    return [
        DefaultInfo(files = depset(extra, transitive = [source_files(src)])),
        FpgaIpInfo(
            label = "//%s:%s" % (ctx.label.package, ctx.label.name),
            entity_name = ctx.attr.entity_name,
            sources = src,
            generics = ctx.attr.generics,
            inst_tcl = ctx.file.inst_tcl,
            wrapper_template = ctx.file.wrapper_template,
            clock_port = ctx.attr.clock_port,
            reset_port = ctx.attr.reset_port,
            reset_type = ctx.attr.reset_type,
            interfaces = ctx.attr.interfaces,
        ),
    ]

fpga_ip = rule(
    implementation = _fpga_ip_impl,
    doc = "Declares an IP. Shared by all fpga_ip_inst targets that reference it.",
    attrs = dict(
        SOURCE_ATTRS,
        entity_name = attr.string(mandatory = True),
        generics = attr.string_dict(doc = "Declared generics with default values."),
        clock_port = attr.string(default = "s_axi_aclk"),
        reset_port = attr.string(default = "s_axi_aresetn"),
        reset_type = attr.string(default = "active_low", values = ["active_low", "active_high"]),
        interfaces = attr.string_dict(doc = "Wired interfaces: name -> master|slave. A master may be a glob (e.g. M_AXI*)."),
        inst_tcl = attr.label(
            allow_single_file = [".tcl"],
            doc = "BD instantiation procedure, used by inline (ooc = False) instances.",
        ),
        wrapper_template = attr.label(
            allow_single_file = [".%s" % e for e in _WRAPPER_EXTENSIONS],
            doc = "Hand-written wrapper, used by OOC instances. Must not also be listed in srcs.",
        ),
    ),
)

# ---------------------------------------------------------------------------
# fpga_ip_inst
# ---------------------------------------------------------------------------

def _fpga_ip_inst_impl(ctx):
    ip = ctx.attr.ip[FpgaIpInfo]
    instance_name = ctx.attr.instance_name or ctx.label.name
    _check_identifier(ctx, "instance_name", instance_name)

    clock_domain = None
    if ctx.attr.clock_domain:
        clock_domain = ctx.attr.clock_domain[FpgaClockDomainInfo]

    inst = FpgaIpInstInfo(
        ip = ip,
        instance_name = instance_name,
        ooc = ctx.attr.ooc,
        generics = ctx.attr.generics,
        clock_domain = clock_domain,
        memory_mapping = ctx.attr.memory_mapping,
    )

    if ctx.attr.ooc:
        fail("WIP : this feature is not yet supported")
        return [DefaultInfo(), inst]

    return [DefaultInfo(files = source_files(ip.sources)), inst, ip.sources]

fpga_ip_inst = rule(
    implementation = _fpga_ip_inst_impl,
    doc = "One instance of an fpga_ip.",
    attrs = {
        "ip": attr.label(mandatory = True, providers = [FpgaIpInfo]),
        "instance_name": attr.string(doc = "Defaults to the target name."),
        "generics": attr.string_dict(doc = "Generic values; unknown names fail."),
        "ooc": attr.bool(default = False),
        "clock_domain": attr.label(providers = [FpgaClockDomainInfo]),
        "memory_mapping": attr.string_dict(doc = "Segment name -> address, passed to vivado_memory_mapping_<entity>."),
    },
)

def fpga_ip_config(
        name,
        ooc = False,
        instance_name = None,
        generics = None,
        memory_mapping = None,
        clock_domain = None,
        visibility = None,
        tags = None,
        **ip_kwargs):
    """helper macro: one fpga_ip (name_ip) plus one fpga_ip_inst (name).

    Every key of `generics` is declared as required on the IP. For defaults or
    several instances of one IP, use fpga_ip and fpga_ip_inst directly.
    """
    generics = generics or {}
    fpga_ip(
        name = name + "_ip",
        required_generics = sorted(generics.keys()),
        visibility = visibility,
        tags = tags,
        **ip_kwargs
    )
    fpga_ip_inst(
        name = name,
        ip = ":" + name + "_ip",
        instance_name = instance_name or name,
        ooc = ooc,
        generics = generics,
        memory_mapping = memory_mapping or {},
        clock_domain = clock_domain,
        visibility = visibility,
        tags = tags,
    )

# ---------------------------------------------------------------------------
# fpga_design
# ---------------------------------------------------------------------------

def _group_instances(ctx, insts):
    """Groups instances that can share one synthesis (equal synth_key).

    Group fields are what is shared; per-instance data (clock domain, memory
    mapping, wrapper name, ports) stays on each instance.
    Returns (ooc_groups, inline_groups): dict[synth_key, struct].
    """
    seen = {}
    members = {}
    for inst in insts:
        if inst.instance_name in seen:
            fail("%s: duplicate IP instance_name '%s'" % (ctx.label, inst.instance_name))
        seen[inst.instance_name] = True
        members.setdefault(inst.synth_key, []).append(inst)

    claimed = {}
    ooc_groups = {}
    inline_groups = {}
    for key, infos in members.items():
        head = infos[0]
        ooc_synth_name = None
        if head.ooc:
            ooc_synth_name = _hdl_name(head.ip.entity_name, "ooc", key)
            _claim_name(ctx, claimed, ooc_synth_name, key)

        instances = []
        for i in infos:
            wrapper_name = None
            if i.ooc:
                wrapper_name = _hdl_name(i.instance_name, "wrap", i.inst_key)
                _claim_name(ctx, claimed, wrapper_name, i.inst_key)
            instances.append(struct(
                instance_name = i.instance_name,
                inst_key = i.inst_key,
                wrapper_name = wrapper_name,
                generics = i.generics,
                clock_domain = i.clock_domain,
                memory_mapping = i.memory_mapping,
                inst_tcl = i.ip.inst_tcl,
                clock_port = i.ip.clock_port,
                reset_port = i.ip.reset_port,
                reset_type = i.ip.reset_type,
                interfaces = i.ip.interfaces,
            ))

        group = struct(
            synth_key = key,
            entity_name = head.ip.entity_name,
            ip = head.ip,
            sources = head.ip.sources,
            generics = head.generics,
            ooc = head.ooc,
            ooc_synth_name = ooc_synth_name,
            instances = instances,
        )
        if head.ooc:
            ooc_groups[key] = group
        else:
            inline_groups[key] = group
    return ooc_groups, inline_groups

def _expand_wrappers(ctx, ooc_groups):
    """One wrapper file per OOC instance, expanded from the IP's template."""
    files = []
    for group in ooc_groups.values():
        template = group.ip.wrapper_template
        for inst in group.instances:
            out = ctx.actions.declare_file("%s_wrappers/%s.%s" % (
                ctx.label.name,
                inst.wrapper_name,
                template.extension,
            ))
            substitutions = {"{{%s}}" % k: v for k, v in inst.generics.items()}
            substitutions["{{WRAPPER_NAME}}"] = inst.wrapper_name
            substitutions["{{OOC_SYNTH_NAME}}"] = group.ooc_synth_name
            ctx.actions.expand_template(
                template = template,
                output = out,
                substitutions = substitutions,
            )
            files.append(out)
    return files

def _fpga_design_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE].fpga_info

    insts = [t[FpgaIpInstInfo] for t in ctx.attr.ips]
    ooc_groups, non_ooc_groups = _group_instances(ctx, insts)
    wrapper_files = _expand_wrappers(ctx, ooc_groups)

    # Inline instances contribute their RTL; OOC instances contribute only the
    # generated wrappers (the RTL is consumed by the OOC synthesis action).
    inline_targets = [t for t in ctx.attr.ips if not t[FpgaIpInstInfo].ooc]
    source_info = collect_sources(
        ctx,
        srcs = wrapper_files,
        deps = ctx.attr.deps + inline_targets,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
    )

    design_data = struct(
        ooc_groups = ooc_groups,
        non_ooc_groups = non_ooc_groups,
        top = ctx.attr.top,
        part = ctx.attr.part,
        pre_bd_hook = ctx.file.pre_bd_hook,
        post_bd_hook = ctx.file.post_bd_hook,
    )
    res = toolchain.generate_design(ctx, toolchain, design_data)

    return [
        DefaultInfo(files = res.generated_files),
        FpgaDesignInfo(
            design_name = ctx.label.name,
            top_entity = ctx.attr.top,
            design_script = res.design_script,
            generated_files = res.generated_files,
            ooc_ips = [
                struct(
                    synth_key = g.synth_key,
                    ooc_synth_name = g.ooc_synth_name,
                    entity_name = g.entity_name,
                    generics = g.generics,
                    dcp = res.ooc_dcps[g.synth_key],
                    instances = g.instances,
                )
                for g in ooc_groups.values()
            ],
            non_ooc_ips = [
                struct(
                    synth_key = g.synth_key,
                    entity_name = g.entity_name,
                    generics = g.generics,
                    instances = g.instances,
                )
                for g in non_ooc_groups.values()
            ],
            sources = source_info,
        ),
        source_info,
    ]

fpga_design = rule(
    implementation = _fpga_design_impl,
    doc = "Generates the block design from IP instances.",
    attrs = dict(
        deps = SOURCE_ATTRS["deps"],
        ips = attr.label_list(
            providers = [FpgaIpInstInfo],
            doc = "fpga_ip_inst targets. OOC instances are synthesized separately and " +
                  "reached through generated wrappers; inline instances add the IP RTL.",
        ),
        library_name = SOURCE_ATTRS["library_name"],
        vhdl_version = SOURCE_ATTRS["vhdl_version"],
        top = attr.string(mandatory = True),
        part = attr.string(mandatory = True),
        pre_bd_hook = attr.label(allow_single_file = [".tcl"]),
        post_bd_hook = attr.label(allow_single_file = [".tcl"]),
        **TOOLCHAIN_ATTRS
    ),
    cfg = fpga_toolchain_transition,
    toolchains = [TOOLCHAIN_TYPE],
)