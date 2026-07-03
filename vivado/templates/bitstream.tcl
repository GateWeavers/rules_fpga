# Vivado Bitstream Template
set PROJ_NAME {PROJECT_NAME}

{OPEN_PROJECT_OR_OPEN_CHECKPOINT}

{PRE_BIT_TCL}
eval "write_bitstream -force {BIT_OPTIONS} {BITSTREAM}"
{POST_BIT_TCL}
catch {write_debug_probes -force {PROBES}}
if {![file exists {PROBES}]} {
    set fp [open {PROBES} w]
    close $fp
}
write_hw_platform -fixed -force -file {PLATFORM}
