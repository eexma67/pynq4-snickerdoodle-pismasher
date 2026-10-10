#!/usr/bin/env bash
# Run a command in the sdbuild container with the EDF/bitbake environment set up.
# Usage: ./edf_shell.sh '<command>'
TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XILINX_TOOLS=/opt/AMD_Design/2025.2
exec docker run --rm --network host --privileged \
    -e XILINX_TOOLS \
    -e PYNQ_BOARDNAME=Snickerdoodle_piSmasher -e FPGA_MANAGER=1 \
    -e PYNQ_BOARD_DTSI="${TOP}/boards/Snickerdoodle_piSmasher/edf_bsp/board.dtsi" \
    -e PYNQ_BOARD_KCFG="${TOP}/boards/Snickerdoodle_piSmasher/edf_bsp/kernel.cfg" \
    -e PYNQ_BOARD_UBOOT_DIR="${TOP}/boards/Snickerdoodle_piSmasher/edf_bsp/u-boot" \
    -e BB_ENV_PASSTHROUGH_ADDITIONS="PYNQ_BOARDNAME FPGA_MANAGER PYNQ_BOARD_DTSI PYNQ_BOARD_KCFG PYNQ_BOARD_UBOOT_DIR" \
    -v "${XILINX_TOOLS}:${XILINX_TOOLS}:ro" -v /opt/Xilinx/DocNav:/opt/Xilinx/DocNav:ro \
    -v "${TOP}/PYNQ:/workspace" -v "${TOP}/boards:${TOP}/boards" \
    pynqdock:latest bash -lc "cd /workspace/sdbuild/edf-cache/pynq-edf && set +u && source edf-init-build-env >/dev/null && export MACHINE=snickerdoodle-pismasher-pynq && $1"
