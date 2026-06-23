# Vivado Bitstream Template
set PROJ_NAME {PROJECT_NAME}

{OPEN_PROJECT_OR_OPEN_CHECKPOINT}

write_bitstream -force {BITSTREAM}
write_debug_probes -force {PROBES}
write_hw_platform -fixed -force -file {PLATFORM}
