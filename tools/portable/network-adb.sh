#!/system/bin/sh
# Own only the legacy switch (1 -> 0) and, if empty, port (empty -> 5555).
# Journal and this standalone recovery helper survive package removal.
umask 077
ROOT=${PORTABLE_TEST_ROOT:-}
STATE=$ROOT/data/local/gen5w-portable/network-adb
LEGACY=persist.service.adb.tcp.enable
PORT=persist.adb.tcp.port
fail() { echo "network-adb: $*" >&2; exit 1; }
# Refuse symlinks in every ancestor, including a fixture prefix.
p=$STATE
while [ "$p" != / ] && [ -n "$p" ]; do
 [ ! -L "$p" ] || fail "symlink: $p"
 p=${p%/*}; [ -n "$p" ] || p=/
done
mkdir -p "$STATE" || exit 1
for f in journal journal.new restore.sh restore.sh.new lock; do
 [ ! -L "$STATE/$f" ] || fail "symlink: $f"
done
# Publish a complete owner atomically: no empty-directory lock crash window.
process_key() {
 local pid=$1 line rest count=0
 case "$pid" in ''|*[!0-9]*) return 1;; esac
 IFS= read -r line < "/proc/$pid/stat" || return 1
 rest=${line##*) }; [ "$rest" != "$line" ] || return 1
 set -- $rest; [ "$#" -ge 20 ] || return 1
 case "$1" in Z|X|x) return 1;; esac
 while [ "$count" -lt 19 ]; do shift; count=$((count+1)); done
 print -r -- "$pid:$1"
}
boot=$(cat /proc/sys/kernel/random/boot_id) || exit 1
key=$(process_key $$) || exit 1
token=$boot'|'$key
candidate=$STATE/owner-$boot-${key/:/-}
[ ! -e "$candidate" ] && [ ! -L "$candidate" ] || fail 'unsafe candidate'
print -r -- "$token" > "$candidate" || exit 1
trap 'rm -f "$candidate"' EXIT
if ! ln "$candidate" "$STATE/lock" 2>/dev/null; then
 [ -f "$STATE/lock" ] && [ ! -L "$STATE/lock" ] || fail 'invalid lock'
 owner=$(cat "$STATE/lock") || exit 1
 IFS='|' read -r owner_boot owner_key <<EOF
$owner
EOF
 owner_pid=${owner_key%%:*}
 case "$owner_pid" in ''|*[!0-9]*) fail 'invalid lock owner';; esac
 if [ "$owner_boot" = "$boot" ] && [ "$(process_key "$owner_pid" 2>/dev/null)" = "$owner_key" ]; then fail 'busy'; fi
 [ "$(cat "$STATE/lock")" = "$owner" ] || fail 'lock changed'
 rm -f "$STATE/lock" && ln "$candidate" "$STATE/lock" || exit 1
fi
trap '[ "$(cat "$STATE/lock" 2>/dev/null)" != "$token" ] || rm -f "$STATE/lock"; rm -f "$candidate"' EXIT
read_journal() {
 [ -f "$STATE/journal" ] || return 1
 { IFS= read -r version && IFS= read -r before_legacy && IFS= read -r own_port && IFS= read -r before_port && IFS= read -r current_port && ! IFS= read -r extra; } < "$STATE/journal" || fail 'invalid journal'
 [ "$version" = network-adb-v1 ] && [ "$before_legacy" = 1 ] || fail 'invalid journal'
 case "$own_port" in 0) [ "$before_port" = "$current_port" ] || fail 'invalid port snapshot';; 1) [ -z "$before_port" ] && [ "$current_port" = 5555 ] || fail 'invalid port snapshot';; *) fail 'invalid journal';; esac
}
write_prop() {
 setprop "$1" "$2" && [ "$(getprop "$1")" = "$2" ]
}
restore() {
 [ -e "$STATE/journal" ] || return 0
 read_journal || return 1
 failed=0
 # CAS restore never overwrites a later operator's differing setting.
 if [ "$own_port" = 1 ] && [ "$(getprop "$PORT")" = 5555 ]; then write_prop "$PORT" '' || failed=1; fi
 if [ "$failed" = 0 ] && [ "$(getprop "$LEGACY")" = 0 ]; then write_prop "$LEGACY" 1 || failed=1; fi
 [ "$failed" = 0 ] || return 1
 rm -f "$STATE/journal"
}
case "${1:-}" in
apply)
 if [ -e "$STATE/journal" ]; then
  read_journal || exit 1
  legacy_now=$(getprop "$LEGACY")
  port_now=$(getprop "$PORT")
  if [ "$legacy_now" = 0 ] && [ "$port_now" = "$current_port" ]; then exit 0; fi
  # Interrupted apply: complete only when current values match owned snapshots.
  if [ "$legacy_now" = 1 ] && { [ "$port_now" = "$current_port" ] || [ "$port_now" = "$before_port" ]; }; then
   if [ "$own_port" = 1 ] && [ -z "$port_now" ]; then write_prop "$PORT" 5555 || { restore; exit 1; }; fi
   write_prop "$LEGACY" 0 || { restore; exit 1; }
   exit 0
  fi
  # A differing operator value wins; release our remaining owned changes.
  restore || exit 1
  exit 0
 fi
 [ "$(getprop "$LEGACY")" = 1 ] || exit 0
 before_port=$(getprop "$PORT") || exit 1
 case "$before_port" in *'
'*) fail 'multiline port';; esac
 own_port=0; current_port=$before_port
 [ -n "$before_port" ] || { own_port=1; current_port=5555; }
 # Retain recovery before recording intent and before the first property write.
 if [ "$0" != "$STATE/restore.sh" ]; then
  cp "$0" "$STATE/restore.sh.new" && chmod 700 "$STATE/restore.sh.new" && mv "$STATE/restore.sh.new" "$STATE/restore.sh" || exit 1
 fi
 { print -r -- network-adb-v1; print -r -- 1; print -r -- "$own_port"; print -r -- "$before_port"; print -r -- "$current_port"; } > "$STATE/journal.new" && mv "$STATE/journal.new" "$STATE/journal" && sync || exit 1
 if [ "$own_port" = 1 ]; then
  # Recheck to avoid overwriting a property changed since the snapshot.
  [ -z "$(getprop "$PORT")" ] && write_prop "$PORT" 5555 || { restore; exit 1; }
 fi
 [ "$(getprop "$LEGACY")" = 1 ] && write_prop "$LEGACY" 0 || { restore; exit 1; }
 ;;
restore) restore || exit 1;;
*) fail 'usage: network-adb.sh apply|restore';;
esac
