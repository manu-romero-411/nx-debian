#!/usr/bin/env bash
# Test of scripts/next_version.py in a scratch git repository.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NXD_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
SCRIPT="${NXD_ROOT}/scripts/next_version.py"

command -v git > /dev/null 2>&1 || { echo "skipped: no git"; exit 0; }
command -v python3 > /dev/null 2>&1 || { echo "skipped: no python3"; exit 0; }

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
expect() {
    local description="$1" want="$2" got
    got="$(cd "${repo}" && python3 -I "${SCRIPT}")"
    if [[ "${got}" == "${want}" ]]; then ok "${description}"; else bad "${description}: got ${got}, want ${want}"; fi
}

repo="$(mktemp -d)"
trap 'rm -rf "${repo}"' EXIT
git -C "${repo}" init -q
git -C "${repo}" config user.name test
git -C "${repo}" config user.email test@invalid
git -C "${repo}" config commit.gpgsign false
git -C "${repo}" config tag.gpgsign false
git -C "${repo}" commit -q --allow-empty -m "initial commit"

expect "the first release is v1.0.0" v1.0.0
git -C "${repo}" tag v1.0.0
expect "the patch goes up" v1.0.1
git -C "${repo}" tag not-a-version
git -C "${repo}" tag v1.0.10
expect "after .10 the minor goes up" v1.1.0
git -C "${repo}" tag v1.10.10
expect "after .10.10 the major goes up" v2.0.0
git -C "${repo}" tag v2.0.0
git -C "${repo}" tag v2.0.1
expect "the newest tag decides" v2.0.2

git -C "${repo}" commit -q --allow-empty -m "second change"
(cd "${repo}" && python3 -I "${SCRIPT}" --notes "${repo}/notes.md" > /dev/null)
if grep -q 'second change' "${repo}/notes.md" && ! grep -q 'initial commit' "${repo}/notes.md"; then
    ok "the notes list the commits since the last release"
else
    bad "the notes list the commits since the last release"
fi

git -C "${repo}" tag v2.0.2
(cd "${repo}" && python3 -I "${SCRIPT}" --tag v2.0.2 --notes "${repo}/tagged.md" > /dev/null)
if grep -q 'second change' "${repo}/tagged.md" && grep -q '^## nx-debian v2.0.2' "${repo}/tagged.md"; then
    ok "--tag writes the notes of an existing tag"
else
    bad "--tag writes the notes of an existing tag"
fi
if (cd "${repo}" && python3 -I "${SCRIPT}" --tag latest > /dev/null 2>&1); then
    bad "--tag refuses what is not a version"
else
    ok "--tag refuses what is not a version"
fi

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
