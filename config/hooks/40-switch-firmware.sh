#!/bin/sh
# Runs inside the rootfs. The Switch's Wi-Fi/Bluetooth chip asks for firmware
# files under other names than the ones the L4T packages ship: link them, and
# rebuild the module dependencies of the L4T kernel (4.9.140-l4t).
# Everything is conditional: a variant without those files is left alone.
set -eu

fwdir=/usr/lib/firmware/brcm
if [ -d "${fwdir}" ]; then
    if [ -e "${fwdir}/brcmfmac4356A3-pcie.bin" ]; then
        ln -sf brcmfmac4356A3-pcie.bin "${fwdir}/brcmfmac4356-pcie.bin"
    fi
    if [ -e "${fwdir}/brcmfmac4356A3-pcie.txt" ]; then
        ln -sf brcmfmac4356A3-pcie.txt "${fwdir}/brcmfmac4356-pcie.txt"
        for model in switch odin vali fric; do
            cp -f "${fwdir}/brcmfmac4356A3-pcie.txt" "${fwdir}/brcmfmac4356-pcie.nintendo,${model}.txt"
        done
    fi
    if [ -e "${fwdir}/BCM4356A3.hcd" ]; then
        ln -sf BCM4356A3.hcd "${fwdir}/bcm4356.hcd"
    fi
fi

for moddir in /usr/lib/modules/*l4t*; do
    [ -d "${moddir}" ] || continue
    if command -v depmod > /dev/null 2>&1; then
        depmod -a "$(basename "${moddir}")"
    fi
done
