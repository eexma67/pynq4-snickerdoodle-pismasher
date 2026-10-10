# PYNQ 4.0 for snickerdoodle black + piSmasher 4.1: build guide

**Author:** Mohammed Al-Badri
**Date:** 2026-10-09
**Result:** `Snickerdoodle_piSmasher-4.0.0.img`, a PynqLinux 4.0.0 (Ubuntu 24.04 "noble", armhf) SD-card image for the krtkl snickerdoodle black (Zynq-7020, `xc7z020clg400-3`) on a krtkl piSmasher 4.1 baseboard.

This guide rebuilds the image from scratch. Every version, patch and file that the working build used is listed below.

---

## 1. What you are building

| Component | Version / source |
|---|---|
| PYNQ sdbuild | `github.com/Xilinx/PYNQ`, commit `d90670c69f7b71ea1a5d23aaa3e0ec713ff5fa9f`, plus `patches/pynq-snickerdoodle-zynq7000.patch` |
| PYNQ Python package | Official v4.0.0 sdist, `pynq-v4.0.0.tar.gz` (MD5 `4076aafc5720c2aebabec47fc8938eaf`) |
| Boot flow | AMD EDF (Yocto) manifest `amd-edf-rel-v25.11.1`, custom machine `snickerdoodle-pismasher-pynq` generated from the base overlay's XSA |
| Kernel | `linux-xlnx` 6.12.40 (`v2025.2`), booted as a `zImage` |
| AMD tools | Vivado/Vitis **2025.2**, installed at `/opt/AMD_Design/2025.2` |
| Root filesystem | Ubuntu 24.04 noble, armhf, built under QEMU in PYNQ's Docker container |
| Base overlay | krtkl `piSmasher-testing/piSmasher_4.1/hdmi-pass-through` block design (Vivado 2018.2), converted to Vivado 2025.2 |

Upstream PYNQ 4.0 dropped Zynq-7000 (32-bit ARM) support. The patch adds it back for this board: zImage boot, a u-boot `boot.scr` that loads `base.bit`, armhf rootfs config, XRT/zocl without the AI Engine, and armhf Python wheel build fixes. See section 11.

---

## 2. Host requirements

The working build used:

- **OS:** Ubuntu 22.04.5 LTS, x86-64. 22 cores and 62 GB RAM were used; 16 GB RAM is a practical minimum.
- **Disk:** about **55 GB** for a finished build. That breaks down as EDF cache 27 GB, rootfs stages 18 GB, output 8.6 GB and ccache 0.7 GB. Leave **≥ 100 GB free**.
- **Docker** (29.x was used). Your user must be in the `docker` group.
- **QEMU user-mode emulation** for armhf:
  ```bash
  sudo apt install qemu-user-static binfmt-support
  ls /proc/sys/fs/binfmt_misc/qemu-arm      # must exist
  ```
- **Vivado + Vitis 2025.2** in `/opt/AMD_Design/2025.2`, with a license in `~/.Xilinx`. The sdbuild checks `vivado -version` and `vitis -version` against 2025.2.
- **`/opt/Xilinx/DocNav`** must exist. The 2025.2 `settings64.sh` scripts source DocNav from the older tree, so `build_image.sh` mounts it into the container.
- **Internet access** during the build (Ubuntu mirrors, PyPI, GitHub, AMD EDF manifests).
- Optional: an SD card ≥ 8 GB and a USB-UART for the serial console.

> **Note:** a long Yocto kernel compile once hung this host (Intel GPU and Wi-Fi driver errors under full CPU load). If that happens, limit parallelism (`BB_NUMBER_THREADS` / `PARALLEL_MAKE` in the EDF `local.conf`) and re-run. The build caches its progress, so a rerun resumes where it stopped.

---

## 3. Directory layout

Everything lives under one working directory, here `~/Downloads/snickerdoodle-pynq4`:

```
snickerdoodle-pynq4/
├── BUILD_GUIDE.md                    this document
├── build_image.sh                    top-level build wrapper (runs sdbuild in Docker)
├── edf_shell.sh                      helper: run a bitbake command in the EDF environment
├── patches/
│   └── pynq-snickerdoodle-zynq7000.patch   all changes to PYNQ (apply to d90670c)
├── PYNQ/                             Xilinx/PYNQ clone (patched)
├── boards/Snickerdoodle_piSmasher/   board definition (see section 9)
├── calc_overlay/                     optional hardware calculator overlay (section 10)
└── krtkl/                            krtkl reference repos and schematics (not needed to build)
```

`build_image.sh`, `edf_shell.sh`, `patches/`, `boards/Snickerdoodle_piSmasher/`, `calc_overlay/` and this guide make up the project's git repository. `.gitignore` keeps everything else out: the PYNQ clone, krtkl's repos, caches, logs and build output.

---

## 4. Get the sources

### 4.1 PYNQ at the exact commit, plus the board patch

```bash
git clone https://github.com/eexma67/pynq4-snickerdoodle-pismasher.git ~/Downloads/snickerdoodle-pynq4
cd ~/Downloads/snickerdoodle-pynq4
git clone https://github.com/Xilinx/PYNQ.git
cd PYNQ
git checkout -b snickerdoodle-zynq7000 d90670c69f7b71ea1a5d23aaa3e0ec713ff5fa9f
git apply --check ../patches/pynq-snickerdoodle-zynq7000.patch   # must print nothing
git apply ../patches/pynq-snickerdoodle-zynq7000.patch
git add -A && git commit -m "Zynq-7000 (snickerdoodle/piSmasher) support"
cd ..
```

The patch was verified to apply cleanly to a fresh checkout of `d90670c`.

### 4.2 The PYNQ v4.0.0 source distribution

The rootfs build installs PYNQ from a prebuilt sdist rather than building it:

```bash
curl -L -o PYNQ/sdbuild/prebuilt/pynq_sdist.tar.gz \
  https://github.com/Xilinx/PYNQ/releases/download/v4.0.0/pynq-v4.0.0.tar.gz
md5sum PYNQ/sdbuild/prebuilt/pynq_sdist.tar.gz
# 4076aafc5720c2aebabec47fc8938eaf
```

### 4.3 Board files

`boards/Snickerdoodle_piSmasher/`, `build_image.sh` and `edf_shell.sh` come with the repository cloned in 4.1. They are described file by file in section 9.

### 4.4 krtkl references (optional)

These are only needed to re-derive the board files. They were used at these commits:

| Repo | Commit |
|---|---|
| `github.com/krtkl/piSmasher-testing` | `a33972a` (source of the base block design and `constraints.xdc`) |
| `github.com/krtkl/piSmasher-software` | `b67f63c` (HDMI/audio config tools) |
| `github.com/krtkl/snickerdoodle-dts` | `b2a7c7f` (device-tree reference) |
| `github.com/krtkl/snickerdoodle-board-files` | `5af4690` |
| `github.com/krtkl/snickerdoodle-build-scripts` | `1b37585` |

---

## 5. Build the base overlay (Vivado)

The base overlay is krtkl's piSmasher 4.1 `hdmi-pass-through` design: PS7, two `gmii_to_rgmii` Ethernet bridges, HDMI pass-through and audio. The EDF flow generates the board's boot machine and device tree from its XSA, so it has to be built **before** the image.

```bash
cd ~/Downloads/snickerdoodle-pynq4/boards/Snickerdoodle_piSmasher/base
source /opt/AMD_Design/2025.2/Vivado/settings64.sh
make            # vivado -mode batch -source build_base.tcl
```

Outputs: `base.bit`, `base.hwh`, `base.xsa`.

What the build does:
1. The makefile downloads krtkl's two files from `github.com/krtkl/piSmasher-testing` at commit `a33972af` and checks their MD5 sums. They are not redistributed in this repository. `make distclean` removes them.
2. `src/convert_bd.py` turns krtkl's Vivado 2018.2 block-design script (`src/krtkl_hdmi_pass_through_2018.2.tcl`, from the `hdmi-pass-through` project's `hw_handoff/base_bd.tcl`) into `src/base_bd.tcl`. It resolves every IP to the newest version in the running Vivado and removes the ILA debug cores.
3. `build_base.tcl` creates the project for `xc7z020clg400-3` and builds the block design. It sets FCLK2 to 100 MHz, because krtkl's 150 MHz request lands on 153.8 MHz, which PYNQ cannot reproduce. It uses **global synthesis** (`synth_checkpoint_mode None`), because out-of-context IP runs crashed Vivado 2025.2 with SIGBUS on this host.
4. `src/piSmasher_4.1.xdc` is krtkl's `piSmasher_4.1/constraints.xdc`, unchanged.

One critical warning is expected and harmless: `piSmasher_4.1.xdc:191` (`CLOCK_DEDICATED_ROUTE` on `AC_BCLK_IBUF`).

---

## 6. Build the SD image

```bash
cd ~/Downloads/snickerdoodle-pynq4
./build_image.sh            # full image
```

`build_image.sh` does the following:
1. Checks for Docker and the `qemu-arm` binfmt handler.
2. Builds the `pynqdock:latest` image from `PYNQ/sdbuild/Dockerfile` on first use, with your UID/GID.
3. Runs, inside the container:
   ```
   make BOARDS=Snickerdoodle_piSmasher BOARDDIR=<abs path>/boards REBUILD_PYNQ_ROOTFS=1
   ```
   It mounts Vivado/Vitis (read-only), DocNav, `~/.Xilinx`, `PYNQ/` (as `/workspace`) and `boards/`.
4. Logs everything to `build_<date>_<time>.log` in the working directory.

`REBUILD_PYNQ_ROOTFS=1` is required, because there is no prebuilt armhf PYNQ rootfs.

**Build stages:**

| Stage | What happens |
|---|---|
| Boot (EDF/bitbake) | Generates machine `snickerdoodle-pismasher-pynq` from `base/base.xsa`, then builds FSBL, u-boot, `BOOT.BIN`, `zImage`, `system.dtb`, kernel modules and `zocl.ko` |
| Rootfs stage 1–2 | Ubuntu noble armhf via multistrap and QEMU, Python venv, Jupyter. Wheels without armhf binaries are compiled from source under emulation (slow) |
| Rootfs stage 3 | XRT built from source **without the AI Engine** (Zynq-7000 has none), then PYNQ, x11, resizefs |
| Stage 4 (board) | Packages `xrt pynq board_fixes ethernet selftest` from the board spec |
| Image | FAT32 boot partition + ext4 root partition |

**Time:** most of a day the first time, mostly QEMU-emulated wheel and XRT builds. Later runs reuse the EDF sstate, ccache and pip caches and are much faster.

**Output:**
```
PYNQ/sdbuild/output/Snickerdoodle_piSmasher-4.0.0.img      (~6.5 GB)
PYNQ/sdbuild/output/boot/Snickerdoodle_piSmasher/          BOOT.BIN, zImage, system.dtb, boot.scr, base.bit, modules.tgz, zocl.ko
```

**Rebuild only the boot files** (after changing `board.dtsi`, `kernel.cfg`, u-boot config or `base.xsa`):
```bash
./build_image.sh boot
```

**Debugging:**
```bash
./build_image.sh shell                          # interactive shell in the build container
./edf_shell.sh 'bitbake -e virtual/kernel | grep ^S='   # one bitbake command in the EDF env
```

---

## 7. Write the SD card

```bash
lsblk                                   # identify the SD card, e.g. /dev/sdX; double-check!
sudo dd if=PYNQ/sdbuild/output/Snickerdoodle_piSmasher-4.0.0.img of=/dev/sdX \
        bs=4M status=progress conv=fsync
sync
```

`dd` overwrites the target completely, so make sure `/dev/sdX` is the SD card. The root partition grows to fill the card on first boot (`resizefs`).

Boot partition contents: `BOOT.BIN`, `boot.scr`, `base.bit`, `zImage`, `system.dtb`.

At power-on, u-boot runs `boot.scr`. It loads `base.bit` into the PL **before** Linux starts, because the Ethernet MACs reach their PHYs through PL logic (`gmii_to_rgmii`). Then it boots `zImage` with `system.dtb`.

---

## 8. First boot

| Item | Value |
|---|---|
| Serial console | UART0 (MIO 50/51), `ttyPS0`, **115200 8N1**, autologin as `xilinx` |
| Login | `xilinx` / `xilinx` (sudo password also `xilinx`; change it) |
| eth0 | DHCP, plus a fixed alias **192.168.2.99/24** (`/etc/network/interfaces.d/eth0`) |
| Jupyter | `http://<board-ip>:9090` |
| SSH | Host keys are generated on first boot; `ssh xilinx@<board-ip>` |
| MAC addresses | Stable per board, derived from `/etc/machine-id` (`pynq-eth-mac.service`) |

A simple direct link: plug the board's eth0 into a USB-Ethernet adapter and set that connection to **"Shared to other computers"** in NetworkManager. The PC becomes `10.42.0.1` and gives the board a 10.42.0.x address with internet access.

**Run the self-test:**
```bash
sudo pynq-selftest                     # all tests, including hardware tests
sudo pynq-selftest --no-peripherals    # software-only
sudo pynq-selftest --list
```
The checks for this board are listed in `boards/Snickerdoodle_piSmasher/selftest.json`. They cover resize, networking, CMA (256 MB of 1 GB), Jupyter, XRT, systemd, image identity, users, notebooks, serial autologin, merged /usr, sysfs GPIO, pybind11, overlay + DMA, USB webcam and internet.

### 8.1 Wi-Fi (TI WL1837 on SDIO1)

The driver (`wl18xx`) and firmware are in the image. Configure a network once:

```bash
sudo sh -c 'umask 077; { echo "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev"; \
  echo "update_config=1"; echo "country=GB"; \
  wpa_passphrase "<SSID>" "<password>" | grep -v "^[[:space:]]*#psk="; } \
  > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf'

sudo tee /etc/network/interfaces.d/wlan0 >/dev/null <<'EOF'
allow-hotplug wlan0
auto wlan0
iface wlan0 inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
    metric 100
EOF

sudo ifup wlan0
ip -br addr show wlan0
```

`metric 100` gives Wi-Fi its own default route without displacing eth0's. The key is stored hashed. Wi-Fi uses PS pins (MIO 10–15), so it keeps working when you load a different overlay.

### 8.2 HDMI transceiver enables

krtkl's documentation uses GPIO 958/959. On this kernel the Zynq GPIO base is 512, so the same pins (MIO 52 = `HDMI_TX_EN`, MIO 53 = `HDMI_RX_NRST`) are **564/565**:

```bash
for g in 564 565; do
  echo $g | sudo tee /sys/class/gpio/export
  echo out | sudo tee /sys/class/gpio/gpio$g/direction
  echo 1 | sudo tee /sys/class/gpio/gpio$g/value
done
```

The "HDMI 5V" and "HDMI 1V8" LEDs light when these are on. See section 13 for the open HDMI I2C issue.

---

## 9. Board definition files (what to keep)

| File | Purpose |
|---|---|
| `Snickerdoodle_piSmasher.spec` | `ARCH=arm`, `BITSTREAM=base/base.bit`, `FPGA_MANAGER=1`, stage-4 packages `xrt pynq board_fixes ethernet selftest` |
| `edf.env` | EDF manifest `amd-edf-rel-v25.11.1`, `EDF_MODE=custom`, machine `snickerdoodle-pismasher-pynq`, `BSP_XSA_PATH=base/base.xsa` |
| `edf_bsp/board.dtsi` | Board device-tree nodes appended to the XSA-generated tree (ported from krtkl's PYNQ 2.5 `snickerdoodle-black-pismasher.dts`): UART0 console, 256 MB CMA, WL1837 Wi-Fi on SDIO1 (enable MIO 9), peripheral power MIO 20, ULPI PHY + USB2514 hub (reset MIO 16), I2C1 at 100 kHz, SPI1 platform MCU, QSPI flash, both GEMs via `gmii_to_rgmii` with PHY resets on MIO 19/17 |
| `edf_bsp/kernel.cfg` | Kernel options: DRM (zocl), FPGA manager/regions/overlays, CMA, MACB + GMII2RGMII + Marvell PHY, ChipIdea USB + ULPI, onboard USB hub, WL18xx + Bluetooth, Cadence SPI, QSPI, compressed firmware loading (zstd) |
| `edf_bsp/u-boot/no-ethernet.cfg` | Disables `CONFIG_ZYNQ_GEM` in u-boot. Probing the Marvell 88E1510 from u-boot left eth0's PHY in a state Linux could not soft-reset |
| `base/` | Base overlay sources and build (section 5) |
| `packages/board_fixes/` | Patches pynqmetadata (accept the `gmii_to_rgmii` MDIO nets; Zynq-7000 FCLK frequency parameter names), `pynq.lib.Wifi` (`allow-hotplug` only), first-boot SSH host keys and machine-id, stable MAC addresses + larger RX ring, Jupyter start timeout 300 s |
| `selftest.json` | Self-test manifest (section 8) |
| `notebooks/getting_started.ipynb` | Board notebook |

---

## 10. Optional: hardware calculator overlay

`calc_overlay/` contains an example overlay: the base design plus a signed 32-bit `+ − × ÷` calculator (`src/calc_axi.v`) on `M_AXI_GP0`. It runs at 100 MHz (FCLK2) at address `0x43C00000` and uses about 1.5% of the LUTs. The Ethernet bridges stay in the design, so loading it keeps eth0's hardware path in place.

The build reuses the base overlay's block design and constraints, so build the base overlay first (section 5), or at least run `make -C boards/Snickerdoodle_piSmasher/base src/base_bd.tcl src/piSmasher_4.1.xdc`.

```bash
cd ~/Downloads/snickerdoodle-pynq4/calc_overlay
source /opt/AMD_Design/2025.2/Vivado/settings64.sh

# simulate (2400 self-checking tests)
cd sim && xvlog ../src/calc_axi.v tb_calc_axi.v && xelab tb_calc_axi -s tb && xsim tb -R && cd ..

# build calc.bit / calc.hwh (about 1 h)
vivado -mode batch -source build_calc.tcl -notrace

# install on the board
ssh xilinx@<board-ip> mkdir -p jupyter_notebooks/calculator
scp calc.bit calc.hwh driver/calc.py driver/calculator.ipynb \
    xilinx@<board-ip>:jupyter_notebooks/calculator/
```

On the board:
```python
from calc import CalcOverlay
calc = CalcOverlay("calc.bit").calc
calc.add(7, 5)          # 12
calc.mul(-6, 7)         # -42 (full 64-bit product)
calc.div(-7, 2)         # quotient -3, remainder -1
```

Register map: `0x00` CTRL (W bit0 start; R busy/done/div_by_zero/overflow), `0x04` OPCODE (0 add, 1 sub, 2 mul, 3 div), `0x08` A, `0x0C` B, `0x10` RES_LO, `0x14` RES_HI. In hardware, 8000 random operations matched Python with no errors.

---

## 11. What the PYNQ patch changes

`patches/pynq-snickerdoodle-zynq7000.patch`, against PYNQ `d90670c`:

| File | Change |
|---|---|
| `sdbuild/Makefile` | `KERNEL_arm := zImage`; kernel name per architecture; passes `BITSTREAM` to the boot build and `KERNEL_NAME` to the image script |
| `sdbuild/scripts/build_edf_boot.sh` | Deploys `zImage` on arm; copies `system.dtb` through symlinks and skips u-boot's dtb; writes a Zynq-7000 `boot.scr` that loads `base.bit` (`fpga loadb`) and then `bootz`; copies `base.bit` to the boot files |
| `sdbuild/scripts/make_sdimage.sh` | Accepts `zImage` and `boot.scr` instead of `Image` + extlinux; copies `base.bit` to the boot partition |
| `sdbuild/boot/meta-pynq/recipes-bsp/device-tree/device-tree.bbappend` | Zynq DT fragments (`pynq_uio_zynq.dtsi`, zocl poll/intc); applies `board.dtsi` and the `pynq_board` name on `linux-gnueabi` (arm) as well as `linux` |
| `sdbuild/boot/meta-pynq/recipes-xrt/zocl/zocl_git.bb` + `files/0001-zocl-support-32-bit-Zynq-7000.patch` | Builds zocl against its AIE stubs on Zynq and fixes error-code masks that truncate on 32-bit |
| `sdbuild/packages/xrtlib/qemu.sh`, `pre.sh`, `xrt-edge-without-aie.patch` | Builds XRT on `armv7l` without the AI Engine runtime (`get_aie_freq`/`set_aie_freq` guarded, 32-bit `size_t` fixes) |
| `sdbuild/packages/python_packages_noble/qemu.sh` | On armv7l: hides Ubuntu's `pybind11.pc` so meson uses the isolated pybind11; uses Make instead of Ninja (Ninja can deadlock under qemu-user); links pyzmq against system libzmq; caches wheels in `/ccache/pip`; `cython<3.2` build constraint (Cython 3.3 rejects pyzmq 27.1) |
| `sdbuild/packages/selftest/tests/python/cma.py` | Minimum CMA size configurable per board (`min_kb`), since this board has 1 GB DDR |
| `sdbuild/ubuntu/noble/arm/` (new) | armhf rootfs config, multistrap config and `/etc` patches (copied from the aarch64 set) |

---

## 12. Build problems you may hit, and their fixes

These are already fixed by the patch and board files above. They're listed so you can recognise them if they come back.

| Symptom | Cause / fix |
|---|---|
| `metadata-generation-failed` / `failed-wheel-build-for-install` in rootfs stage 2 | armhf wheels compiled from source: pybind11 `.pc` clash, Ninja hangs under QEMU, Cython 3.3 vs pyzmq. Fixed in `python_packages_noble/qemu.sh` |
| `'class ZYNQ::shim' has no member named 'get_aie_freq'` | XRT edge build assumes AIE. Fixed by `xrt-edge-without-aie.patch` |
| Build tries to make `boards/ZCU104/base/base.bit` | Missing `BOARDS=Snickerdoodle_piSmasher`. `build_image.sh` passes it |
| `REBUILD_PYNQ_SDIST not set and PYNQ_SDIST file ... does not exist` | Download the v4.0.0 sdist (section 4.2) |
| Overlay fails to load: `WrongPolarityConnection` on `gmii_to_rgmii` MDIO | pynqmetadata patch in `board_fixes` (turns it into a "Skipping net" warning) |
| `phy_poll_reset failed` / eth0 dead after boot | u-boot probing the PHY. Fixed by `no-ethernet.cfg`, but see section 13 |
| Vivado SIGBUS at start of synthesis | Concurrent OOC IP runs. Use global synthesis (`synth_checkpoint_mode None`) |

---

## 13. Known issues (as of 2026-10-09)

1. **HDMI configuration over I2C does not work yet.** krtkl's `hdmi-config` fails at its first write to the TDA19971 receiver (`writing page 13 (-1)`).
   - At register level, the Zynq I2C1 controller on MIO 24/25 does run transfers.
   - With the HDMI chips enabled, the receiver at 0x48 acknowledges only about 4% of attempts. The rest get NACK or hang, and slowing the clock to 25 kHz doesn't help.
   - The Linux `cdns-i2c` driver times out (`-110`) on every transfer after the first boot.
   - The piSmasher I2C goes through PCA9306 level shifters U5 (I2C1, HDMI) and U34 (I2C2, USB hub). Scope decodes so far were inconclusive (channel or probe placement unconfirmed). Next step: clean scope captures on P3-17/19 and U5 pins 5/6.
2. **eth0 sometimes fails to attach its PHY at boot** (`Could not attach PHY (-110)`, `phy_poll_reset failed`) even with `no-ethernet.cfg`. A reboot usually clears it. Wi-Fi is a reliable fallback.
3. **eth1 is not configured by the image** (only eth0 is in `interfaces.d`). In testing it linked at only 10 Mbps (PHY "downshift ... check cabling") and could receive but not transmit. Retest with a known-good cable at 100/1000 Mbps.
4. The USB2514 hub's SMBus configuration is not used. The hub runs on its strap defaults (`usb251xb ... Failed to connect hub` in the log is expected).

---

## 14. Quick reference

```bash
# from scratch, after section 4
cd ~/Downloads/snickerdoodle-pynq4/boards/Snickerdoodle_piSmasher/base
source /opt/AMD_Design/2025.2/Vivado/settings64.sh && make
cd ~/Downloads/snickerdoodle-pynq4
./build_image.sh
sudo dd if=PYNQ/sdbuild/output/Snickerdoodle_piSmasher-4.0.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```
