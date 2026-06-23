#!/usr/bin/env python3

"""
VHDL UART
---------

A more realistic test bench of an UART to show VUnit VHDL usage on a
typical module.
"""

from sim.vunit_bazel_helper import get_vunit_from_bazel,add_lib_from_bazel
from pathlib import Path
import sys

vu = get_vunit_from_bazel()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

add_lib_from_bazel(vu)

vu.main()