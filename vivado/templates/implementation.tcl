# Vivado Implementation Template
set PROJ_NAME {PROJECT_NAME}

{OPEN_PROJECT_OR_OPEN_CHECKPOINT}

set_param general.maxThreads 8

opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file {REPORT_TIMING}
report_utilization -hierarchical -file {REPORT_UTILIZATION}
report_route_status -file {REPORT_ROUTE_STATUS}
write_checkpoint -force {OUTPUT_CHECKPOINT}
