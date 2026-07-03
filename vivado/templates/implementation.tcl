# Vivado Implementation Template
set PROJ_NAME {PROJECT_NAME}

{OPEN_PROJECT_OR_OPEN_CHECKPOINT}

set_param general.maxThreads {MAX_THREADS}
{PRE_IMPL_TCL}
opt_design {OPT_OPTIONS}
place_design {PLACE_OPTIONS}
phys_opt_design {PHYS_OPT_OPTIONS}
route_design {ROUTE_OPTIONS}
{POST_IMPL_TCL}

report_timing_summary -file {REPORT_TIMING}
report_utilization -hierarchical -file {REPORT_UTILIZATION}
report_route_status -file {REPORT_ROUTE_STATUS}
write_checkpoint -force {OUTPUT_CHECKPOINT}
