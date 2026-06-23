# Vivado Synthesis Template
set PROJ_NAME {PROJECT_NAME}
set PART_NAME {PART_NAME}
set TOP_MODULE {TOP_MODULE}

{OPEN_PROJECT_OR_IN_MEMORY}
{READ_SOURCES_IF_MEMORY}

set_param general.maxThreads 8
eval "synth_design -top $TOP_MODULE -part $PART_NAME {SYNTH_ARGS}"

report_timing_summary -file {REPORT_TIMING}
report_utilization -file {REPORT_UTILIZATION}
write_checkpoint -force {OUTPUT_CHECKPOINT}
