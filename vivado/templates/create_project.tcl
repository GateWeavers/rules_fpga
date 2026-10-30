# Vivado Project Creation Template
set PROJ_NAME {PROJECT_NAME}
set PART_NAME {PART_NAME}

create_project $PROJ_NAME {OUTPUT_DIR} -part $PART_NAME -force
set_property target_language VHDL [current_project]

# Read sources into the project
{READ_SOURCES}

# Source BD script
{SOURCE_BD_SCRIPT}

set_property top {TOP_MODULE} [current_fileset]

