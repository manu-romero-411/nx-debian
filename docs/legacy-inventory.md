# What the old `build.sh` did

`build.sh` (and `pack_l4t_installer.sh`, `builder/`, `tools/install_gui.py`,
`tools/mkdtboimg.py`, `tools/fix_ext4_perms.py`, `tools/bump_version.py`) were
removed when `nxd` took over. They stay in the git history under the tag
`legacy-build`:

```
git show legacy-build:build.sh
git checkout legacy-build -- build.sh      # to read it as a file
```

Most of it is replaced by packages (apt installs what `build.sh` copied by
hand) and by `nxd image` (`pack_l4t_installer.sh`, `fix_ext4_perms.py`,
`mkdtboimg.py`: the boot files, the device tree table and the permissions come
from `switch-bsp` and `mke2fs -d`). This is what is **not** in `nxd` yet,
all of it belonging to the desktop (`xfce`) variant. The line numbers are
those of `legacy-build:build.sh`.

| Feature | Where it was | State |
| --- | --- | --- |
| Xorg configuration for the Tegra screen (RandR, Xwrapper) | 359-455 | pending: `xfce` |
| On-screen keyboard (Onboard) in the XFCE autostart | 455-467 | pending: `xfce` |
| `switch-rotate`: live rotation of screen and touch, saved between boots | 534-657 | pending: `xfce` |
| XFCE appearance (Adwaita icons), top panel with tray, default applications, MIME associations, empty desktop | 658-890, 1030-1050 | pending: `xfce` |
| Coordinated startup of the Wi-Fi, Bluetooth, power and NVPModel applets | 890-1030 | pending: `xfce` |
| `nvpmodel` suite: overclock profiles, fan profiles, battery charge limit (`tools/nvpmodel_indicator`) | 1205-1270 | pending: `xfce`; sources kept in `tools/nvpmodel_indicator` |
| NetworkManager owns the network (netplan delegation, networkd/resolved masked, `nvwifibt` removed) | 1053-1100, 1509 | partly: NetworkManager is installed; check the masks on a real boot |
| PulseAudio as a user service, GObject typelibs for the applets | 1182-1205 | pending |
| Suspend/resume hook: mute audio, resync the backlight | 1571-1633 | pending |
| `tmpfiles.d` and an early service that repair permissions (sudo, `/home`, `/tmp`) | 1804-1857 | not needed: `mke2fs -d` keeps the owners and modes of the packages; revisit if a boot shows wrong permissions |
| Release versioning and changelog (`tools/bump_version.py`) | | ported to `scripts/next-version.py` |

The kernel patches in `patches/kernel/` (BlueZ 5.8x management opcodes, Joy-Con
serdev rate limit) and `BCM4356A3.hcd` are not used while the image runs the
`switch-bsp` kernel; they are the plan B of the decision in
[decisions.md](decisions.md). The firmware file is also copied by
`config/hooks/40-switch-firmware.sh`.
