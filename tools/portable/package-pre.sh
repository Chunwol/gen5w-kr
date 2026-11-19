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
# NEMESIS --update removes the old app folder, hooks and APKs BEFORE this
# preinstall (pkg.c cmd_install). Never call the old package's scripts here;
# its state is judged by the verified staged state-reset.sh instead.
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
op() {
    if [ -n "${PORTABLE_TEST_PACKAGE_ADAPTER:-}" ]; then
        # 99 = not mocked: run the real implementation below.
        "$PORTABLE_TEST_PACKAGE_ADAPTER" "$@"; rc=$?
        [ "$rc" = 99 ] || return "$rc"
    fi
    case "$1" in
    version) /system/xbin/nemesis version;;
    packages) /system/xbin/nemesis pkg-list;;
    healthy) [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop init.svc.zygote)" = running ];;
    installed) pm path "$2" | grep -q '^package:';;
    retirement)
        marker=/data/local/gen5w-portable/boot/update-held
        [ -f "$marker" ] && [ ! -L "$marker" ] || { echo none; return 0; }
        IFS='|' read -r held_boot held_enabled held_overlay held_runtime extra < "$marker" || return 1
        [ -z "$extra" ] && [ "$held_boot" = "$(cat /proc/sys/kernel/random/boot_id)" ] || return 1
        echo held;;
    overlay-state)
        status=$(PORTABLE_HELPER=$HELPER "$SH" "$BASE/overlay.sh" status) || return 1
        case "$status" in *'state|retired-pending'*) echo retired-pending;; *'state|disabled'*) echo disabled;; *'state|expired'*) echo expired;; *'state|prepared'*) echo prepared;; *'state|retired'*) echo retired;; *'state|committed'*) echo active;; *) echo unknown; return 1;; esac;;
    state-reset) PORTABLE_HELPER=$HELPER "$SH" "$BASE/state-reset.sh";;
    *) return 1;;
    esac
}
plain "$BASE" && plain "$HELPER" && [ -f "$HELPER" ] || fail 'unsafe bundle'
if [ -z "${PORTABLE_TEST_PACKAGE_ADAPTER:-}" ]; then
    case "$(id)" in uid=0\(*) :;; *) fail 'root required';; esac
    case "$BASE" in /data/*) :;; *) fail 'package must be staged in data';; esac
fi
# Verify and arm the staged bundle first: the old package's state is read with
# these staged scripts when NEMESIS has already removed the old folder.
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
own_update=0
while IFS='|' read -r package rest; do
    [ "$package" != gen5w.kr.portable ] || own_update=1
    case "$package" in gen5w.kr.bridge|gen5w.kr.core|wireless.projection|enhanced.projection|projection.tbt)
        fail "conflicting installation retained: $package";; esac
done <<EOF
$packages
EOF
op healthy || fail 'healthy Android required for installation'
for package in kr.gen5w.core kr.gen5w.wirelesshost; do
    if op installed "$package"; then
        [ "$own_update" = 1 ] || fail 'existing authored app retained; remove its owning installation first'
    fi
done
# Read-only admissions end here; the retirement below is the only change.
# Two paths only. A same-boot update handoff (an enabled persistent package
# retired its live view through its own code, before NEMESIS) is continued;
# anything else must be inactive and is retired by state-reset.sh.
retirement=$(op retirement) || fail 'existing update-handoff state is unreadable'
if [ "$retirement" = held ]; then
    [ "$own_update" = 1 ] || fail 'update handoff recorded without an installed package'
    overlay_state=$(op overlay-state) || fail 'existing overlay state is unreadable'
    case "$overlay_state" in retired-pending|disabled|expired|prepared|retired) :;; *) fail 'existing overlays are not held or inactive';; esac
else
    op state-reset || fail 'earlier portable state is not inactive or could not be retired'
fi
echo 'portable install: package and NEMESIS verified; no system files changed'
