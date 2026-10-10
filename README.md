# PYNQ 4.0 for snickerdoodle black + piSmasher

PYNQ 4.0 (Ubuntu 24.04 armhf, Python 3.12, Jupyter, XRT) on the krtkl
**snickerdoodle black** (Zynq-7020) with the **piSmasher 4.1** baseboard.
Upstream PYNQ 4 supports only 64-bit boards. This repository adds back the
Zynq-7000 path and the board definition.

Author: Mohammed Al-Badri

## What's here

| Path | Contents |
|---|---|
| `patches/pynq-snickerdoodle-zynq7000.patch` | All changes to [Xilinx/PYNQ](https://github.com/Xilinx/PYNQ), against commit `d90670c` |
| `boards/Snickerdoodle_piSmasher/` | Board spec, AMD EDF (Yocto) config, device tree, kernel and u-boot config, base overlay build, board fixes, self-test list |
| `build_image.sh` | Builds the SD image in PYNQ's Docker container |
| `edf_shell.sh` | Runs one bitbake command in the EDF environment, for debugging |
| `calc_overlay/` | Example overlay: a signed 32-bit `+ - * /` calculator in Verilog, its testbench, Vivado build and PYNQ driver |
| `BUILD_GUIDE.md` | The full build guide |

## Quick start

Requirements: Ubuntu 22.04 x86-64, Docker, `qemu-user-static`, Vivado + Vitis
2025.2 in `/opt/AMD_Design/2025.2`, and about 100 GB of free disk.

```bash
git clone <this repository> snickerdoodle-pynq4 && cd snickerdoodle-pynq4

# PYNQ at the pinned commit, plus the Zynq-7000 patch
git clone https://github.com/Xilinx/PYNQ.git
git -C PYNQ checkout -b snickerdoodle-zynq7000 d90670c69f7b71ea1a5d23aaa3e0ec713ff5fa9f
git -C PYNQ apply ../patches/pynq-snickerdoodle-zynq7000.patch
curl -L -o PYNQ/sdbuild/prebuilt/pynq_sdist.tar.gz \
  https://github.com/Xilinx/PYNQ/releases/download/v4.0.0/pynq-v4.0.0.tar.gz

# Base overlay (downloads krtkl's block design and constraints), then the image
source /opt/AMD_Design/2025.2/Vivado/settings64.sh
make -C boards/Snickerdoodle_piSmasher/base
./build_image.sh
```

The image is written to `PYNQ/sdbuild/output/Snickerdoodle_piSmasher-4.0.0.img`.
Write it to a microSD card, boot, and log in as `xilinx` / `xilinx`. Jupyter
runs on port 9090. See [BUILD_GUIDE.md](BUILD_GUIDE.md) for every step,
first-boot setup, Wi-Fi and troubleshooting.

## Status

Working: boot with the PL loaded by u-boot, Linux 6.12, PYNQ overlays,
MMIO and CMA buffers, XRT/zocl, eth0, Wi-Fi (TI WL1837), USB host,
`pynq-selftest`.

Not yet working:
- HDMI configuration over I2C (the TDA19971 receiver acknowledges only a few
  percent of transfers).
- eth1 is untested at 100/1000 Mbps.
- eth0 occasionally fails to attach its PHY at boot; a reboot clears it.

## Licence

The files in this repository are released under the BSD 3-Clause licence
(see `LICENSE`), the same licence as PYNQ. The base overlay's block design and
constraints are krtkl's and are **not** included: the makefile downloads them
from [krtkl/piSmasher-testing](https://github.com/krtkl/piSmasher-testing) at
a pinned commit.

## Credits

[krtkl](https://github.com/krtkl) for the snickerdoodle, the piSmasher and
their reference designs, and the AMD [PYNQ](https://github.com/Xilinx/PYNQ)
team.
