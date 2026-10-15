#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMMON="$ROOT/iso/rootfs/usr/local/lib/pchh/common.sh"
MENU="$ROOT/iso/rootfs/usr/local/bin/pchh"
REPORT="$ROOT/iso/rootfs/usr/local/bin/pchh-report"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$*"; }

bash -n "$COMMON" "$MENU" "$REPORT" || fail "shell syntax"
pass "modified shell scripts parse"

test_root=$(mktemp -d "${TMPDIR:-/tmp}/pchh-stability.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
test_mountpoint="$test_root/usb"
mkdir -p "$test_mountpoint"
printf 'diagnostic output\n' > "$test_root/source.txt"

# Use the real save helper while replacing only hardware discovery and blkid.
. "$COMMON"
find_pchh_data_device() { printf '%s\n' /dev/mock-pchh-data; }
blkid() {
    case "$*" in
        *"-s TYPE"*) printf '%s\n' vfat ;;
        *) printf 'LABEL="PCHH_DATA" TYPE="vfat"\n' ;;
    esac
}
findmnt() { printf '%s\n' "$test_mountpoint"; }

save_result_to_usb "$test_root/source.txt" >/dev/null || fail "FAT32 save failed"
saved=$(find "$test_mountpoint" -type f -name 'PCHH-result-*.txt' -print -quit)
[ -n "$saved" ] || fail "Windows-friendly result filename missing"
cmp -s "$test_root/source.txt" "$saved" || fail "saved report content changed"
pass "report saves with readable filename and intact content"

blkid() { printf '%s\n' ext4; }
if save_result_to_usb "$test_root/source.txt" >/dev/null 2>&1; then
    fail "non-FAT32 volume was accepted"
fi
pass "non-FAT32 volume is rejected"

grep -q 'PCHH-Diagnose-.*\.txt' "$REPORT" || fail "diagnose filename contract missing"
grep -q 'Diagnose-all is complete' "$MENU" || fail "diagnose completion message missing"
pass "diagnose-all save contract is present"
