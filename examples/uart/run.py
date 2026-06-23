#!/usr/bin/env python3

import os
import sys
import json
from pathlib import Path
from vunit import VUnit

config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
if not config_path:
    print("Error: VUNIT_BAZEL_CONFIG not set.")
    sys.exit(1)
    
if not os.path.exists(config_path):
    config_path = os.path.join(os.getcwd(), config_path)

with open(config_path, 'r') as f:
    config = json.load(f)

sim_type = config['simulator_type']
binary_path = os.path.abspath(config['binary_path'])
binary_dir = os.path.dirname(binary_path)

if sim_type == "ghdl":
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    os.environ["VUNIT_GHDL_PATH"] = binary_dir
    os.environ["GHDL_PREFIX"] = os.path.join(binary_dir, "..", "lib", "ghdl")
elif sim_type == "nvc":
    os.environ["VUNIT_SIMULATOR"] = "nvc"
    os.environ["VUNIT_NVC_PATH"] = binary_dir

args = [os.path.expandvars(a) for a in sys.argv[1:]]

if "XML_OUTPUT_FILE" in os.environ and "--xunit-xml" not in args:
    args.extend(["--xunit-xml", os.environ["XML_OUTPUT_FILE"]])

# Initialize VUnit
vu = VUnit.from_argv(args)
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

SRC_PATH = Path(__file__).parent / "src"
vu.add_library("uart_lib").add_source_files(SRC_PATH / "*.vhd")
vu.add_library("tb_uart_lib").add_source_files(SRC_PATH / "test" / "*.vhd")

vu.main()
