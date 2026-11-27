# nx-debian's packages and nxd-update

Every file nx-debian adds to the system (services, configuration, scripts, the
Retrobox session...) is in a Debian package built from this repository, not
copied into the image loose. An image installs the packages of the commit it
is built from, and a console that is already installed gets the new ones with
`nxd-update`, without flashing again.

What stays out of the packages is what makes one image that image, written by
the build: the user and its autologin (`config/hooks/20-user.sh`), the
hostname, `/etc/hosts` and `/etc/fstab` (`config/overlay/common`), the empty
`machine-id`, the units a variant masks or disables, the content preloaded for
Retrobox and the emulators installed at build time.

## The packages

| Package | What it has | Installed in |
| --- | --- | --- |
| `nxd-common` | `nxd-update`; the font of the text consoles (Terminus, regular, 8x16: its `postinst` puts it in `/etc/default/console-setup` and in debconf on the first install, so a font chosen later stays); the common locales of Europe, generated (`/usr/share/nxd/locales`: English, Spanish, Catalan, Basque, Galician, French, German, Italian, Polish, Russian, Ukrainian and Greek, in UTF-8; on every configure its `postinst` runs `/usr/lib/nxd/ensure-locales`, which uncomments or adds them in `/etc/locale.gen` and runs `locale-gen` if one is missing; locales added by hand stay, none is removed); the volume kept between starts (Switchroot's UCM profile, `/usr/share/alsa/ucm2/Tegra/tegra-snd-t210ref-mobile-rt565x/HiFi.conf`, set the speaker's and the headphones' DAC1 volume, the controls PulseAudio drives, to their maximum whenever it enabled them: `preinst` diverts it with `dpkg-divert` to `HiFi.conf.switch-alsa-ucm2`, and `postinst` writes `/usr/lib/nxd/ucm-volume`'s copy without those lines in its place, again whenever switch-alsa-ucm2 changes it: `triggers`; removing nxd-common puts Switchroot's back); the sound on the headphones while they are plugged in (in that profile the speaker and the headphones are two profiles of the card, and PulseAudio does not change it when the jack says the headphones are there: `/usr/lib/nxd/headphones`, run for every user by the user unit `nxd-headphones.service`, switches to the profile with the other output on each plug and unplug, and leaves alone a profile chosen by hand meanwhile; each output keeps its own volume; the port is debounced and the switches are rate-limited (at most one per 5 seconds) and kept in a state file in tmpfs, so a flappy port cannot flip the profile every few seconds and the unit can restart freely); the performance backend (`/usr/share/polkit-1/actions/org.nxd.nvpmodel.policy`: the user of the active session runs `nvpmodel` and `/usr/lib/nxd/nvpmodel-helper` through `pkexec` without a password, any other one needs an administrator's; `nxd-nvpmodel-restore.service` applies the saved fan mode, charge limit and panel colour mode at boot); the lightdm seat settings for the Switch (`/etc/lightdm/lightdm.conf.d/10-nxd-seat.conf`); the firmware names the Wi-Fi/Bluetooth chip asks for (made by its `postinst`, again whenever a package changes `/usr/lib/firmware/brcm` or `/usr/lib/modules`: `triggers`); the GitHub repository of nx-debian (`/usr/share/nxd/releases.d/nx-debian.list`) | every image |
| `nxd-xfce` | `switch-rotate` (turns the screen and the touchscreen together and remembers it: `~/.config/nxd/rotation`, put back at login by `/etc/xdg/autostart/nxd-switch-rotate.desktop`) and its launcher; `switch-sensors` (SoC temperature and fan, for the panel's genmon plugin); the performance indicator (`/usr/share/nxd/nvpmodel-indicator`: profiles, fan modes, battery charge limit; started in XFCE and in the menu); the desktop's defaults in `/etc/xdg/nxd` (theme and fonts, the two panels, default applications, MIME types), put before `/etc/xdg` in `XDG_CONFIG_DIRS` for the XFCE session (`/etc/X11/Xsession.d/55nxd-xfce`) and the user services (`/usr/lib/environment.d/60-nxd-xfce.conf`), so they win over the XFCE packages' defaults and a user's own settings win over them | `xfce` |
| `nxd-retrobox` | what retrobox-session-openbox's `retrobox-openbox` session needs for the Switch (its step `/etc/retrobox/session.d/50-nxd-emulationstation`); Retrobox's settings (`/etc/retrobox/retrobox.ini.d/50-nxd.ini`); the SD card (`nxd-sdcard.service`, `/usr/sbin/nxd-sdcard`); the volume toast and the power button (`/etc/retrobox/overlay.ini`, `/etc/systemd/logind.conf.d/10-nxd-power.conf`; the buttons themselves are retrobox-session-openbox's); the Capture button of the Joy-Cons and the Pro Controller (`BTN_Z`), which takes a screenshot with retrobox-screenshot (`/usr/share/nxd/retrobox/capture-button`, started by the session's step `60-nxd-capture-button`); the power button in the session (`/usr/share/nxd/retrobox/power-button`, started by the step `61-nxd-power-button` under a `handle-power-key` and `handle-suspend-key` inhibitor (the Switch's button is a suspend key, `KEY_SUSPEND`; its log: `~/.local/state/retrobox/logs/power-button.log`): a tap suspends, holding it one second opens the overlay's power options, `retrobox-overlay --power`; logind handles it when the session is not there); the compositor across a suspend (`/usr/lib/systemd/system-sleep/nxd-picom`: closes picom before a suspend and reopens it at the resume as the user that ran it, with its environment and invocation, but only when it was running at the suspend); the overlay's menu at 175 % (`row_scale` in `/etc/retrobox/overlay.ini`); EmulationStation's defaults for the Switch (`/usr/share/nxd/retrobox/emulationstation`); the GitHub repositories of the Retrobox packages (`/usr/share/nxd/releases.d/retrobox.list`, linked from `/etc/retrobox/releases.d/retrobox.list` for retrobox-update) | `retrobox` |

`packages/<name>/root/` holds the files as they go in `/`, and
`packages/<name>/DEBIAN/` the `control.in` (its `@VERSION@` is filled in)
and the maintainer scripts. A new variant `foo` gets its files by adding
`packages/nxd-foo/`: the build installs `nxd-common` and `nxd-<variant>` when
there is one.

- **Configuration files.** Everything under `/etc` is a conffile: dpkg keeps a
  copy changed by hand when the package brings a new one (`nxd-update` keeps
  the old one, `--force-confold`, and dpkg leaves the new one next to it as
  `.dpkg-dist`).
- **Other packages' files.** A package cannot own a file another one has
  (`/etc/xdg/xfce4/panel/default.xml` is xfce4-panel's, `xsettings.xml`
  xfce4-settings'), so nxd-xfce's defaults live in `/etc/xdg/nxd`, a
  configuration folder of its own that comes first.
- **The user's files.** Nothing goes in `/etc/skel`: a package update would not
  reach accounts that already exist. Openbox gets its configuration from the
  session's command line, not from the home. EmulationStation's `es_input.cfg`
  and `es_settings.cfg` are the exception: EmulationStation rewrites them, so
  the session's step `50-nxd-emulationstation` copies the package's ones into the user's Retrobox
  configuration only when the user has none, and they are the user's from then on.
- **Services.** `nxd-sdcard.service` is enabled on the first install, the way
  debhelper does it (`deb-systemd-helper`): an upgrade keeps it disabled if it
  was disabled by hand.

## Building them

```
./nxd debs dist                       # every package, into dist/
./nxd debs --variant retrobox dist    # nxd-common and nxd-retrobox
./nxd debs --version 1.2.0 dist       # a given version
./nxd debs --print-version            # the version they would get
```

No root needed: `dpkg-deb` makes the files belong to root. The version is the
one of a continuous build, the rule of the Retrobox repositories
(`.github/scripts/continuous-version.sh`): the last release's, from the
highest `vX.Y` or `vX.Y.Z` tag (a missing patch is 0, no tag at all is
`0.0.0`), with the UTC time of the build as one more number
(`0.7.9.20261127093012`): above that release, below the next one
(`0.7.10`, `0.8.0`), and each build above the one before. Digits and dots
only, as GitHub rewrites any other character in an asset's name. A release
gets the version of its tag (`--version`). The files get the commit's date. `nxd rootfs` (and so `nxd build`) builds them for the variant
and installs them with the Retrobox packages; `nxd container` works out the
version outside the container, which has no git (`NXD_PACKAGE_VERSION`
overrides it).

## Where they are published

The same way as the Retrobox repositories (`.github/scripts` are copies of
theirs: keep them equal):

- **Every push to `main`** (`.github/workflows/packages.yml`): the
  continuous pre-release, tag `continuous`, deleted and made again on the new
  commit (one release, never offered by `/releases/latest`), with the `.deb`
  files of the continuous version and their `SHA256SUMS`. The consoles take it
  with `nxd-update --allow-prereleases`; while it is being made again,
  `nxd-update` warns that it cannot read it and the next run finds it.
- **Every `vX.Y` or `vX.Y.Z` tag pushed** (`build.yml`): the release of that
  tag, with the installers, the packages of its version and `SHA256SUMS`; only
  `vX.Y` and `vX.Y.0` are full releases, any other `vX.Y.Z` is a
  pre-release. A manual run of `build.yml` only builds (the installers stay as
  artifacts for 14 days).

## nxd-update

```
nxd-update                       # Debian, L4T, nx-debian, Retrobox: releases
nxd-update --allow-prereleases   # ...and the pre-releases too
```

It runs itself through `sudo` when needed, and holds off sleep, shutdown and
the power button while it works. As `retrobox-update` does on the Retrobox
side, the members of the `nxd` group (the console's user) need no password:

- `sudo`: `/etc/sudoers.d/nxd-update` (a conffile, 0440) lets the group run
  `/usr/bin/nxd-update` as root with `NOPASSWD`, keeping `GITHUB_TOKEN`; not
  with `--download-only`, which writes where it is told and needs no root (it
  refuses to run through sudo). Remove the file, or the user from the group,
  to get the password prompt back.
- `pkexec`: the Retrobox overlay's *Update system* runs it as root with
  nxd-common's polkit action `org.nxd.update`, which the user at the console
  gets without a password, and the group from any session, ssh included
  (`/usr/share/polkit-1/rules.d/50-nxd-update.rules`).

nxd-common's `postinst` makes the group, with the console's user (uid 1000) in
it when it makes it, so a console installed before gets it too; the image puts
its user in it (`config/hooks/20-user.sh`). In order:

1. `retrobox-update --no-recommends`, run whole (retrobox-system-settings'
   updater): `apt-get update` and `apt-get dist-upgrade` (Debian and the L4T
   packages; the L4T pins of `/etc/apt/preferences.d` still decide which comes
   from where), then Retrobox's packages from the lists of
   `/etc/retrobox/releases.d` (where nxd-retrobox links its `retrobox.list`).
   Only on the Retrobox image (`nxd-retrobox` installed); `retrobox-update`
   knows nothing of `nxd-update`. Any other image runs the two apt steps
   itself.
2. The packages from GitHub releases that are not in apt. For each repository of
   `/usr/share/nxd/releases.d/*.list` (nx-debian's own, and any other list, such
   as Switchroot's; not the Retrobox one when `retrobox-update` has it), the release with the newest packages (by their upload
   date) that is not a pre-release, or with `--allow-prereleases` pre-release
   or not (a repository with pre-releases only gets nothing without it, and
   says so); from it, the `.deb` of this
   machine (as the build picks them: this CPU or `all`, this Debian's build
   before a generic one, no `-dbgsym`) **of packages that are installed**, if
   they are newer than the installed version. A release without a
   `SHA256SUMS`, or a file that does not match it, is not installed. Then one
   `apt-get install` of all of them, so their new dependencies come from
   Debian. The release used last time is remembered in `/var/lib/nxd/releases`,
   and is not downloaded again.
3. `apt-get autoremove --purge` and `apt-get clean`.

Switchroot's `nintendo-switch-meta` is `Essential: yes`, so any `apt-get
dist-upgrade` would install it and its dependencies (the set of Switchroot's
Ubuntu images: flatpak, gnome-software, the gamepad-as-mouse driver, a second
source for the L4T repository...). nxd-common pins it, and `switch-l4t-repo`,
below zero (`/etc/apt/preferences.d/50-nxd-no-l4t-meta.pref`), so apt never
installs them. Like the build, `nxd-update` also installs no Recommends (`APT::Install-Recommends=false`):
an upgrade does not bring what the image leaves out on purpose, such as the
L4T meta package, flatpak or the gamepad-as-mouse driver. Everything is
non-interactive (`DEBIAN_FRONTEND=noninteractive`), and
configuration files changed by hand are kept. `--download-only DIR` stops
after downloading and checking the packages of step 2 (no root, no apt).
`$GITHUB_TOKEN` (sudo keeps it) avoids GitHub's limit of 60 anonymous
requests an hour; a run makes one per repository.

`tests/packages.sh` checks what the packages have and what `nxd-update`
chooses, against a fake GitHub API.
