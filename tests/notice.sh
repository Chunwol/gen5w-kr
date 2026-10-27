#!/bin/bash
# Synthetic files only; run the actual module hooks under Android's mksh.
set -u
cd "$(dirname "$0")/.."
. tests/lib.sh
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/pkg/scripts" "$W/pkg/bin" "$W/sys/priv-app" "$W/data" "$W/bin" "$W/fixture"
cp packages/notice-timer/scripts/*.sh "$W/pkg/scripts/"
cp packages/notice-timer/bin/status.sh "$W/pkg/bin/"
for version in 035 039; do
    echo "stock$version" > "$W/fixture/original$version"
    echo "patched$version" > "$W/fixture/patched$version"
    echo "apk$version" > "$W/fixture/apk$version"
    printf 'NOTICE_RECIPE=test-%s\nNOTICE_APK_SHA=apk%s\n' "$version" "$version" > "$W/pkg/scripts/recipe-v$version.sh"
    cat > "$W/pkg/bin/notice-patch-v$version" <<EOF
#!/bin/sh
case "\$1" in
original) cmp -s "\$2" "\$NOTICE_TEST_FIXTURE/original$version";;
patched) cmp -s "\$2" "\$NOTICE_TEST_FIXTURE/patched$version";;
verify) cmp -s "\$2" "\$NOTICE_TEST_FIXTURE/\$3";;
apply) cmp -s "\$2" "\$NOTICE_TEST_FIXTURE/original$version" && cp "\$NOTICE_TEST_FIXTURE/patched$version" "\$3";;
*) exit 2;;
esac
EOF
done
cat > "$W/bin/nemesis" <<'EOF'
#!/bin/sh
echo "$*" >> "$NOTICE_TEST_FIXTURE/remounts"
exit 0
EOF
chmod +x "$W/bin/nemesis"
# Mock root ownership assignment; no host privilege change is required.
printf '#!/bin/sh\nexit 0\n' > "$W/bin/chown"
chmod +x "$W/bin/chown"
printf '#!/bin/sh\nexit 0\n' > "$W/bin/sync"
chmod +x "$W/bin/sync"
export PATH="$W/bin:$PATH"
# Deliberately leave helpers 0644, as NEMESIS does when extracting.
export NOTICE_TEST_SYS="$W/sys" NOTICE_TEST_DATA="$W/data" NOTICE_TEST_NEM="$W/bin/nemesis" NOTICE_TEST_FIXTURE="$W/fixture"
TARGET=$W/sys/priv-app/SystemUI.odex
APK=$W/sys/priv-app/SystemUI.apk
PERSIST=$W/sys/etc/gen5w-kr-backup/notice
MARK=$W/data/nemesis/backup/gen5w.kr.notice
run() { mksh "$W/pkg/scripts/$1.sh" > "$W/out" 2>&1; }
cp "$W/fixture/original039" "$TARGET"
echo unknown > "$APK"
run pre; rc=$?
check 'unknown APK skips without mutation' test "$rc" = 77
check 'unknown APK creates no ownership' test ! -e "$PERSIST"
cp "$W/fixture/apk039" "$APK"
echo unknown > "$TARGET"
run pre; rc=$?
check 'unknown generation skips' test "$rc" = 77
check 'unknown input never remounts' test ! -e "$W/fixture/remounts"
cp "$W/fixture/original039" "$TARGET"
check 'V039 paired precheck' run pre
check 'V039 apply' run post
check 'patched ODEX exact' cmp -s "$TARGET" "$W/fixture/patched039"
check 'durable original exact' cmp -s "$PERSIST/original" "$W/fixture/original039"
check 'runtime original exact' cmp -s "$MARK/original" "$W/fixture/original039"
check 'idempotent reinstall' run post
echo tamper > "$TARGET"
if run preun; then bad 'foreign target blocks restore'; else ok 'foreign target blocks restore'; fi
check 'tampered target retained' grep -qx tamper "$TARGET"
cp "$W/fixture/patched039" "$TARGET"
echo corrupt > "$PERSIST/original"
if run preun; then bad 'damaged backup blocks restore'; else ok 'damaged backup blocks restore'; fi
cp "$W/fixture/original039" "$PERSIST/original"
rm -rf "$MARK"
check 'rollback after data reset' run preun
check 'rollback byte identity' cmp -s "$TARGET" "$W/fixture/original039"
check 'owned persistent state removed' test ! -e "$PERSIST"
cp "$W/fixture/original035" "$TARGET"; cp "$W/fixture/apk035" "$APK"
check 'V035 auto profile' run post
check 'V035 patched bytes' cmp -s "$TARGET" "$W/fixture/patched035"
check 'V035 restore' run preun
check 'V035 exact original' cmp -s "$TARGET" "$W/fixture/original035"
mv "$TARGET" "$TARGET.real"; ln -s "$TARGET.real" "$TARGET"
if run post; then bad 'linked target refused'; else ok 'linked target refused'; fi
check 'linked original preserved' cmp -s "$TARGET.real" "$W/fixture/original035"
rm "$TARGET"; mv "$TARGET.real" "$TARGET"
mkdir -p "$PERSIST.pending"
echo gen5w.kr.notice:test-035 > "$PERSIST.pending/owner"
echo interrupted-copy > "$PERSIST.pending/original.tmp"
check 'interrupted durable backup retries from verified stock' run post
check 'retry publishes complete durable original' cmp -s "$PERSIST/original" "$W/fixture/original035"
rm -rf "$MARK"
mkdir -p "$MARK.pending"
echo gen5w.kr.notice:test-035 > "$MARK.pending/owner"
echo interrupted-copy > "$MARK.pending/original.tmp"
check 'interrupted runtime backup retries from durable original' run post
check 'retry publishes complete runtime original' cmp -s "$MARK/original" "$W/fixture/original035"
check 'interrupted backup retries preserve exact removal' run preun
done_tests notice
