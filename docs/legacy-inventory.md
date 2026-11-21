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
from `switch-bsp` and `mke2fs -d`). This is what was **not** in `nxd` at first,
most of it belonging to the desktop (`xfce`) variant, and what became of it.
The line numbers are those of `legacy-build:build.sh`.

| Feature | Where it was | State |
| --- | --- | --- |
| Xorg configuration for the Tegra screen (`xorg.conf`, `10-monitor.conf`) | 359-455 | not needed: `switch-bsp` ships the same files |
| `IgnoreABI`, `Xwrapper.config`, an identity matrix for the touchscreens | 359-455 | not needed: the image installs the L4T Xorg it was built for, lightdm starts X as root, libinput's default matrix is the identity |
| On-screen keyboard (Onboard) in the XFCE autostart | 455-467 | dropped: the old build ended up removing that autostart; `onboard` is installed and is in the menu |
| `switch-rotate`: live rotation of screen and touch, saved between logins | 534-657 | ported: `nxd-xfce` (`/usr/bin/switch-rotate`) |
| Display wake-up hook on resume (`99-switch-display-wake.sh`) | 627-650 | not ported: resume brings the screen back without it on the Retrobox image; revisit if the XFCE one stays black |
| XFCE appearance, top and bottom panels, default applications, MIME associations | 658-890 | ported: `nxd-xfce` (`/etc/xdg/nxd`), without the indicator plugin (not installed) |
| `alternatives` links, `monitors.xml`, `.xsessionrc`, `.xinitrc`, an emptied `Desktop` | 830-1050 | not needed: the packages register the alternatives; lightdm starts the XFCE session |
| Applet autostart script (`rfkill unblock`, radios on, nm-applet, blueman, power manager) and duplicate autostart entries | 890-1030 | not needed: nm-applet, blueman and xfce4-power-manager ship their autostart entries; NetworkManager keeps the radios as they were |
| Wi-Fi scan helper in a terminal (`switch-wifi-scan.sh`) | 925-950 | dropped: nm-applet does it |
| `switch-sensors` (temperature and fan in the panel) | 1219 | ported: `nxd-xfce` (`/usr/bin/switch-sensors`) |
| `nvpmodel` indicator with fan modes and battery charge limit (`tools/nvpmodel_indicator`), its polkit policy, a udev rule that opens the fan's sysfs files to everyone | 1205-1270 | ported: the backend (a polkit policy for the user at the console, `/usr/lib/nxd/nvpmodel-helper`, `nxd-nvpmodel-restore.service`) in `nxd-common`, for both images (the Retrobox overlay changes the profile through `pkexec nvpmodel`); the indicator in `nxd-xfce`. Without the udev rule and the `chmod 666` of the old helper: what needs root goes through pkexec |
| NetworkManager owns the network (netplan delegation, networkd/resolved masked, `nvwifibt` removed) | 1053-1100, 1509 | partly: NetworkManager is installed; check the masks on a real boot |
| PulseAudio as a user service, GObject typelibs for the applets | 1182-1205 | not needed: Debian's pulseaudio enables its user service and socket; the typelibs come with the packages that need them |
| Suspend/resume hook: mute audio, resync the backlight, `udevadm trigger` for input | 1571-1633 | not ported: suspend and resume work on the Retrobox image without it, and re-triggering input recreates the pads |
| `tmpfiles.d` and an early service that repair permissions (sudo, `/home`, `/tmp`) | 1804-1857 | not needed: `mke2fs -d` keeps the owners and modes of the packages; revisit if a boot shows wrong permissions |
| Release versioning and changelog (`tools/bump_version.py`) | | ported to `scripts/next_version.py` |

The `nvpmodel` indicator is NVIDIA's, with CTCaer's changes, as in
`switch-bsp` (which ships the original, the `nvpmodel` Python module and the
icons the copy in `nxd-xfce` uses); its header and copyrights are kept. The
original only starts in GNOME, Unity, LXDE and KDE, and needs AppIndicator3,
which Debian 13 does not have: the copy falls back to Ayatana.
