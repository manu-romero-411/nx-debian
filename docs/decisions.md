# Decisions

## Kernel: stay on the Switchroot 4.9 kernel, on Debian 13 (trixie)

Status: decided.

The image runs the 4.9.140-l4t kernel that `switch-bsp` (theofficialgman's L4T
repository) ships, together with its bootstack and modules. We do not backport
a newer kernel now, and we stay on trixie.

Why:

- The L4T userspace (`nvidia-l4t-*`, Xorg 1.20.14) and the Tegra X1 drivers
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
