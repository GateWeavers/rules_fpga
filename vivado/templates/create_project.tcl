# Vivado Project Creation Template
set PROJ_NAME {PROJECT_NAME}
set PART_NAME {PART_NAME}

create_project $PROJ_NAME {OUTPUT_DIR} -part $PART_NAME -force
set_property target_language VHDL [current_project]

# Add VHDL sources
{ADD_VHDL_SOURCES}

# Add Verilog sources
{ADD_VERILOG_SOURCES}

# Add Constraints
{ADD_CONSTRAINTS}

# Source BD script
{SOURCE_BD_SCRIPT}

set_property top {TOP_MODULE} [current_fileset]

