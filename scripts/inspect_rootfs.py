#!/usr/bin/env python3
"""Report what ended up inside a rootfs tarball built by ``nxd rootfs``.

It only reads the tarball (no root needed). The report answers: how big is
it, which packages weigh the most, who pulled in the packages nobody asked
for, and whether the image is clean (machine-id, build flags, apt sources).
"""

import argparse
import re
import sys
import tarfile
from collections import defaultdict

# Packages worth asking "who needs this?" about when nothing explicit does.
DEFAULT_WHY = (
    "imagemagick", "yad", "cpp", "sudo", "python3", "v4l-utils", "libgs10",
    "systemd-timesyncd", "wpasupplicant", "network-manager", "bluez",
    "pulseaudio", "polkitd", "openbox", "lightdm", "kmod", "alsa-utils",
)

# Left behind by the build; none of them may be in the image.
BUILD_FLAGS = (
    "opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall",
    "opt/switchroot/image_prep",
)


def norm(name):
    """Strip the leading ``./`` of a tar member name."""
    return name[2:] if name.startswith("./") else name.lstrip("/")


def read_member(tar, path):
    """Return the text of a regular file of the tarball, or None."""
    try:
        member = tar.getmember("./" + path)
    except KeyError:
        try:
            member = tar.getmember(path)
        except KeyError:
            return None
    if not member.isfile():
        return None
    extracted = tar.extractfile(member)
    if extracted is None:
        return None
    return extracted.read().decode("utf-8", "replace")


def parse_status(text):
    """Parse a dpkg status file into {name: {field: value}} (installed only)."""
    packages = {}
    for stanza in re.split(r"\n\n+", text):
        fields = {}
        key = None
        for line in stanza.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, value = line.partition(":")
                fields[key] = value.strip()
        if "Package" in fields and fields.get("Status", "").endswith("installed"):
            packages[fields["Package"]] = fields
    return packages


def dependency_names(fields):
    """Names in Depends and Pre-Depends, alternatives included."""
    names = set()
    for field in ("Depends", "Pre-Depends"):
        for clause in fields.get(field, "").split(","):
            for alternative in clause.split("|"):
                name = alternative.strip().split(" ")[0].split(":")[0]
                if name:
                    names.add(name)
    return names


def reverse_dependencies(packages):
    """Map package name -> set of installed packages depending on it."""
    provided = defaultdict(set)
    for name, fields in packages.items():
        provided[name].add(name)
        for clause in fields.get("Provides", "").split(","):
            virtual = clause.strip().split(" ")[0].split(":")[0]
            if virtual:
                provided[virtual].add(name)
    reverse = defaultdict(set)
    for name, fields in packages.items():
        for dep in dependency_names(fields):
            for target in provided.get(dep, ()):
                if target != name:
                    reverse[target].add(name)
    return reverse


def section(title):
    """Print a section header."""
    print(f"\n## {title}\n")


def report_sizes(tarball, packages, top):
    """Total sizes and the heaviest packages."""
    section("Size")
    with open(tarball, "rb") as handle:
        handle.seek(0, 2)
        print(f"tarball: {handle.tell() / 1048576:.0f} MiB")
    sizes = {n: int(f.get("Installed-Size", "0") or 0) for n, f in packages.items()}
    print(f"packages: {len(packages)}, installed size: {sum(sizes.values()) / 1024:.0f} MiB")
    print(f"\nHeaviest {top}:")
    for name, size in sorted(sizes.items(), key=lambda item: -item[1])[:top]:
        print(f"  {size / 1024:8.1f} MiB  {name}")


def report_why(packages, explicit, names):
    """Who depends on each name, and whether it was asked for."""
    section("Who pulls these in")
    reverse = reverse_dependencies(packages)
    for name in dict.fromkeys(names):
        if name not in packages:
            continue
        asked = "asked for" if name in explicit else "pulled in"
        users = sorted(reverse.get(name, ()))
        print(f"{name} ({asked}): {', '.join(users) if users else '-'}")


def report_hygiene(tar, members):
    """Machine-id, build flags, apt state."""
    section("Image hygiene")
    machine_id = read_member(tar, "etc/machine-id")
    print(f"machine-id empty: {machine_id == ''}")
    firstboot = members.get("etc/systemd/system/systemd-firstboot.service")
    masked = firstboot is not None and firstboot.linkname == "/dev/null"
    print(f"systemd-firstboot masked: {masked}")
    for flag in BUILD_FLAGS:
        print(f"build flag gone ({flag}): {flag not in members}")
    for path in ("etc/apt/sources.list.d/nxd-l4t.sources",
                 "etc/apt/sources.list.d/nxd-compat.sources",
                 "etc/apt/preferences.d/10-nxd-l4t.pref"):
        print(f"present {path}: {path in members}")
    lists = sum(m.size for n, m in members.items() if n.startswith("var/lib/apt/lists/"))
    cache = sum(m.size for n, m in members.items() if n.startswith("var/cache/apt/"))
    print(f"apt lists: {lists / 1048576:.1f} MiB, apt cache: {cache / 1048576:.1f} MiB")
    tmp = [n for n in members if n.startswith("tmp/") and n != "tmp/"]
    print(f"left in /tmp: {tmp if tmp else 'nothing'}")


def report_boot(members):
    """Boot files, kernel modules and headers."""
    section("Boot and kernel")
    for name in sorted(members):
        member = members[name]
        if name.startswith("opt/switchroot/") and member.isfile():
            print(f"  {member.size / 1048576:8.2f} MiB  {name}")
    for prefix, label in (("lib/modules/", "kernel modules"),
                          ("usr/lib/modules/", "kernel modules (usr)"),
                          ("usr/src/", "usr/src (kernel headers)")):
        total = sum(m.size for n, m in members.items() if n.startswith(prefix))
        if total:
            print(f"  {total / 1048576:8.1f} MiB  {label}")
    modules = sorted({n.split("/")[2] for n in members
                      if n.startswith(("lib/modules/", "usr/lib/modules/")) and n.count("/") > 2})
    print(f"  kernel versions: {', '.join(modules) if modules else 'none'}")


def report_services(members):
    """Services enabled through *.wants links."""
    section("Enabled services")
    enabled = defaultdict(list)
    for name, member in members.items():
        match = re.match(r"etc/systemd/(system|user)/([^/]+\.wants)/([^/]+)$", name)
        if match and member.issym():
            enabled[f"{match.group(1)}/{match.group(2)}"].append(match.group(3))
    for target in sorted(enabled):
        print(f"{target}: {', '.join(sorted(enabled[target]))}")


def report_users(tar):
    """Accounts with a login shell or a real uid."""
    section("Accounts")
    passwd = read_member(tar, "etc/passwd") or ""
    for line in passwd.splitlines():
        parts = line.split(":")
        if len(parts) >= 7 and (int(parts[2]) >= 1000 or parts[2] == "0"):
            print(f"  {parts[0]} uid={parts[2]} shell={parts[6]}")


def main():
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tarball", help="rootfs.tar built by nxd rootfs")
    parser.add_argument("--packages", help="file with the explicit package names")
    parser.add_argument("--why", action="append", default=[],
                        help="also explain this package (repeatable)")
    parser.add_argument("--top", type=int, default=25, help="heaviest packages to list")
    args = parser.parse_args()

    explicit = set()
    if args.packages:
        with open(args.packages, encoding="utf-8") as handle:
            explicit = {line.strip() for line in handle if line.strip()}

    with tarfile.open(args.tarball) as tar:
        members = {norm(m.name).rstrip("/"): m for m in tar.getmembers()}
        status = read_member(tar, "var/lib/dpkg/status")
        if status is None:
            print("no dpkg status in the tarball", file=sys.stderr)
            return 1
        packages = parse_status(status)
        print(f"# nxd rootfs report: {args.tarball}")
        report_sizes(args.tarball, packages, args.top)
        report_why(packages, explicit, list(DEFAULT_WHY) + args.why)
        report_hygiene(tar, members)
        report_boot(members)
        report_services(members)
        report_users(tar)
    return 0


if __name__ == "__main__":
    sys.exit(main())
