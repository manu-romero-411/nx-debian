# nxd: viability spike and rootfs skeleton

`nxd` is the entry point of the new, apt-based build. The legacy `build.sh`
keeps working untouched; nothing here replaces it yet.

## 1. The spike: does Debian + the L4T repository resolve?

```
./nxd spike --contents
```

No root needed. It uses a private apt state (nothing is installed, nothing on
the host is touched) and simulates `apt-get install` of a whole variant for
three scenarios:

| scenario            | meaning                                                      |
|---------------------|--------------------------------------------------------------|
| `debian`            | Debian trixie alone                                          |
| `l4t-<comp>-nopin`  | Debian + the L4T component, no pins                          |
| `l4t-<comp>-pin`    | the same, with `config/apt/l4t.pref` (Xorg 1.20 from L4T)    |

`<comp>` is each entry of `--components` (default `jammy noble`; the L4T repo
uses the Ubuntu release as component). The result is `spike-report.md`:

* packages that do not exist in Debian (candidates to drop or to package),
* unmet dependencies per scenario (a `jammy` component usually fails on
  `t64` library names, `noble` should not),
* the candidate source and priority of the key packages: with the pin, the
  `xserver-xorg-core` candidate must come from L4T (1.20.x), not Debian,
* with `--contents`, what the L4T packages ship (`nvpmodel`, polkit actions,
  `nvidia_drv.so`, ucm2, udev rules, ...), to know what no longer has to live
  in this repository.

Libraries that Debian dropped but L4T packages still need (today: `libpcre3`,
required by `nvidia-l4t-multimedia`) come from an otherwise disabled older
suite: `NXD_COMPAT_SUITE` / `NXD_COMPAT_PACKAGES` in `config/nxd.conf`. Only the
listed packages can be installed from it (pin 100, everything else -1). Set
`NXD_COMPAT_SUITE=""` to turn it off.

Pick the component that resolves with pins and set `NXD_L4T_COMPONENT` in
`config/nxd.conf` (or pass `--component` to `nxd rootfs`).

Please send back `spike-report.md`: it decides the contents of
`config/packages/*.list`.

## 2. The rootfs

```
sudo ./nxd rootfs --variant xfce            # or: retrobox
./nxd rootfs --variant retrobox --dry-run   # only print the mmdebstrap command
```

Output: `build_output/<variant>/rootfs.tar` and `manifest.txt` (package and
version of everything installed, from `dpkg-query`).

The build has two phases:

1. `mmdebstrap` bootstraps a Debian `minbase` with `apt` and certificates.
2. Customize hooks copy the L4T key (`/etc/apt/keyrings`), the pins and the
   source (`/etc/apt/sources.list.d/nxd-l4t.sources`) into the rootfs and run
   `apt-get install` of the variant package list **inside** it. The image
   keeps the same repositories and pins, so `apt` works after the first boot.

Then the scripts of `config/hooks/*.sh` run inside the rootfs (currently:
empty `machine-id`, `systemd-firstboot` masked).

Then `./nxd inspect --variant retrobox` (no root) prints a report, also saved as
`build_output/<variant>/report.txt`: size, heaviest packages, who pulled in what
(`--why PKG` for more), image hygiene (machine-id, build flags, apt sources),
boot files and kernel modules, enabled services and accounts.

Variants are a list of package lists (`config/variants/*.conf`,
`config/packages/*.list`). Add a package by editing a list, not a script.

## 3. On Fedora Asahi (native arm64)

Fedora has neither `apt` nor the Debian keyrings, so everything runs in a
Debian trixie container:

```
./nxd container spike --contents
sudo ./nxd container rootfs --variant xfce
```

Uses `podman` (or `docker`; override with `NXD_CONTAINER_ENGINE`). The
container is privileged because `mmdebstrap` needs mount and chroot, hence
`sudo` for `rootfs`; the spike does not need it. As the host is arm64 no
emulation is involved.

Notes:

* Asahi kernels use 16K pages. This is irrelevant for building (ext4 images
  keep 4K blocks), it would matter only when running arm64 binaries of the
  Tegra stack on the Mac.
* The Mac cannot boot-test the result (Tegra X1 + Hekate): it validates the
  package resolution, the rootfs contents and the XFCE layout (with
  Xvfb/Xephyr).

## 4. Tests

```
tests/test-lists.sh        # offline, no root
sudo tests/integration.sh  # fake signed L4T repo, runs the spike and a rootfs
sudo tests/image.sh        # nxd image on a hand-made rootfs
```

## The first user

`nxd rootfs --user NAME` creates the first account (uid/gid 1000) in the image.
The password is read, in this order, from `--password-hash HASH` (a crypt(3)
hash, for example `openssl passwd -6`), from `$NXD_PASSWORD`, or from a prompt;
`--no-password` leaves the account without one. Only the hash reaches the
image: it travels in a mode-600 file that `config/hooks/20-user.sh` consumes
and deletes. The user joins `sudo`, `audio`, `video`, `input`, `render`,
`plugdev`, `netdev`, `bluetooth` and `dialout`, whichever of them exist.

Without `--user` the image has no user and root is locked; the first-boot
setup is meant to create it.

## Leaving things out of a variant

A variant can set `NXD_PATH_EXCLUDES` (and `NXD_PATH_INCLUDES` for the
exceptions) in its `config/variants/*.conf`. They become dpkg `path-exclude` /
`path-include` lines, applied from the bootstrap on and kept in
`/etc/dpkg/dpkg.cfg.d/nxd-excludes`. Retrobox leaves out the kernel headers,
man pages, info pages and package docs (copyright files stay).

## Ownership of the output

When the build runs as root (`sudo`, or the container), the output directory is
handed back to the owner of its parent, so `nxd inspect` can write its report
without `sudo`.

## Masking units

`NXD_MASK_UNITS` in a variant conf lists units to mask in the image
(`config/hooks/30-services.sh`). Retrobox masks the apt-daily timers and
services; NetworkManager, bluez and the audio daemons are left alone because
Retrobox drives them.

## The SD card installer (`nxd image`)

```sh
sudo ./nxd container image --variant retrobox      # or: sudo ./nxd image ...
```

It takes `rootfs.tar` and writes `<output>/<variant>/installer.zip` plus
`SHA256SUMS`:

- the tree is unpacked as root and copied into an ext4 image labelled
  `SWR-DEB` (`--size`, default 5120M; the first boot expands it to the
  partition), checked with `e2fsck`, and split in `l4t.00`, `l4t.01`... of
  4092M, the most FAT32 can hold;
- the kernel (`uImage`), `initramfs`, `nx-plat.dtimg`, `bl31.bin`, `bl33.bin`
  and `boot.scr` come from the `switch-bsp` package inside the rootfs: no
  kernel is built here. `boot.scr` gets `NXD_KERNEL_CMDLINE_EXTRA`
  (default `net.ifnames=0`, which keeps `wlan0`) after the cgroup flag;
- `config/boot/hekate.ini` becomes `bootloader/ini/debian.ini` (name, id and
  title from `NXD_BOOT_NAME`, `NXD_BOOT_ID`, `NXD_BOOT_TITLE`);
- the boot logo and icon are `assets/bootlogo.bmp` and `assets/icon.bmp` when
  they exist, else the ones of `switch-bsp`;
- Hekate itself is the latest release (cached in `downloads/`), or `--hekate
  ZIP`, or nothing with `--no-hekate`.

Unzip the installer at the root of the SD card, boot Hekate and flash the
`l4t.*` parts from its partition manager.

`/etc/fstab`, `/etc/hostname` and `/etc/hosts` come from
`config/overlay/common`; `config/overlay/<variant>` adds to it. The root
filesystem is mounted by label, not by partition number.

## Autologin

When `--user` is given and the variant sets `NXD_AUTOLOGIN_SESSION`, the user
hook writes `/etc/lightdm/lightdm.conf.d/50-nxd-autologin.conf`: lightdm logs
that user straight into the session (`xfce` for both variants, the one that
`xfce4-session` ships). `config/packages/xfce-core.list` is the session core
both variants share (session, window manager, panel, desktop, settings,
terminal), so an application can run on the bare session and bring the panel
and the desktop up when it ends. Change the variable to `openbox` for a plain
Openbox session.

The first user is also put in `adm` and `systemd-journal`, to read the logs
without sudo.
