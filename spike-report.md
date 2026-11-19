# nxd spike report

- date: 2026-11-18T21:01:31Z
- Debian: trixie (arm64) from http://deb.debian.org/debian
- L4T: https://theofficialgman.github.io/l4t-debs/ l4t, components tried: jammy noble
- variant: xfce (71 packages, 19 from L4T)

## Names trixie does not have

None: all 52 Debian-side names exist.

## Packages that change the plan (Debian trixie)

```
xfce4-volumed-pulse          (none)
xubuntu-default-settings     (none)
onboard                      1.4.1-10  500  http://deb.debian.org/debian trixie/main
openbox                      3.6.1-12+b2  500  http://deb.debian.org/debian trixie/main
xfce4-genmon-plugin          4.1.1-1+b3  500  http://deb.debian.org/debian trixie/main
systemd-zram-generator       1.2.1-2  500  http://deb.debian.org/debian trixie/main
joycond                      (none)
nvpmodel                     (none)
```

## debian: OK (521 packages)

## l4t-jammy-nopin: OK (593 packages)

Where the L4T packages come from (version, priority, source):

```
joycond                        0.6-1  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-3d-core             32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-configs             32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-core                32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-firmware            32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-init                32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-multimedia          32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-multimedia-utils    32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-x11                 32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-alsa-ucm2               1.0-1  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-bsp                     5.1.2-34  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-dock-handler            3.0-2  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-joystick-mouse          1.2-1  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-touch-rules             2.0  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-l4t-configs             1.5-14  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-core              2:21.1.16-1.3+deb13u3  500  http://deb.debian.org/debian trixie/main
xserver-xorg-input-libinput    1.5.0-1  500  http://deb.debian.org/debian trixie/main
xserver-xorg-input-joystick    2:1.6.4-1.3  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-video-fbdev       1:0.5.0-2+b2  500  http://deb.debian.org/debian trixie/main
libpcre3                       2:8.39-15  100  http://deb.debian.org/debian bookworm/main
```

The packages that change the plan, with this repository:

```
xfce4-volumed-pulse            (none)
xubuntu-default-settings       (none)
onboard                        1.4.1-10  500  http://deb.debian.org/debian trixie/main
openbox                        3.6.1-12+b2  500  http://deb.debian.org/debian trixie/main
xfce4-genmon-plugin            4.1.1-1+b3  500  http://deb.debian.org/debian trixie/main
systemd-zram-generator         1.2.1-2  500  http://deb.debian.org/debian trixie/main
joycond                        0.6-1  500  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvpmodel                       (none)
```

## l4t-jammy-pin: OK (592 packages)

Where the L4T packages come from (version, priority, source):

```
joycond                        0.6-1  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-3d-core             32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-configs             32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-core                32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-firmware            32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-init                32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-multimedia          32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-multimedia-utils    32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvidia-l4t-x11                 32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-alsa-ucm2               1.0-1  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-bsp                     5.1.2-34  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-dock-handler            3.0-2  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-joystick-mouse          1.2-1  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-touch-rules             2.0  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
switch-l4t-configs             1.5-14  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-core              2:1.20.13-1ubuntu1~20.04.8  1001  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-input-libinput    1.2.1-1  1001  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-input-joystick    2:1.6.4-1.3  1001  https://theofficialgman.github.io/l4t-debs l4t/jammy
xserver-xorg-video-fbdev       1:0.5.0-1ubuntu1  1001  https://theofficialgman.github.io/l4t-debs l4t/jammy
libpcre3                       2:8.39-15  100  http://deb.debian.org/debian bookworm/main
```

The packages that change the plan, with this repository:

```
xfce4-volumed-pulse            (none)
xubuntu-default-settings       (none)
onboard                        1.4.1-10  500  http://deb.debian.org/debian trixie/main
openbox                        3.6.1-12+b2  500  http://deb.debian.org/debian trixie/main
xfce4-genmon-plugin            4.1.1-1+b3  500  http://deb.debian.org/debian trixie/main
systemd-zram-generator         1.2.1-2  500  http://deb.debian.org/debian trixie/main
joycond                        0.6-1  100  https://theofficialgman.github.io/l4t-debs l4t/jammy
nvpmodel                       (none)
```

## l4t-noble-nopin: UNMET DEPENDENCIES

```
E: Unable to correct problems, you have held broken packages.
E: The following information from --solver 3.0 may provide additional context:
```

Unmet dependencies:

```
 onboard : Depends: python3 (< 3.13) but 3.13.5-1 is to be installed
```

Where the L4T packages come from (version, priority, source):

```
joycond                        0.6-1  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-3d-core             32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-configs             32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-core                32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-firmware            32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-init                32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-multimedia          32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-multimedia-utils    32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-x11                 32.3.1-20191209225816  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-alsa-ucm2               1.0-1+24.04  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-bsp                     5.1.2-34+24.04  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-dock-handler            3.0-2  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-joystick-mouse          1.2-1  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-touch-rules             2.0  500  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-l4t-configs             1.5-18+24.04  500  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-core              2:21.1.16-1.3+deb13u3  500  http://deb.debian.org/debian trixie/main
xserver-xorg-input-libinput    1.5.0-1  500  http://deb.debian.org/debian trixie/main
xserver-xorg-input-joystick    2:1.6.4-1.3  500  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-video-fbdev       1:0.5.0-2+b2  500  http://deb.debian.org/debian trixie/main
libpcre3                       2:8.39-15  100  http://deb.debian.org/debian bookworm/main
```

The packages that change the plan, with this repository:

```
xfce4-volumed-pulse            (none)
xubuntu-default-settings       (none)
onboard                        1.4.2-1  500  https://theofficialgman.github.io/l4t-debs l4t/noble
openbox                        3.6.1-12+b2  500  http://deb.debian.org/debian trixie/main
xfce4-genmon-plugin            4.1.1-1+b3  500  http://deb.debian.org/debian trixie/main
systemd-zram-generator         1.2.1-2  500  http://deb.debian.org/debian trixie/main
joycond                        0.6-1  500  https://theofficialgman.github.io/l4t-debs l4t/noble
nvpmodel                       (none)
```

## l4t-noble-pin: OK (592 packages)

Where the L4T packages come from (version, priority, source):

```
joycond                        0.6-1  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-3d-core             32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-configs             32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-core                32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-firmware            32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-init                32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-multimedia          32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-multimedia-utils    32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvidia-l4t-x11                 32.3.1-20191209225816  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-alsa-ucm2               1.0-1+24.04  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-bsp                     5.1.2-34+24.04  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-dock-handler            3.0-2  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-joystick-mouse          1.2-1  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-touch-rules             2.0  100  https://theofficialgman.github.io/l4t-debs l4t/noble
switch-l4t-configs             1.5-18+24.04  100  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-core              2:1.20.13-1ubuntu1~20.04.8  1001  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-input-libinput    1.2.1-1  1001  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-input-joystick    2:1.6.4-1.3  1001  https://theofficialgman.github.io/l4t-debs l4t/noble
xserver-xorg-video-fbdev       1:0.5.0-1ubuntu1  1001  https://theofficialgman.github.io/l4t-debs l4t/noble
libpcre3                       2:8.39-15  100  http://deb.debian.org/debian bookworm/main
```

The packages that change the plan, with this repository:

```
xfce4-volumed-pulse            (none)
xubuntu-default-settings       (none)
onboard                        1.4.1-10  500  http://deb.debian.org/debian trixie/main
openbox                        3.6.1-12+b2  500  http://deb.debian.org/debian trixie/main
xfce4-genmon-plugin            4.1.1-1+b3  500  http://deb.debian.org/debian trixie/main
systemd-zram-generator         1.2.1-2  500  http://deb.debian.org/debian trixie/main
joycond                        0.6-1  100  https://theofficialgman.github.io/l4t-debs l4t/noble
nvpmodel                       (none)
```

## What the L4T packages (noble) ship

```
--- usr/sbin/nvpmodel$
switch-bsp: ./usr/sbin/nvpmodel
--- nvpmodel.*\.conf$
switch-bsp: ./etc/nvpmodel/nvpmodel_charging.conf
switch-bsp: ./etc/nvpmodel/nvpmodel_t210.conf
switch-bsp: ./etc/nvpmodel/nvpmodel_t210b01.conf
--- polkit-1/actions/
nvidia-l4t-init: ./usr/share/polkit-1/actions/
nvidia-l4t-init: ./usr/share/polkit-1/actions/com.nvidia.pkexec.nvpmodel.policy
nvidia-l4t-init: ./usr/share/polkit-1/actions/com.nvidia.pkexec.tegrastats.policy
switch-dock-handler: ./usr/share/polkit-1/actions/
switch-dock-handler: ./usr/share/polkit-1/actions/org.switchroot.dock-hotplug.policy
switch-l4t-configs: ./usr/share/polkit-1/actions/
switch-l4t-configs: ./usr/share/polkit-1/actions/com.nvidia.pkexec.membench.policy
switch-l4t-configs: ./usr/share/polkit-1/actions/com.nvidia.pkexec.tegrastats-l4t.policy
switch-l4t-configs: ./usr/share/polkit-1/actions/org.switchroot.r2c.policy
--- usr/lib/xorg/Xorg$
xserver-xorg-core: ./usr/lib/xorg/Xorg
--- nvidia_drv\.so$
nvidia-l4t-3d-core: ./usr/lib/xorg/modules/drivers/nvidia_drv.so
--- bootstack/
switch-bsp: ./opt/switchroot/bootstack/
switch-bsp: ./opt/switchroot/bootstack/.cleanup
switch-bsp: ./opt/switchroot/bootstack/README_CONFIG.txt
switch-bsp: ./opt/switchroot/bootstack/bl31.bin
switch-bsp: ./opt/switchroot/bootstack/bl33.bin
switch-bsp: ./opt/switchroot/bootstack/boot.scr
--- modules\.tar
switch-bsp: ./opt/switchroot/modules.tar.gz
--- ucm2/
switch-alsa-ucm2: ./usr/share/alsa/ucm2/
switch-alsa-ucm2: ./usr/share/alsa/ucm2/Tegra/
switch-alsa-ucm2: ./usr/share/alsa/ucm2/Tegra/tegra-hda/
switch-alsa-ucm2: ./usr/share/alsa/ucm2/Tegra/tegra-hda/tegra-hda-HiFi.conf
switch-alsa-ucm2: ./usr/share/alsa/ucm2/Tegra/tegra-snd-t210ref-mobile-rt565x/
switch-alsa-ucm2: ./usr/share/alsa/ucm2/Tegra/tegra-snd-t210ref-mobile-rt565x/HiFi.conf
--- udev/rules\.d/
joycond: ./lib/udev/rules.d/
joycond: ./lib/udev/rules.d/72-joycond.rules
joycond: ./lib/udev/rules.d/89-joycond.rules
nvidia-l4t-init: ./etc/udev/rules.d/
nvidia-l4t-init: ./etc/udev/rules.d/90-alsa-asound-tegra.rules
nvidia-l4t-init: ./etc/udev/rules.d/91-xorg-conf-tegra.rules
nvidia-l4t-init: ./etc/udev/rules.d/92-hdmi-audio-tegra.rules
nvidia-l4t-init: ./etc/udev/rules.d/99-nv-l4t-usb-device-mode.rules
nvidia-l4t-init: ./etc/udev/rules.d/99-nv-ufs-mount.rules
switch-bsp: ./etc/udev/rules.d/
switch-bsp: ./etc/udev/rules.d/99-nv-ufs-mount.rules
switch-bsp: ./etc/udev/rules.d/99-tegra-mmc-ra.rules
switch-dock-handler: ./lib/udev/rules.d/
switch-dock-handler: ./lib/udev/rules.d/92-dp-switch.rules
switch-dock-handler: ./lib/udev/rules.d/94-pd-switch.rules
xserver-xorg-core: ./usr/lib/udev/rules.d/
xserver-xorg-core: ./usr/lib/udev/rules.d/64-xorg-xkb.rules
--- xorg\.conf\.d/
switch-bsp: ./etc/X11/xorg.conf.d/
switch-bsp: ./etc/X11/xorg.conf.d/10-monitor.conf
switch-joystick-mouse: ./usr/share/X11/xorg.conf.d/
switch-joystick-mouse: ./usr/share/X11/xorg.conf.d/50-joystick.conf
switch-joystick-mouse: ./usr/share/X11/xorg.conf.d/51-joystick-others.conf
xserver-xorg-core: ./usr/share/X11/xorg.conf.d/
xserver-xorg-core: ./usr/share/X11/xorg.conf.d/10-quirks.conf
xserver-xorg-input-libinput: ./usr/share/X11/xorg.conf.d/
xserver-xorg-input-libinput: ./usr/share/X11/xorg.conf.d/40-libinput.conf
--- systemd/system/.*\.service$
joycond: ./etc/systemd/system/joycond.service
nvidia-l4t-configs: ./etc/systemd/system/nvweston.service
nvidia-l4t-configs: ./etc/systemd/system/nvpmodel.service
nvidia-l4t-configs: ./etc/systemd/system/nvfb-early.service
nvidia-l4t-configs: ./etc/systemd/system/multi-user.target.wants/nvweston.service
nvidia-l4t-configs: ./etc/systemd/system/multi-user.target.wants/nvfb-early.service
nvidia-l4t-firmware: ./etc/systemd/system/nvwifibt.service
nvidia-l4t-init: ./etc/systemd/system/nv.service
nvidia-l4t-init: ./etc/systemd/system/nvfb.service
nvidia-l4t-init: ./etc/systemd/system/nvgetty.service
nvidia-l4t-init: ./etc/systemd/system/nvmemwarning.service
nvidia-l4t-init: ./etc/systemd/system/nvphs.service
nvidia-l4t-init: ./etc/systemd/system/nvs-service.service
switch-bsp: ./etc/systemd/system/multi-user.target.wants/nvpmodel.service
--- opt/switchroot/
switch-bsp: ./opt/switchroot/
switch-bsp: ./opt/switchroot/L4T-noble.ini
switch-bsp: ./opt/switchroot/bootloader.bin
switch-bsp: ./opt/switchroot/bootstack/
switch-bsp: ./opt/switchroot/bootstack/.cleanup
switch-bsp: ./opt/switchroot/bootstack/README_CONFIG.txt
```

