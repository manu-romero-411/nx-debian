# Switchroot Debian 13 (Trixie) for Nintendo Switch

[![Build images](https://github.com/manu-romero-411/nx-debian/actions/workflows/build.yml/badge.svg)](https://github.com/manu-romero-411/nx-debian/actions/workflows/build.yml)
[![CI](https://github.com/manu-romero-411/nx-debian/actions/workflows/ci.yml/badge.svg)](https://github.com/manu-romero-411/nx-debian/actions/workflows/ci.yml)
[![Debian Version](https://img.shields.io/badge/Debian-13%20(Trixie)-crimson.svg)](https://www.debian.org/)
[![Kernel](https://img.shields.io/badge/Kernel-4.9.140--l4t-blue.svg)](https://developer.nvidia.com/embedded/linux-tegra)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20%2F%20aarch64-green.svg)](https://wiki.debian.org/Arm64Port)

**Debian 13 (Trixie)** for the Nintendo Switch (V1, V2, Lite and OLED), on the
Switchroot L4T kernel and NVIDIA's Tegra X1 driver, packaged as installers for
Hekate. Two images are built: an XFCE desktop and a Retrobox console image.

> **Status.** The images are built by `nxd` (see [Building](#building-from-source)),
> which installs everything with apt from Debian and the L4T repository. Some
> desktop features of the old hand-made image (screen rotation, the NVPModel
> indicator, the panel layout) are not ported yet; they are listed under
> [Not ported yet](#not-ported-yet) and in
> [docs/legacy-inventory.md](docs/legacy-inventory.md).

---

<p align="center">
  <img src="screenshots/xfce4.png" alt="Switchroot Debian 13 (Trixie) XFCE4 Desktop" width="850">
</p>

---

## Branches

| Branch | What it is |
| :--- | :--- |
| `main` | The L4T images (4.9 kernel, NVIDIA driver). What the releases are built from. |
| `mainline` | Experimental: an extra `mainline` variant with a mainline kernel and Mesa (nouveau, NVK later). Rootfs only, it does not boot yet. See `docs/mainline.md` on that branch. |

---

## What the images have

* **Debian 13 (Trixie)**, every package installed by apt from Debian and from
  the [L4T repository](https://theofficialgman.github.io/l4t-debs/), so `apt`
  keeps updating both after installation.
* **Tegra X1 hardware acceleration**: NVIDIA's L4T 32.3.1 driver, with the
  Xorg 1.20.13 server it needs pinned to the L4T repository (Debian's Xorg 21
  has another ABI).
* **Kernel 4.9.140-l4t** with its modules and boot files, from Switchroot's
  `switch-bsp` package. Debian 13's systemd still boots on it with cgroup v1
  (the image sets `SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1` to skip its 30 s wait).
  Why this kernel and when that changes: [docs/decisions.md](docs/decisions.md).
* **Switch hardware** through the Switchroot packages: dock handling, touch
  screen rules, Joy-Cons (`joycond`), ALSA UCM2 audio profiles, and the
  Wi-Fi/Bluetooth firmware of the BCM4356.
* **Desktop basics**: NetworkManager, BlueZ, PulseAudio, zram swap, `sudo`,
  and `ssh` installed but off.
* **Hekate installer**: an ext4 image split into `l4t.00`, `l4t.01` (FAT32-safe)
  for Hekate's Nyx partition manager, with its own boot entry, icon and logo.

### Not ported yet

From the old image, still to be done in `nxd` (details and the lines of the
old script in [docs/legacy-inventory.md](docs/legacy-inventory.md)):

* `switch-rotate`: live rotation of the screen and the touch input.
* The NVPModel indicator: CPU/GPU/EMC profiles, fan profiles and the battery
  charge limit (sources kept in `tools/nvpmodel_indicator`). `nvpmodel` itself
  is installed by `switch-bsp`.
* The XFCE layout: top panel with the applets, bottom dock, appearance,
  Onboard in the autostart.
* The Xorg configuration for the Tegra screen, and the suspend/resume hook.
* The BlueZ 5.8x and Joy-Con serdev kernel patches in `patches/kernel/`: they
  are not applied, as the kernel is the one of `switch-bsp`.

---

## Hardware Support

| Model | Supported | 8 GB RAM mod | Notes |
| :--- | :---: | :---: | :--- |
| **Nintendo Switch V1 (Erista)** | Yes | Yes | RCM exploit or modchip |
| **Nintendo Switch V2 (Mariko)** | Yes | Yes | Modchip required |
| **Nintendo Switch Lite** | Yes | Yes | Modchip required |
| **Nintendo Switch OLED** | Yes | Yes | Modchip required |

---

## Quick Installation Guide (Hekate Nyx)

The installers do not include Hekate: the SD card must already have a recent
one.

### 1. Partitioning the MicroSD Card
1. Boot your Nintendo Switch into **Hekate**.
2. Tap **Tools** -> **Partition SD Card**.
3. Move the **Linux** slider to allocate space for Debian (minimum: **8 GB**, recommended: **16 GB** or more).
4. Tap **Next Step** and proceed to format the SD card.

### 2. Copying Installer Files
1. Download the installer of the variant you want (`switch-debian-13-trixie-xfce-installer.zip` or `switch-debian-13-trixie-retrobox-installer.zip`) from the [Releases](https://github.com/manu-romero-411/nx-debian/releases) page, and check it against `SHA256SUMS`.
2. Extract the archive directly onto the root of your MicroSD card's FAT32 partition.
   - The directory tree should contain `bootloader/ini/debian.ini`, `switchroot/debian/`, and `switchroot/install/l4t.00`, `l4t.01`.

### 3. Flashing & First Boot
1. Insert the MicroSD card into your Nintendo Switch and power on into Hekate.
2. Navigate to **Tools** -> **Partition SD Card** -> **Flash Linux**.
3. Hekate flashes `l4t.00` and `l4t.01` into the Linux partition.
4. Once completed, return to the Hekate main menu, tap **More Configs**, and select **Debian 13 Trixie**.
5. On the first boot, the filesystem is grown to fill the partition.

---

## Variants and default credentials

| Variant | Session | User | Password |
| :--- | :--- | :--- | :--- |
| **`xfce`** | XFCE4 desktop | `switch` | `switch` (a build at a terminal asks for the user name and the password) |
| **`retrobox`** | Openbox starting [Retrobox](https://github.com/RetroboxProject), with RetroArch and its base cores | `retrobox` | `retrobox` |

Both log the user in automatically, and the hostname is `nintendo-switch`. In
`xfce`, the gamepad can act as a mouse (`switch-joystick-mouse`). In
`retrobox`, Retrobox keeps its data in `/retrobox` and the gamepad is never a
mouse. The account can `sudo`, `root` has no password, and `ssh` is installed
but disabled (`sudo systemctl enable --now ssh` turns it on): change the
password before you do.

---

## Controls & Usage

* **Wi-Fi**: the NetworkManager applet in the panel, or `nmtui` in a terminal.
* **Bluetooth**: Blueman in the panel, to pair controllers and audio devices.
* **Performance profiles**: until the indicator is ported, `nvpmodel` from a
  terminal (`sudo nvpmodel -q` shows the current one).

---

## Troubleshooting & FAQs

### Joy-Con Rail Errors / Boot Loop (`joycon_serdev: received packet has wrong magic` or `malformed`)
If your Switch repeats messages such as:
```text
joycon_serdev serial 0-0: Received pkt has wrong magic
joycon_serdev serial 0-0: Received pkt is malformed
joycon_serdev serial 0-0: Packet length too large; ignoring
```
This is caused by an attached Joy-Con that is physically broken, has damaged internal electronics/ribbon cable, or dirty/damaged rail pins (`serial0-0` is the Left rail, `serial1-0` is the Right rail). The kernel detects the controller presence via the physical rail pin, but receives corrupt serial packets from the faulty hardware.

**Solutions:**
1. **Physical Fix (Fastest)**: Simply **slide off and detach the broken Joy-Con** from the console. If you use a Pro Controller or Bluetooth controllers, you can keep the rail empty and Debian will boot normally.
2. **Optional Software Setting (to keep the broken Joy-Con slotted in)**: On your SD card, edit `bootloader/ini/debian.ini` and change `jc_rail_disable=0` to `jc_rail_disable=1` in the `[Debian 13 Trixie]` section:
   ```ini
   [Debian 13 Trixie]
   l4t=1
   boot_prefixes=/switchroot/debian/
   id=SWR-DEB
   r2p_action=self
   fbconsole=0
   jc_rail_disable=1
   ```
   *(The rails are enabled by default. `jc_rail_disable=1` is only for consoles with faulty rail hardware.)*

---

## Building from Source

Everything goes through `nxd` (`./nxd --help`). The build is done by Debian's
`mmdebstrap`, so any host works, including a non-arm64 one (qemu) or one that
is not Debian: `nxd container` runs the same steps in a Debian trixie
container.

```bash
./nxd variants                       # what can be built
sudo ./nxd build --variant retrobox  # rootfs + installer, native
sudo ./nxd container build           # the same, every variant, in a container
```

The Retrobox packages come from their GitHub releases, and only from those
that are not pre-releases; `--prereleases` (for example
`sudo ./nxd container build --variant retrobox --prereleases`) takes the newest
of each, which is what you want while Retrobox is still gaining features.

Hekate is left out of the installers; `--with-hekate` puts the latest release
in them, and the installer is then named `...-installer-hekate.zip`.

The installers end up in `dist/`: `switch-debian-13-trixie-<variant>-installer.zip`,
the package list and the rootfs report of each one, and a `SHA256SUMS`. Unzip
an installer on the root of the SD card and flash it from Hekate as described
above.

The steps can also be run apart: `nxd spike` (does Debian plus the L4T
repository resolve), `nxd rootfs`, `nxd inspect` (what is in the rootfs and
why) and `nxd image`. [docs/rootfs.md](docs/rootfs.md) documents them, the
variants, the release packages and the tests;
[docs/decisions.md](docs/decisions.md) records why the image runs the 4.9
kernel of `switch-bsp`.

### Continuous integration

`.github/workflows/ci.yml` runs the linters and the tests on every push.
`.github/workflows/build.yml` builds the images on a native arm64 runner when
it is started by hand (Actions → *Build images* → *Run workflow*) or when a
`v*` tag is pushed, and can publish them as a GitHub release; its
*prereleases* input builds with the pre-releases of the Retrobox packages and
marks the release it publishes as a pre-release, and its *hekate* input puts
Hekate in the installers.

---

## License & Credits

* **Debian GNU/Linux**: [Software in the Public Interest, Inc.](https://www.debian.org/)
* **Switchroot Team**: For foundational device tree trees, bootloaders, and L4T patches.
* **CTCaer & contributors**: For Hekate, Nyx, and partition management tools.
* **theofficialgman**: For the L4T package repository the images are installed from.
* **NVIDIA**: For Linux for Tegra (L4T) board support packages and drivers.
