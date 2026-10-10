#!/usr/bin/env bash
#
# Build the PYNQ 4.0 SD card image for snickerdoodle black + piSmasher 4.1
# in PYNQ's sdbuild Docker container.
#
# Usage: ./build_image.sh            full build (several hours the first time)
#        ./build_image.sh boot       boot files only (BOOT.BIN, zImage, dtb, zocl)
#        ./build_image.sh shell      interactive shell in the build container

set -euo pipefail

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYNQ_DIR="${TOP}/PYNQ"
BOARDS_DIR="${TOP}/boards"
BOARD=Snickerdoodle_piSmasher
XILINX_TOOLS="${XILINX_TOOLS:-/opt/AMD_Design/2025.2}"
XILINXD_LICENSE_FILE="${XILINXD_LICENSE_FILE:-${HOME}/.Xilinx}"

command -v docker >/dev/null || { echo "docker is not installed" >&2; exit 1; }
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || {
    echo "qemu-arm binfmt handler missing: sudo apt install qemu-user-static binfmt-support" >&2
    exit 1
}

if ! docker image inspect pynqdock:latest >/dev/null 2>&1; then
    docker build \
        --build-arg USERNAME="$(whoami)" \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t pynqdock:latest "${PYNQ_DIR}/sdbuild"
fi

case "${1:-image}" in
    image) target="" ;;
    boot)  target="boot_${BOARD}" ;;
    shell) target="shell" ;;
    *) echo "unknown target: $1" >&2; exit 1 ;;
esac

make_cmd="cd /workspace/sdbuild && make BOARDS=${BOARD} BOARDDIR=${BOARDS_DIR} \
REBUILD_PYNQ_ROOTFS=1 ${target}"

docker_args=(
    --init --rm --network host --privileged
    -e XILINX_TOOLS -e XILINXD_LICENSE_FILE
    -v "${XILINX_TOOLS}:${XILINX_TOOLS}:ro"
    # The 2025.2 settings64.sh scripts source DocNav from the older tree.
    -v /opt/Xilinx/DocNav:/opt/Xilinx/DocNav:ro
    -v "${XILINXD_LICENSE_FILE}:${XILINXD_LICENSE_FILE}"
    -v "${PYNQ_DIR}:/workspace"
    -v "${BOARDS_DIR}:${BOARDS_DIR}"
)
export XILINX_TOOLS XILINXD_LICENSE_FILE

if [ "${target}" = "shell" ]; then
    docker run -it "${docker_args[@]}" pynqdock:latest /bin/bash
else
    docker run "${docker_args[@]}" pynqdock:latest bash -lc "${make_cmd}" \
        2>&1 | tee "${TOP}/build_$(date +%Y%m%d_%H%M%S).log"
fi
