# Decisions

## Kernel: stay on the Switchroot 4.9 kernel, on Debian 13 (trixie)

Status: decided.

The image runs the 4.9.140-l4t kernel that `switch-bsp` (theofficialgman's L4T
repository) ships, together with its bootstack and modules. We do not backport
a newer kernel now, and we stay on trixie.

Why:

- The L4T userspace (`nvidia-l4t-*`, Xorg 1.20.13) and the Tegra X1 drivers
  are tied to that kernel; a newer one means maintaining that stack ourselves.
- Debian 13 works with it. systemd 257 still supports cgroup v1, which this
  kernel needs; the 30 s wait it causes at boot is avoided with
  `SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1` on the kernel command line.
- No alternative is ready: the L4S kernels (backports onto 4.9, packaged in
  the `linux4switch/l4s` COPR and developed in the l4t-community GitLab) are
  not packaged for Debian.

Reopen this decision when any of these happens:

1. We want a Debian with systemd 258 or later. It drops cgroup v1 and needs a
   kernel 5.4 or later, so the 4.9 kernel cannot boot it.
2. BlueZ 5.8x does not work with the 4.9 kernel (Bluetooth controllers,
   Joy-Cons, Pro Controller). The alternative is to port the Switchroot BlueZ
   patches to the version of Debian.
3. The L4S / l4t-community kernel becomes reusable as a Debian package (or
   its build can be reproduced in `nxd`).

Things to check on the hardware before relying on this: that the cmdline flag
really removes the wait, and the real cgroup mode
(`stat -fc %T /sys/fs/cgroup/`, `tmpfs` means v1).

## Mainline kernel and Mesa: an experimental variant, not a replacement

Status: proposed.

The two graphics stacks cannot be mixed. NVIDIA's driver (`nvidia-l4t-*`
32.3.1) needs nvgpu and nvmap from the 4.9 L4T kernel, and NVIDIA has no newer
kernel for T210 (JetPack 4 was the last release for it). Mesa needs nouveau and
tegra-drm from a mainline kernel; NVK also needs the VM_BIND uAPI of Linux 6.6
or later. Moving to Mesa therefore means moving to a mainline kernel and leaving
L4T.

The open stack is worked on in the `mainline` branch, in a separate variant,
`mainline` (`config/variants/mainline.conf`), marked experimental so that
`nxd build` and the CI keep building the L4T variants only. `main` goes on
with L4T and is what is published; the branch is rebased on it and merged
only when the mainline variant reaches the L4T ones. The plan, its phases and what
is lost on the way are in [mainline.md](mainline.md).

Why:

- It covers reasons 1 and 2 of the decision above (systemd 258, BlueZ) and
  adds what 4.9 cannot run: FEX-Emu (and so Proton) and Wayland.
- The variant reuses everything that does not depend on the kernel (lists,
  overlays, hooks, users, services): the work is the kernel, the boot path and
  the hardware, not a second build system.
- Nothing published changes until the variant boots and works.

Facts to keep in mind:

- NVK does not officially support Tegra. NVK on T210 is being worked on
  upstream for the Switch, and it is mostly missing kernel fixes (Mesa work
  item 14105).
- Tegra210B01 (Mariko: V2, Lite, OLED) is not in mainline yet; the patches are
  under review. Phase 1 targets Erista (V1).

Make it the default when the mainline variant boots on Erista and Mariko and
covers the hardware table of mainline.md; drop it if the kernel tree it
depends on stops being maintained.

## The images' own changes live in this repository

Status: decided.

The changes the images need (configuration files, hooks, scripts, the pieces of
the desktop that were in the `switchroot-xfce` package) are kept in this
repository (`config/overlay/`, `config/hooks/`, `config/variants/`; see
[rootfs.md](rootfs.md#patches-live-in-this-repository)), not in a separate
repository nor in a package of their own. One place to change, one commit for
a change and the test that covers it, and the CI builds exactly what is
committed.

Reopen it if something here is wanted outside the images, for example the
desktop pieces installed on an existing Switchroot system: then that part
becomes a package built from this repository.
