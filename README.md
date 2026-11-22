# Debian 13 (Trixie) for the Nintendo Switch

[![Build images](https://github.com/manu-romero-411/nx-debian/actions/workflows/build.yml/badge.svg)](https://github.com/manu-romero-411/nx-debian/actions/workflows/build.yml)
[![CI](https://github.com/manu-romero-411/nx-debian/actions/workflows/ci.yml/badge.svg)](https://github.com/manu-romero-411/nx-debian/actions/workflows/ci.yml)
[![Debian Version](https://img.shields.io/badge/Debian-13%20(Trixie)-crimson.svg)](https://www.debian.org/)
[![Kernel](https://img.shields.io/badge/Kernel-4.9.140--l4t-blue.svg)](https://developer.nvidia.com/embedded/linux-tegra)
[![Architecture](https://img.shields.io/badge/Arch-arm64-green.svg)](https://wiki.debian.org/Arm64Port)

Debian 13 for the Nintendo Switch, booted by Hekate, with Switchroot's L4T
kernel and NVIDIA's Tegra drivers. Two images: an XFCE desktop and Retrobox, a
console made of EmulationStation and RetroArch.

Everything in the images is installed by apt, from Debian and the L4T
repository. What nx-debian adds itself is in its own packages (`nxd-common`,
`nxd-xfce`, `nxd-retrobox`), so a console that is already installed is
updated with `nxd-update` instead of being flashed again.

---

<p align="center">
  <img src="screenshots/xfce4.png" alt="The XFCE desktop" width="850">
</p>

---

## The images

| Image | What it starts | User | Password |
| :--- | :--- | :--- | :--- |
| **`xfce`** | the XFCE desktop | `switch` | `switch` (a build at a terminal asks for the user name and the password) |
| **`retrobox`** | [Retrobox](https://github.com/RetroboxProject), as a console | `retrobox` | `retrobox` |

Both log the user in automatically, the hostname is `nintendo-switch`, the
user can `sudo` and `root` has no password. Change the password before the
console joins a network you do not trust: `ssh` is on in `retrobox` (to work
on it from a computer), and installed but off in `xfce` (`sudo systemctl
enable --now ssh` turns it on).

Common to both:

* **The hardware**: the L4T 4.9 kernel and boot files of Switchroot's
  `switch-bsp`, NVIDIA's Tegra X1 drivers and the Xorg server they are built
  for, Wi-Fi and Bluetooth, the integrated pad and the Joy-Cons, PulseAudio.
* **Performance profiles** (`nvpmodel`), fan modes and a battery charge limit,
  which the user at the console can change without a password: from the
  overlay in `retrobox`, from the panel indicator in `xfce`. The fan mode and the
  charge limit are kept across reboots.
* **Text consoles** in Terminus 8x16, and `fastfetch`.
* **Volume** of the speaker and the headphones kept between starts (Switchroot's sound profile no longer puts it back at 100%).
* **Locales** of the common languages of Europe generated (English, Spanish, Catalan, Basque, Galician, French, German, Italian, Polish, Russian, Ukrainian, Greek).
* **A quiet boot** (no kernel or systemd text on the screen), and a reboot that
  goes back to Hekate's menu.
* **Installers for Hekate**: the system is an ext4 image in parts that fit
  FAT32 (`l4t.00`, `l4t.01`), which Hekate's partition manager flashes; the
  first boot grows the file system to the size of the partition.

**`xfce`** adds, through `nxd-xfce`:

* `switch-rotate`, which turns the screen and the touchscreen together, at
  once, and keeps the choice for the next login (button in the top panel).
* A top panel with the applications menu, windows, rotation, volume, battery,
  the SoC temperature and the fan (`switch-sensors`), the performance indicator,
  Wi-Fi (nm-applet), Bluetooth (Blueman), the clock and the session actions; a bottom launcher bar,
  hidden until the pointer gets there (terminal, files, Firefox ESR, finder).
* The Adwaita theme, Firefox ESR and Thunar as default applications, and
  Onboard, the on-screen keyboard, in the menu.

**`retrobox`** adds, through `nxd-retrobox`:

* EmulationStation as a console: no way to quit to a desktop, the Nintendo
  button layout (the east button confirms), the Switch Lite's pad with Home as
  the hotkey, larger text for the small screen.
* RetroArch and a base set of cores already installed (more from the Content
  Downloader), with the theme, bezels and shaders Retrobox would download at
  its first start.
* ROMs, BIOS and saves in the SD card's FAT32 partition (`/sdcard/retrobox`),
  the one Hekate, Android and a PC see too.
* The volume buttons change the volume and show it at the top of the screen;
  the power button suspends (a long press turns the console off).
* The picom compositor (vsync, and the overlay over a running game).

---

## Hardware

The images are built for every model the L4T kernel of `switch-bsp` supports
(Erista and Mariko: the first Switch, the V2, the Lite and the OLED); a
Mariko needs a modchip to run Hekate. They have been tested on a **Switch
Lite**; reports from other models are welcome.

---

## Installation (Hekate)

1. **Partition the SD card.** In Hekate: *Tools* → *Partition SD Card*, and
   give *Linux (EXT4)* at least 6 GB (the image is 5 GiB; 16 GB or more leaves
   room for your files). Then *Next Step* and *Start*.
2. **Copy the installer.** Download the installer of the image you want
   (`switch-debian-13-trixie-xfce-installer.zip` or
   `switch-debian-13-trixie-retrobox-installer.zip`) from the
   [Releases](https://github.com/manu-romero-411/nx-debian/releases), check it
   against `SHA256SUMS`, and unzip it at the root of the SD card's FAT32
   partition: it has `bootloader/` and `switchroot/` (`switchroot/install/`
   holds `l4t.00` and `l4t.01`).
3. **Flash it.** In Hekate: *Tools* → *Partition SD Card* → *Flash Linux*.
4. **Boot it.** From Hekate's *More Configs*, pick **Debian 13 Trixie**.

Hekate is not in the installers: install or update it as you usually do.

---

## Updating

```bash
sudo nxd-update                       # Debian, L4T, nx-debian and Retrobox (releases)
sudo nxd-update --allow-prereleases   # ...including pre-releases
```

It upgrades Debian and the L4T packages, then nx-debian's packages and the
Retrobox ones from their GitHub releases, and cleans up. Files you changed
under `/etc` are kept. See [docs/packages.md](docs/packages.md).

---

## Troubleshooting

### A broken Joy-Con (`joycon_serdev: Received pkt has wrong magic`)

Messages like these, over and over, come from a Joy-Con on a rail that sends
corrupt data (a damaged controller, ribbon cable or rail pins):

```text
joycon_serdev serial0-0: Received pkt has wrong magic
joycon_serdev serial0-0: Received pkt is malformed
```

Take that Joy-Con off. To keep it attached and ignore the rails instead, set
`jc_rail_disable=1` in `bootloader/ini/debian.ini` on the SD card (it is `0` by
default).

---

## Building from source

Everything goes through `nxd` (`./nxd --help`). The build is done by Debian's
`mmdebstrap`, so any host works, even one that is not arm64 (qemu) or not
Debian: `nxd container` runs the same steps in a Debian trixie container.

```bash
./nxd variants                                              # what can be built
sudo ./nxd container build --variant retrobox --clean       # one image
sudo ./nxd container build                                  # every image
```

The Retrobox packages come from their GitHub releases, only from the ones that
are not pre-releases unless `--prereleases` is given (the newest of each,
which is what you want while Retrobox is still gaining features). The
installers end up in `dist/`, with the package list of each one and a
`SHA256SUMS`.

[docs/rootfs.md](docs/rootfs.md) documents the steps (`nxd rootfs`,
`nxd inspect`, `nxd image`), the variants and the tests;
[docs/packages.md](docs/packages.md) nx-debian's packages and `nxd-update`;
[docs/decisions.md](docs/decisions.md) why the images run the 4.9 kernel of
`switch-bsp`; [docs/legacy-inventory.md](docs/legacy-inventory.md) what became
of the old build script.

### Continuous integration

* `ci.yml`: the linters and the tests, on every push.
* `packages.yml`: nx-debian's packages, on every push to `main`, published as
  the `nxd-latest` pre-release.
* `build.yml`: the images, on an arm64 runner, by hand (*Actions* → *Build
  images* → *Run workflow*) or for a `v*` tag; it can publish them as a release,
  with the packages of that version.

---

## Credits

* **Debian**: [Software in the Public Interest, Inc.](https://www.debian.org/)
* **Switchroot**: the L4T kernel, device trees and boot files (`switch-bsp`).
* **CTCaer and contributors**: Hekate and Nyx.
* **NVIDIA**: Linux for Tegra and its drivers.
* **Retrobox**: [RetroboxProject](https://github.com/RetroboxProject).
