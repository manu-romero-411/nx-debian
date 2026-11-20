#!/usr/bin/env python3
"""Next release tag and release notes of nx-debian.

The version is X.Y.Z, counted like this: Z goes up to 10, then it is 0 and Y
goes up; Y goes up to 10, then it is 0 and X goes up (1.0.10 -> 1.1.0,
1.10.10 -> 2.0.0). The first release is 1.0.0. The tag is "v" plus the
version, and is never one that already exists.

Prints the tag. With --notes FILE it also writes the release notes there: the
commits since the previous release. With --tag TAG (a release that is being
made from a tag that already exists) the tag is not computed: the notes are
those of TAG, since the release before it.

Run it from a clone that has all the tags (git fetch --tags).
"""

import argparse
import re
import subprocess
import sys

TAG_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
LIMIT = 10

Version = tuple[int, int, int]


def git(*args: str) -> str:
    """Output of a git command, or an empty string when it fails."""
    try:
        result = subprocess.run(
            ["git", *args],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return ""
    return result.stdout.strip()


def release_tags() -> dict[Version, str]:
    """The tags that are versions, by version."""
    tags: dict[Version, str] = {}
    for line in git("tag", "--list").splitlines():
        match = TAG_RE.match(line.strip())
        if match:
            version = (int(match[1]), int(match[2]), int(match[3]))
            tags.setdefault(version, line.strip())
    return tags


def bump(version: Version) -> Version:
    """The version after this one."""
    major, minor, patch = version
    patch += 1
    if patch > LIMIT:
        patch = 0
        minor += 1
        if minor > LIMIT:
            minor = 0
            major += 1
    return major, minor, patch


def next_version(existing: set[Version]) -> Version:
    """The first version after the newest one that is not taken."""
    if not existing:
        return 1, 0, 0
    version = max(existing)
    while True:
        version = bump(version)
        if version not in existing:
            return version


def notes(previous: str | None, version: str) -> str:
    """Release notes: the commits since the previous release."""
    span = f"{previous}..HEAD" if previous else "HEAD"
    log = git("log", span, "--pretty=format:- %s (`%h` by %an)")
    if not log:
        log = "- General updates and performance improvements."
    return f"""## nx-debian {version}

### Changes

{log}

### Installation

1. Download the installer of the variant you want
   (`switch-debian-13-trixie-<variant>-installer.zip`) and check it
   against `SHA256SUMS`. It does not include Hekate: the card must already
   have it (the one of your hats pack is fine).
2. Unzip it at the root of the microSD card (the FAT32 partition).
3. In Hekate: Tools -> Partition SD Card -> Flash Linux.
4. Reboot, More configs, Debian 13 Trixie. The filesystem grows to fill its
   partition on the first boot.

`*-packages.txt` lists what each image contains and `*-report.txt` where its
size comes from.
"""


def main() -> int:
    """Print the next tag; write the notes when asked."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n", maxsplit=1)[0])
    parser.add_argument("--notes", metavar="FILE", help="write the release notes here")
    parser.add_argument("--tag", help="use this existing tag instead of the next one")
    args = parser.parse_args()

    tags = release_tags()
    if args.tag:
        match = TAG_RE.match(args.tag)
        if not match:
            parser.error(f"{args.tag} is not a version tag")
        version = (int(match[1]), int(match[2]), int(match[3]))
        tag = args.tag
        older = [found for found in tags if found < version]
    else:
        version = next_version(set(tags))
        tag = f"v{version[0]}.{version[1]}.{version[2]}"
        older = list(tags)
    if args.notes:
        previous = tags[max(older)] if older else None
        with open(args.notes, "w", encoding="utf-8") as handle:
            handle.write(notes(previous, tag))
    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
