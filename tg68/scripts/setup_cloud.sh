#!/bin/bash
# Tool setup for a Claude Code cloud environment (Ubuntu 24.04).
#
# Paste this into the environment's "Setup script" field (claude.ai/code ->
# environment settings), or run it once in a fresh session. It installs the
# exact tool versions this project was built and verified with, so cloud
# builds reproduce the released bitstreams bit for bit. It runs well under
# the five-minute limit, so the environment gets cached.
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    verilator fpga-trellis binutils-m68k-linux-gnu gcc-m68k-linux-gnu python3-pip ghdl >/dev/null
# yosys and nextpnr as WebAssembly builds (pinned), plus amitools/vamos for
# testing Amiga executables (sw/maprom)
pip install --break-system-packages -q \
    "yowasp-yosys==0.70.0.0.post1259" \
    "yowasp-nextpnr-ecp5==0.11.1.0.post826" \
    amitools machine68k
echo "tools ready: $(verilator --version | head -1)"
