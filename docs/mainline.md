# The mainline variant

An image with a mainline kernel and the open graphics stack (nouveau and tegra
in Mesa), next to the L4T variants. It is developed in the `mainline` branch;
`main` stays on L4T. Why it is a separate variant, and when it
replaces them, is in [decisions.md](decisions.md).

```sh
./nxd variants --all                         # it is listed as experimental
sudo ./nxd rootfs --variant mainline         # the rootfs builds
sudo ./nxd image --variant mainline          # refused: no boot path yet
```

## How it differs from the L4T variants

| | L4T variants | mainline |
| :--- | :--- | :--- |
| Kernel | 4.9.140-l4t (`switch-bsp`) | mainline (Debian's for now) |
| GPU, GL | NVIDIA 32.3.1, Xorg 1.20 pinned | Mesa: nouveau renders, tegra displays |
| Vulkan | NVIDIA 32.3.1 | none yet (NVK, phase 4) |
| X server | Xorg 1.20 from L4T | Debian's, modesetting |
| Repositories | Debian + L4T (+ bookworm compat) | Debian with non-free-firmware |
| Clocks, fan | nvpmodel profiles | kernel (devfreq, thermal) |
| cgroup | v1 (`SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE`) | v2 |

`NXD_L4T=0` in the variant turns off the L4T key, source and pins, and the
compat suite; `NXD_COMPONENTS` gives the Debian components.

## Phases

### 0. The rootfs (done)

`nxd rootfs --variant mainline` builds Debian with Debian's kernel, Mesa and
the XFCE desktop, without L4T. `nxd image` refuses it.

To check on the first build (`nxd inspect --variant mainline`): which firmware
package ships `nvidia/tegra210/*`, `nvidia/gm20b/*` and `brcm/brcmfmac4356*`,
and whether `40-switch-firmware.sh` still needs to link anything.

### 1. Boot on Erista

- Choose the kernel tree: the Switch support is not upstream (device tree,
  panel, Joy-Con rails). Candidates are the trees of L4T-Community and of
  Aaron Kling. The kernel is built as a .deb and replaces `kernel-debian.list`.
- The boot path through Hekate: keep Switchroot's ATF and u-boot (`bl31.bin`,
  `bl33.bin`) and give u-boot a `boot.scr` that loads `Image`, the DTB and the
  initramfs. `nxd image` gets a second boot path for variants without L4T.
- The initramfs must find the root by label (`SWR-DEB`), as fstab does.

Done when: the console on the panel, USB, the SD card as root, a login.

### 2. Hardware

| Part | Likely mainline driver | Status |
| :--- | :--- | :--- |
| Display panel (DSI) | tegra-drm + panel driver | to check |
| Touch screen | stmfts (?) | to check |
| Wi-Fi, Bluetooth (BCM4356) | brcmfmac, hci_bcm | to check |
| Audio (ALC5639) | tegra210 AHUB, rt5640 | to check |
| Battery, charger | max17042, bq24190 | to check |
| Joy-Con rails | serdev (not upstream) | to check |
| Dock (USB-C, DP alt mode) | | to check |
| Fan, thermal | pwm-fan, soctherm | to check |
| Suspend | | to check |

What is lost for good: nvpmodel and the indicator (the kernel drives the
clocks), the L4T multimedia packages (hardware video decoding: NVDEC on T210
is not in mainline yet) and the kernel patches of `patches/kernel/` (they are
for 4.9).

### 3. GL and the session

Mesa's nouveau and tegra drivers: kmscube, glmark2-es2, then the XFCE session
on Xorg's modesetting driver, then a Wayland session.

### 4. Vulkan (NVK)

Debian's Mesa does not enumerate the Tegra GPU in NVK. This needs Mesa built
from upstream with the Tegra work (Mesa work item 14105) and the kernel fixes
it lists. `NVK_I_WANT_A_BROKEN_VULKAN_DRIVER=1` enumerates GPUs NVK does not
support officially.

### 5. Mariko

Tegra210B01 (V2, Lite, OLED) is waiting for its patches to land upstream (PMC,
clocks, device tree). Until then the variant is Erista only.
