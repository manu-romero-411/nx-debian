# nxd: viability spike and rootfs skeleton

`nxd` is the entry point of the apt-based build. It replaced the old
`build.sh`, which is kept in the git history (see
[legacy-inventory.md](legacy-inventory.md)).

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
tests/releases.sh          # fetch-releases.sh against a fake GitHub API on localhost
tests/version.sh           # scripts/next_version.py in a scratch git repository
```

`.github/workflows/ci.yml` runs all of them (and shellcheck and pylint) on every
push and pull request.

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
  (default `net.ifnames=0`, which keeps `wlan0`, and
  `SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1`, without which systemd 257 waits 30 s
  at every boot on the cgroup v1 of the 4.9 kernel) after the cgroup flag;
- `config/boot/hekate.ini` becomes `bootloader/ini/debian.ini` (name, id and
  title from `NXD_BOOT_NAME`, `NXD_BOOT_ID`, `NXD_BOOT_TITLE`);
- the boot logo and icon are `assets/bootlogo.bmp` and `assets/icon.bmp` when
  they exist, else the ones of `switch-bsp`;
- Hekate itself is not included: whoever installs this has it already (a hats
  pack updates it together with the rest). `--with-hekate` adds the latest
  release (cached in `downloads/`) and `--hekate ZIP` a release you have.

Unzip the installer at the root of the SD card, boot Hekate and flash the
`l4t.*` parts from its partition manager.

`/etc/fstab`, `/etc/hostname` and `/etc/hosts` come from
`config/overlay/common`; `config/overlay/<variant>` adds to it. The root
filesystem is mounted by label, not by partition number.

## Autologin

When a user is created and the variant sets `NXD_AUTOLOGIN_SESSION`, the user
hook writes `/etc/lightdm/lightdm.conf.d/50-nxd-autologin.conf`: lightdm logs
that user straight into the session. `xfce` starts the XFCE session
(`xfce4-session`), `openbox` a plain Openbox one. The hook warns when the
session file is missing from `/usr/share/xsessions`.

The first user is also put in `adm` and `systemd-journal`, to read the logs
without sudo.

## Default user and hostname

A variant may fix its user with `NXD_DEFAULT_USER` and `NXD_DEFAULT_PASSWORD`
(an empty password means a passwordless account). With `NXD_PROMPT_USER=1`
(the desktop, `xfce`) a build at a terminal asks for the user name and the
password instead, and Enter keeps the defaults (`switch` / `switch`); one
without a terminal, like the CI, takes the defaults without asking. `retrobox` ships the user
`retrobox` with the password `retrobox`, so `nxd rootfs --variant retrobox`
asks nothing. `--user`/`--password-hash`/`--no-password` and `$NXD_PASSWORD`
override it, and `--no-user` builds without any account.

Because that password is public, `xfce` keeps `ssh.service` and `ssh.socket`
disabled (`NXD_DISABLE_UNITS`: the links are removed, the packages stay, so
`systemctl enable --now ssh` is all it takes). `retrobox` leaves ssh on, to work
on the console from a computer: change the password (`--user`,
`--password-hash`) before it joins a network you do not trust. Masked units
(`NXD_MASK_UNITS`) are different: they point to `/dev/null` and cannot be
started at all.

The hostname of every variant is `nintendo-switch`
(`config/overlay/common/etc/hostname` and `hosts`).

## Packages from GitHub releases

Some components are not in any apt repository. A variant lists them in
`config/releases/<NXD_RELEASE_LIST>.list`, one `owner/repo` per line (`#`
comments allowed), and `scripts/fetch-releases.sh` downloads them before the
build:

- the latest release that GitHub does not mark as a pre-release is used, and a
  repository that has none stops the build. `--prereleases` (`nxd rootfs`,
  `nxd build`, `nxd container build`, `NXD_PRERELEASES=1`, the `prereleases`
  input of the build workflow) takes the newest release of each repository,
  pre-release or not, never a draft: Retrobox keeps adding features, and its
  releases lag behind until it is finished. The fetch log says which ones are
  pre-releases, and the workflow marks the GitHub release it publishes as a
  pre-release when it was built that way;
- per repository it picks the `.deb` for `NXD_ARCH` (`arm64`), else the one
  for `all`; one tagged for this Debian (`NXD_RELEASE_TAG_RE`, by default
  `debian13` or `trixie`) wins over a generic one, other distributions' are
  ignored, `-dbgsym` packages are never taken;
- the release must have a `SHA256SUMS` asset, and every `.deb` is checked
  against it; a release without one, or a mismatch, stops the build;
- `$GITHUB_TOKEN`, if set, is sent to the API (it is forwarded into the
  container) to avoid the anonymous rate limit.

They are installed with `apt-get install --no-install-recommends` after the
main package list, so their dependencies come from Debian. `--releases-dir D`
uses the `.deb` files in `D` instead (offline builds, tests), and
`--no-releases` skips them.

`retrobox` installs `retrobox-core`, `retrobox-mangohud`,
`retrobox-emulationstation` and `retrobox-overlay`. Openbox starts Retrobox
from `/etc/skel/.config/openbox/autostart` (`retrobox &`), which the user
account copies at creation; `/etc/xdg/openbox/autostart` is a dpkg conffile
and is left alone. Their Recommends are not installed; add the ones you want
(for example the PySide6 settings window) to `config/packages/retrobox.list`.

## Building the installers (`nxd build`)

```
sudo ./nxd build                          # every variant, here
sudo ./nxd build --variant retrobox       # one of them
sudo ./nxd container build --clean        # the same, in a container
sudo ./nxd build --skip-rootfs            # only re-image the rootfs.tar that is there
sudo ./nxd build --variant xfce -- --user manu   # options after -- go to nxd rootfs
```

For each variant it runs `nxd rootfs`, `nxd inspect` (a failure there is only a
warning) and `nxd image`, then puts in `dist/` (`--dist`, `$NXD_DIST_DIR`):

- `switch-debian-13-trixie-<variant>-installer.zip`, or `-installer-hekate.zip` when
  Hekate is in it (the prefix is
  `$NXD_DIST_PREFIX`),
- `...-<variant>-packages.txt`, the package list of the image,
- `...-<variant>-report.txt`, the `nxd inspect` report,
- one `SHA256SUMS` of the lot.

`--clean` deletes each `rootfs.tar` once its installer is made, which matters on
a small disk; `--require-hekate` implies `--with-hekate` and fails instead of warning when
Hekate cannot be downloaded; `--size`, `--with-hekate`, `--hekate` and
`--no-hekate` are those of `nxd image`.
It warns when an installer reaches 2 GiB, which GitHub does not take as a
release asset.

## Continuous integration and releases

`.github/workflows/build.yml` is the same command on a native arm64 runner
(`ubuntu-24.04-arm`, so no qemu), one job per variant, in the same container
anyone can use. It starts:

- by hand, from Actions, *Build images*, *Run workflow*: `variant` is `all` or
  the name of one; ticking `publish` makes a release;
- when a tag `v*` is pushed: it builds everything and publishes a release for
  that tag.

The installers are kept as workflow artifacts for 14 days whether or not a
release is made. A release is made only if every variant built: one
`SHA256SUMS` is computed for all the files, the tag comes from
`scripts/next_version.py` (the scheme of the old release script: `v1.0.0`,
`v1.0.1`, ... `v1.0.10`, `v1.1.0`, ...) or is the pushed one, and the notes are
the commits since the previous release. Nothing else is needed: the
workflow's own `GITHUB_TOKEN` creates the release and lifts the rate limit of
the GitHub API calls (the Hekate download and the Retrobox packages).

Adding a variant is adding `config/variants/NAME.conf`: both the matrix of the
workflow and `nxd build` pick it up.

## Patches live in this repository

What the images need beyond what the packages bring is kept here, never in
another repository, and is applied by the build:

- `config/overlay/common/` and `config/overlay/<variant>/`: files copied into
  the image as they are (`/etc/hostname`, the Openbox autostart, the lightdm
  and Retrobox configuration...);
- `config/hooks/*.sh`: scripts run inside the image for every variant, in name
  order; `config/hooks/<variant>/*.sh` run after those, for that variant only;
- `config/packages/*.list`, `config/variants/*.conf`: what is installed, what
  is left out (`NXD_PATH_EXCLUDES`), which units are masked or disabled.

A hook that needs something decided at build time gets it as a file in
`/tmp` that the hook deletes (`nxd-user`, `nxd-mask`, `nxd-preload`, `nxd-emulators`...).

## lightdm and the Switch's seat

lightdm 1.32 (Debian 13) starts X only on a seat that logind marks graphical,
and `seat0` is not on the Switch: the service stays active with no X server
and the screen is black (`loginctl show-seat seat0 -p CanGraphical` says
`no`; `systemctl status lightdm` shows no process but lightdm itself).
`config/overlay/common/etc/lightdm/lightdm.conf.d/10-nxd-seat.conf` sets
`logind-check-graphical=false`, in the `[LightDM]` section: in `[Seat:*]` the
option is ignored. If the screen is still black after that, the logs are
`/var/log/lightdm/lightdm.log` and `x-0.log`.

## The Retrobox image: /retrobox, preloaded content, a gamepad that is a gamepad

- **Data directory.** `config/overlay/retrobox/etc/retrobox/retrobox.ini.d/50-nxd.ini`
  sets `data_dir = /retrobox`: ROMs, saves, BIOS, themes, bezels and shaders
  live there. `config/hooks/retrobox/10-retrobox-data.sh` creates it owned by
  the user of the image and the group of that user (`retrobox:retrobox` by
  default).
- **Configuration and logs in `/retrobox`.** The configuration is
  `/retrobox/config` (not `~/.config/retrobox`) and the logs are
  `/retrobox/state/logs` (not `~/.local/state/retrobox/logs`; `/retrobox/logs`
  is a link to it, made by `10-retrobox-data.sh`). `state_dir = /retrobox/state`
  in the same drop-in moves the state, which is also where the record of the
  installs and of what was offered (`store/`, `downloads-offered`) goes. The configuration cannot be set there: `retrobox.ini`
  lives in it, so Retrobox only takes it from `RETROBOX_CONFIGDIR`. The overlay
  sets `RETROBOX_CONFIGDIR` and `RETROBOX_STATEDIR` for the user services
  (`etc/environment.d`), the X session (`etc/X11/Xsession.d`) and login shells
  such as ssh (`etc/profile.d`); the overlay and its input daemon read only
  those variables, not the ini. The build hooks pass them too. The user's home
  keeps only what is not Retrobox's (Openbox, the shell...).
- **Content in the image.** Retrobox downloads its default theme
  (es-theme-iconic), the RetroBat bezels and its shaders the first time it
  starts. The hook runs Retrobox's downloader
  (`python3 -m retrobox.startup.downloads`, not `retrobox --download`, which
  the 0.6 release does not have) for the names in `NXD_PRELOAD` as the user,
  while the image is built, and records the packages as offered, so
  the first start has nothing left to fetch. They are the latest commit of
  their GitHub repositories at build time. `nxd rootfs --no-preload` (or
  `nxd build -- --no-preload`) skips it, for a quick build or without network:
  Retrobox then downloads them at its first start, as it always did. The
  bezels count in the size of the image and of the installer: look at the size
  `nxd build` prints (a release asset cannot reach 2 GiB).
- **RetroArch in the image.** `NXD_EMULATORS="retroarch"` makes
  `config/hooks/retrobox/20-retrobox-emulators.sh` run Retrobox's own installer
  (`/opt/retrobox/tools/emulators/retroarch.sh -i`) as the user of the image,
  into `/retrobox/emulators`. On aarch64 that is the libretro buildbot's
  `retroarch` binary, its assets (about 240 MiB compressed: assets, cheats,
  database, slang shaders, overlays...) and the base cores
  (`retrobox.cores.BASE_CORES`, 25 cores, 39 MiB compressed); flycast is built
  from source, because the buildbot's build does not work on the desktop
  OpenGL RetroArch. Every other core is downloaded on demand, from RetroArch's
  menu or EmulationStation's Content Downloader, into the same place.
  - The installer would use `sudo apt-get`, which the image does not need, so
    what it asks for is installed beforehand: the libraries of the binary are in
    `config/packages/retrobox.list`, and the hook installs the build tools
    (`build-essential git cmake unzip curl 7zip`) for the build and purges
    them, with everything they brought, once the emulators are installed.
    The OpenGL headers flycast includes (`GL/gl.h`) are unpacked from the
    `libgl-dev` and related packages into a temporary folder and found through
    `CPATH`, not installed: `libgl-dev` needs `libx11-dev`, and the L4T
    repository has its own `libx11-dev`, tied to its own `libx11-6`, which apt
    cannot solve next to Debian's.
  - It needs a retrobox-core that has the binary install for aarch64 (the
    commit after `v0.7.1`, which is a pre-release: build with `--prereleases`
    until a release has it). With an older one the hook warns that RetroArch
    is not in the image and goes on, instead of compiling it for the CPU that
    builds the image (`-march=native`) and crashing on the Switch; Retrobox
    offers to install it at the first start.
  - It needs network and makes the build slower (the flycast compile).
    `nxd rootfs --no-preload` (and `nxd build -- --no-preload`) skips it with
    the rest of the preload; RetroArch is then installed from Retrobox's setup
    screen at the first start.
  - Expect the installer to grow by roughly 0.3 GiB compressed; `nxd build`
    prints the size and warns from 2000 MiB.
- **A console, with the Nintendo layout.** The drop-in
  `etc/retrobox/retrobox.ini.d/50-nxd.ini` sets `[core] console_mode = true`:
  EmulationStation cannot be quit (QUIT opens the restart / suspend / shut down
  menu, with no "quit EmulationStation"), nor closed with Alt+F4. The default
  `/retrobox/config/frontend/.emulationstation/es_settings.cfg` (the overlay's
  `retrobox/config/...`)
  sets `InvertButtons`, EmulationStation's "Switch confirm & cancel buttons":
  the east button confirms and the south one goes back, as on Nintendo pads,
  in EmulationStation, RetroArch's menus and the setup screen alike. Both are
  defaults: the first is a system layer that a user's `retrobox.ini` overrides,
  the second is part of the image, and EmulationStation rewrites it when the
  user changes it, so their choice stays.
- **Text size.** The same `es_settings.cfg` sets EmulationStation's
  `FontScale` (the theme's text) to 1.5 and `MenuFontScale` (its menus) to 1.25:
  the screen of the Switch is small, mostly the Lite's. They are the "theme font
  scale" and "menu font scale" of its interface settings, and EmulationStation
  rewrites them if the user changes them. The overlay takes the sizes of its
  text from the menu theme EmulationStation exports, so it follows.
- **Default pad, keyboard, volume and power buttons.**
  - `es_input.cfg` in the same folder has the Switch Lite pad
    (`Nintendo Switch Lite Gamepad`, Home as `hotkey`) and a keyboard. The
    keyboard entry matters: the volume and power buttons reach X as keys, and
    EmulationStation opens its keyboard setup when it sees keys of a keyboard
    that has no configuration.
  - The skeleton's Openbox `rc.xml` takes those keys before EmulationStation
    does: volume up / down / mute run `/usr/local/bin/nxd-volume` (steps of 5 %
    of the default PulseAudio output, `pactl`), and the power key is only
    grabbed.
  - `etc/systemd/logind.conf.d/10-nxd-power.conf`: a tap on the power button
    suspends (standby), a long press powers off. Standby depends on the kernel
    and drivers of the Switch (4.9 L4T) and has not been verified on a device;
    the suspend / resume hook of the old `build.sh` (mute audio, resync the
    backlight) is not ported yet.
  - Joy-Cons have no default mapping yet.
- **No gamepad-as-mouse.** The mouse mode of the pad is the
  `switch-joystick-mouse` package and the `xserver-xorg-input-joystick` driver: they
  are in the `joystick` package list, which only the desktop uses. In the
  Retrobox image the pad is only a gamepad (the overlay does the key mapping),
  and the Xorg configuration that attaches the joystick driver is not
  installed even if some package brings it (`NXD_PATH_EXCLUDES`).
