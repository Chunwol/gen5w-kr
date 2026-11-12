#!/system/bin/sh
# NEMESIS owns APK installation, including HMG's boot-property install guard.
umask 077
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
BASE=$(CDPATH= cd -- "$BASE" && pwd) || exit 1
HELPER=$BASE/bin/dex-patch
fail() { echo "portable install: $*" >&2; exit 1; }
plain() {
    case "$1" in /*) :;; *) return 1;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
    local part=$1
    while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
op() {
    if [ -n "${PORTABLE_TEST_PACKAGE_ADAPTER:-}" ]; then "$PORTABLE_TEST_PACKAGE_ADAPTER" "$@"; return $?; fi
    case "$1" in
    version) /system/xbin/nemesis version;;
    packages) /system/xbin/nemesis pkg-list;;
    healthy) [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop init.svc.zygote)" = running ];;
    installed) pm path "$2" | grep -q '^package:';;
    *) return 1;;
    esac
}
plain "$BASE" && plain "$HELPER" && [ -f "$HELPER" ] || fail 'unsafe bundle'
if [ -z "${PORTABLE_TEST_PACKAGE_ADAPTER:-}" ]; then
    case "$(id)" in uid=0\(*) :;; *) fail 'root required';; esac
    case "$BASE" in /data/*) :;; *) fail 'package must be staged in data';; esac
fi
version=$(op version) || fail 'NEMESIS version unavailable'
case "$version" in ''|*[!0-9.]*|.*|*.|*..*) fail 'unrecognized NEMESIS version';; esac
major=${version%%.*}; [ "$major" != "$version" ] || fail version
rest=${version#*.}; minor=${rest%%.*}; patch=${rest#*.}
[ "$patch" != "$rest" ] || patch=0
for number in "$major" "$minor" "$patch"; do
    case "$number" in ''|*[!0-9]*|0?*) fail version;; esac
    [ "${#number}" -le 6 ] || fail version
done
if [ "$major" -lt 1 ] || { [ "$major" = 1 ] && { [ "$minor" -lt 16 ] || { [ "$minor" = 16 ] && [ "$patch" -lt 7 ]; }; }; }; then
    fail 'NEMESIS 1.16.7 or newer is required'
fi
packages=$(op packages) || fail 'installed package inventory unavailable'
while IFS='|' read -r package rest; do
    case "$package" in gen5w.kr.bridge|gen5w.kr.core|wireless.projection|enhanced.projection|projection.tbt)
        fail "conflicting installation retained: $package";; esac
done <<EOF
$packages
EOF
op healthy || fail 'healthy Android required for installation'
for package in kr.gen5w.core kr.gen5w.wirelesshost; do
    op installed "$package" && fail 'existing authored app retained; remove its owning installation first'
done
plain "$BASE/SHA256SUMS" && [ -s "$BASE/SHA256SUMS" ] || fail hashes
chmod 755 "$HELPER" || fail helper
while read -r digest name extra; do
    [ -z "$extra" ] || fail hashes
    case "$digest" in ''|*[!a-f0-9]*) fail hashes;; esac
    [ "${#digest}" = 64 ] || fail hashes
    case "$name" in ''|/*|*[!a-zA-Z0-9_./-]*|*/../*|../*|*/./*|*//*) fail 'unsafe hash path';; esac
    plain "$BASE/$name" && [ -f "$BASE/$name" ] && [ "$("$HELPER" sha256 "$BASE/$name")" = "$digest" ] || fail 'bundle checksum differs'
    # NEMESIS's native extractor writes every member as 0644. copy_tree then
    # preserves these modes, so arm the verified worker scripts/helpers here.
    case "$name" in *.sh|bin/*) chmod 755 "$BASE/$name" || fail 'executable mode failed';; esac
done < "$BASE/SHA256SUMS"
echo 'portable install: package and NEMESIS verified; no system files changed'
