#!/system/bin/sh
# Verify NEMESIS installed the exact bundled Core before native PDK 1.6 is enabled.
BASE=${0%/*}; [ "$BASE" != "$0" ] || BASE=.
ROOT=${PORTABLE_TEST_ROOT:-}
ADAPTER=${PORTABLE_TEST_CORE_ADAPTER:-}
HELPER=${PORTABLE_HELPER:-$BASE/bin/dex-patch}
fail() { echo "core-ready: $*" >&2; exit 1; }
plain() {
 case "$1" in /*) :;; *) return 1;; esac
 case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*/..|*/.|*//*) return 1;; esac
 local part=$1
 while [ "$part" != / ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; [ -n "$part" ] || part=/; done
}
[ "${1:-}" = verify ] && [ "$#" = 1 ] || fail usage
if [ -n "$ROOT" ]; then
 plain "$ROOT" && [ "$ROOT" != / ] && [ -d "$ROOT" ] || fail fixture
 plain "$ADAPTER" && [ -x "$ADAPTER" ] || fail fixture-adapter
else
 [ -z "$ADAPTER" ] || fail fixture
 case "$(id)" in uid=0\(*) :;; *) fail 'real root required';; esac
fi
plain "$HELPER" && [ -x "$HELPER" ] || fail helper
BUNDLE=$BASE/app/gen5w-core.apk
plain "$BUNDLE" && [ -f "$BUNDLE" ] || fail bundled-apk
if [ -n "$ROOT" ]; then
 result=$("$ADAPTER" pm-path) || fail pm-path
else
 # KitKat pm has no shebang; supervise its sh interpreter and process group.
 result=$("$HELPER" supervise 20 /system/bin/true /system/bin/sh /system/bin/pm path kr.gen5w.core) || fail pm-path
fi
case "$result" in package:/data/app/*.apk|package:/system/app/*.apk) :;; *) fail installed-path;; esac
installed=${result#package:}
# A newline, extra package path, traversal, or symlink in any ancestor fails.
plain "$installed" && plain "$ROOT$installed" && [ -f "$ROOT$installed" ] || fail installed-path
bundle_hash=$("$HELPER" sha256 "$BUNDLE") || fail bundled-hash
installed_hash=$("$HELPER" sha256 "$ROOT$installed") || fail installed-hash
case "$bundle_hash" in ''|*[!a-f0-9]*) fail bundled-hash;; esac
[ "${#bundle_hash}" = 64 ] && [ "$installed_hash" = "$bundle_hash" ] || fail 'installed Core differs from bundled APK'
echo 'core-ready: exact installed Core APK verified'
