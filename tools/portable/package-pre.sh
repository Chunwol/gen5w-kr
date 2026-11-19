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
# NEMESIS --update runs the old preuninstall/postuninstall, uninstalls the old
# APKs and removes the old app directory BEFORE this preinstall (pkg.c
# cmd_install: rm_rf(oldroot); "update replacing"). The old scripts are then
# gone (vehicle 2026-11-19: boot.sh: No such file). Their status commands only
# read /data/local/gen5w-portable, so the staged copies read the same state.
OLD_APP=${PORTABLE_TEST_OLD_APP:-/data/nemesis/apps/gen5w.kr.portable}
SH=${PORTABLE_TEST_SH:-/system/bin/sh}
owned() {
    if [ -f "$OLD_APP/$1" ] && [ ! -L "$OLD_APP/$1" ]; then print -r -- "$OLD_APP/$1"
    else print -r -- "$BASE/$1"; fi
}
old_removed() { [ ! -e "$OLD_APP/boot.sh" ] && [ ! -L "$OLD_APP/boot.sh" ]; }
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
        status=$(PORTABLE_HELPER=$HELPER "$SH" "$(owned overlay.sh)" status) || return 1
        case "$status" in *'state|retired-pending'*) echo retired-pending;; *'state|disabled'*) echo disabled;; *'state|expired'*) echo expired;; *'state|prepared'*) echo prepared;; *'state|retired'*) echo retired;; *'state|committed'*) echo active;; *) echo unknown; return 1;; esac;;
    old-status)
        "$SH" "$(owned boot.sh)" status;;
    legacy-quiescent)
        grep -q '/data/local/gen5w-portable' "${PORTABLE_TEST_MOUNTS:-/proc/mounts}" && return 1
        for key in wrap.com.daudio.app.dipo wrap.com.google.android.project; do [ -z "$(getprop "$key" 2>/dev/null)" ] || return 1; done
        runtime=$(PORTABLE_HELPER=$HELPER "$SH" "$(owned runtime.sh)" status) || return 1
        case "$runtime" in 'runtime|disabled'|'runtime|expired') :;; *) return 1;; esac;;
    retire-update)
        # Retiring a live view needs the owning (old) code; never improvise it.
        old_removed && return 1
        "$SH" "$OLD_APP/boot.sh" update-retire;;
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
if [ "$own_update" = 1 ]; then
    retirement=$(op retirement) || fail 'existing update-handoff state is unreadable'
    if [ "$retirement" != held ]; then
        prior_status=$(op old-status) || fail 'existing package state is unreadable'
        if grep -qx 'enabled|1' <<EOF
$prior_status
EOF
        then
            op retire-update || fail 'existing package could not safely retire its live view for update'
            retirement=$(op retirement) || fail 'existing update-handoff state is unreadable'
        else
            grep -qx 'enabled|0' <<EOF
$prior_status
EOF
            op legacy-quiescent || fail 'legacy package is not quiescent; disable it through its owning path before update'
            retirement=inactive
        fi
    fi
    if [ "$retirement" = held ]; then
        overlay_state=$(op overlay-state) || fail 'existing overlay state is unreadable'
        case "$overlay_state" in retired-pending|disabled|expired|prepared|retired) :;; *) fail 'existing overlays are not held or inactive';; esac
    else [ "$retirement" = inactive ] || fail 'safe update handoff was not recorded'; fi
fi
for package in kr.gen5w.core kr.gen5w.wirelesshost; do
    if op installed "$package"; then
        [ "$own_update" = 1 ] || fail 'existing authored app retained; remove its owning installation first'
    fi
done
echo 'portable install: package and NEMESIS verified; no system files changed'
