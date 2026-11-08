#!/bin/mksh
set -eu
cd "${0%/*}/.."
fail() { echo "FAIL $1"; exit 1; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export ERR_DIR=$W/private ERR_ATTEMPT=boot-test-1 ERR_REVISION=abcdef01
helper=$PWD/tools/diagnostics/errors.sh
if [ ! -f "$helper" ]; then echo 'FAIL missing diagnostic boundary'; exit 1; fi
. "$helper"
cat > "$W/command" <<'EOF'
#!/bin/sh
echo parsed-value
echo 'Permission denied SSID=secret-network password=secret-value 00:11:22:33:44:55' >&2
exit 13
EOF
chmod 755 "$W/command"
rc=0
err_run core install apply "$W/command" > "$W/out" 2> "$W/err" || rc=$?
[ "$rc" = 13 ] || fail 'preserve command rc'
[ "$(cat "$W/out")" = parsed-value ] || fail 'stdout parsing not contaminated'
grep -q 'reason=permission' "$ERR_DIR/errors.0" || fail 'classify permission'
grep -q 'rc=13' "$ERR_DIR/first.0" || fail 'first error persisted'
err_event core rollback restore failed 7 unknown
grep -q 'rc=13' "$ERR_DIR/first.0" || fail 'recovery does not replace original cause'
if grep -R -E 'secret-network|secret-value|00:11:22:33:44:55' "$ERR_DIR" "$W/err"; then fail 'secrets escaped'; fi
rc=0; err_run core inspect absent "$W/not-present" > "$W/out" 2> "$W/err" || rc=$?
[ "$rc" = 127 ] || fail 'missing command rc'
grep -q 'reason=missing-command' "$ERR_DIR/errors.0" || fail 'missing classification'
err_run core inspect empty true > "$W/out" 2> "$W/err"
[ ! -s "$W/out" ] || fail 'empty stdout preserved'
err_run core inspect huge sh -c 'dd if=/dev/zero bs=1024 count=256 2>/dev/null | tr "\000" x >&2; echo huge-complete' > "$W/out" 2> "$W/err"
[ "$(cat "$W/out")" = huge-complete ] || fail 'huge unterminated stderr changes stdout'
[ "$(wc -c < "$W/err")" -le 4096 ] || fail 'huge stderr output unbounded'
for n in $(seq 1 400); do err_event core inspect repeat failed 1 unknown 2>/dev/null; done
[ -f "$ERR_DIR/errors.1" ] || fail 'rotation occurred'
count=0
for f in "$ERR_DIR"/errors.*; do
 [ -f "$f" ] || continue
 bytes=$(wc -c < "$f"); [ "$bytes" -le 65536 ] || fail 'journal byte cap'
 count=$((count+1))
done
[ "$count" -le 4 ] || fail 'segment cap'
# A malicious or unavailable diagnostic path cannot redirect or change command effects.
mkdir "$W/elsewhere"; ln -s "$W/elsewhere" "$W/link"
ERR_DIR=$W/link
rc=0; err_run core install symlink "$W/command" > "$W/out" 2> "$W/err" || rc=$?
[ "$rc" = 13 ] && [ "$(cat "$W/out")" = parsed-value ] || fail 'diagnostic failure changed operation'
[ -z "$(ls -A "$W/elsewhere")" ] || fail 'followed diagnostic symlink'
echo 'PASS bounded error journal rc/stdout/first-failure/privacy/rotation/symlink'
