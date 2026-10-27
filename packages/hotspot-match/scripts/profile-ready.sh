#!/system/bin/sh
# Root-only publication: disk patch must have crossed a kernel boot boundary.
SCRIPT_DIR=${0%/*}
[ "$SCRIPT_DIR" != "$0" ] || SCRIPT_DIR=.
. "$SCRIPT_DIR/profile-common.sh"
clear_ready || exit 1
[ ! -e "$NOREBOOT" ] || exit 2
[ ! -e "$PROFILE_STOPPING" ] && [ ! -L "$PROFILE_STOPPING" ] || exit 2
inspect || exit $?
dependencies || exit $?
[ "$PROFILE_STATE" = patched ] && [ "$PROFILE_OWNED" = yes ] || exit 2
original "$STATE/original" || exit 1
read_boot || exit 1
[ -f "$STATE/applied-boot" ] && [ ! -L "$STATE/applied-boot" ] || exit 1
applied=$(cat "$STATE/applied-boot")
case "$applied" in *[!a-fA-F0-9-]*|'') exit 1;; esac
[ ${#applied} = 36 ] || exit 1
case "$applied" in ????????-????-????-????-????????????) ;; *) exit 1;; esac
[ "$PROFILE_BOOT" != "$applied" ] || exit 2
mkdir -p "$DATA/nemesis" || exit 1
{ echo ready; echo "$PROFILE_BOOT"; } > "$READY.tmp" &&
    chmod 644 "$READY.tmp" && chown 0:0 "$READY.tmp" &&
    mv "$READY.tmp" "$READY" || exit 1
exit 0
