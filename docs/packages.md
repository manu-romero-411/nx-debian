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
| `nxd-common` | `nxd-update`; the lightdm seat settings for the Switch (`/etc/lightdm/lightdm.conf.d/10-nxd-seat.conf`); the firmware names the Wi-Fi/Bluetooth chip asks for (made by its `postinst`, again whenever a package changes `/usr/lib/firmware/brcm` or `/usr/lib/modules`: `triggers`); the GitHub repository of nx-debian (`/usr/share/nxd/releases.d/nx-debian.list`) | every image |
| `nxd-retrobox` | the `nxd-retrobox` session (Openbox, picom, Retrobox: `/usr/share/xsessions/nxd-retrobox.desktop`, `/usr/lib/nxd/retrobox-session`, `retrobox-autostart`, `/usr/share/nxd/retrobox/openbox/rc.xml`); Retrobox's settings (`/etc/retrobox/retrobox.ini.d/50-nxd.ini`); the SD card (`nxd-sdcard.service`, `/usr/sbin/nxd-sdcard`); the volume and power buttons (`/usr/bin/nxd-volume`, `/etc/systemd/logind.conf.d/10-nxd-power.conf`); EmulationStation's defaults for the Switch (`/usr/share/nxd/retrobox/emulationstation`); the GitHub repositories of the Retrobox packages (`/usr/share/nxd/releases.d/retrobox.list`) | `retrobox` |

`packages/<name>/root/` holds the files as they go in `/`, and
`packages/<name>/DEBIAN/` the `control.in` (its `@VERSION@` is filled in)
and the maintainer scripts. A new variant `foo` gets its files by adding
`packages/nxd-foo/`: the build installs `nxd-common` and `nxd-<variant>` when
there is one.

- **Configuration files.** Everything under `/etc` is a conffile: dpkg keeps a
  copy changed by hand when the package brings a new one (`nxd-update` keeps
  the old one, `--force-confold`, and dpkg leaves the new one next to it as
  `.dpkg-dist`).
- **The user's files.** Nothing goes in `/etc/skel`: a package update would not
  reach accounts that already exist. Openbox gets its configuration from the
  session's command line, not from the home. EmulationStation's `es_input.cfg`
  and `es_settings.cfg` are the exception: EmulationStation rewrites them, so
  `retrobox-session` copies the package's ones into the user's Retrobox
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

No root needed: `dpkg-deb` makes the files belong to root. The version comes
from git: `X.Y.Z` on a `vX.Y.Z` tag, `X.Y.Z.gitN.gSHA` N commits after it
(newer than `X.Y.Z`, older than the next release), `0.0.0.gitN.gSHA` before
the first tag. Two builds of one commit are the same file (the files get the
commit's date). `nxd rootfs` (and so `nxd build`) builds them for the variant
and installs them with the Retrobox packages; `nxd container` works out the
version outside the container, which has no git (`NXD_PACKAGE_VERSION`
overrides it).

## Where they are published

- **Every push to `main`** (`.github/workflows/packages.yml`): the
  `nxd-latest` pre-release, replaced each time, with the `.deb` files and
  their `SHA256SUMS`.
- **Every release** (`build.yml`, a `vX.Y.Z` tag or a manual run with
  "publish"): the release has the installers and the packages of its version.
  An image built from a tag has the packages of that version; one built by a
  manual run has the `gitN` version of its commit, and `nxd-update` brings the
  release's.

## nxd-update

```
sudo nxd-update                       # Debian, L4T, nx-debian, Retrobox: releases
sudo nxd-update --allow-prereleases   # ...and the pre-releases too
```

It runs itself through `sudo` when needed, and holds off sleep, shutdown and
the power button while it works. In order:

1. `apt-get update` and `apt-get dist-upgrade` (Debian and the L4T packages;
   the L4T pins of `/etc/apt/preferences.d` still decide which comes from where).
2. The packages from GitHub releases. For each repository of
   `/usr/share/nxd/releases.d/*.list` (nx-debian, then the Retrobox
   components), the newest release, or with `--allow-prereleases` the newest
   one that has packages, pre-release or not; from it, the `.deb` of this
   machine (as the build picks them: this CPU or `all`, this Debian's build
   before a generic one, no `-dbgsym`) **of packages that are installed**, if
   they are newer than the installed version. A release without a
   `SHA256SUMS`, or a file that does not match it, is not installed. Then one
   `apt-get install` of all of them, so their new dependencies come from
   Debian. The release used last time is remembered in `/var/lib/nxd/releases`,
   and is not downloaded again.
3. `apt-get autoremove --purge` and `apt-get clean`.

Everything is non-interactive (`DEBIAN_FRONTEND=noninteractive`), and
configuration files changed by hand are kept. `--download-only DIR` stops
after downloading and checking the packages of step 2 (no root, no apt).
`$GITHUB_TOKEN` (sudo keeps it) avoids GitHub's limit of 60 anonymous
requests an hour; a run makes one per repository.

`tests/packages.sh` checks what the packages have and what `nxd-update`
chooses, against a fake GitHub API.
