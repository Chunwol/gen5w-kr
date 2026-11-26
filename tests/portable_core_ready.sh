#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
command -v mksh >/dev/null || exit 78
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
pkg=$t/package; root=$t/root
mkdir -p "$pkg/app" "$pkg/bin" "$root/data/app" "$root/system/app"
cp tools/portable/core-ready.sh "$pkg/"
printf apk-modern > "$pkg/app/gen5w-core.apk"
cp "$pkg/app/gen5w-core.apk" "$root/data/app/kr.gen5w.core-1.apk"
cat > "$pkg/bin/dex-patch" <<'EOF'
#!/bin/sh
[ "$1" = sha256 ] || exit 2
sha256sum "$2" | cut -d ' ' -f 1
EOF
cat > "$t/adapter" <<'EOF'
#!/bin/sh
[ "$1" = pm-path ] || exit 2
cat "$PORTABLE_TEST_ROOT/pm-path"
EOF
chmod +x "$pkg/bin/dex-patch" "$t/adapter"
run() { PORTABLE_TEST_ROOT="$root" PORTABLE_TEST_CORE_ADAPTER="$t/adapter" mksh "$pkg/core-ready.sh" verify; }
printf 'package:/data/app/kr.gen5w.core-1.apk\n' > "$root/pm-path"
run
printf stale > "$root/data/app/kr.gen5w.core-1.apk"
if run; then echo 'FAIL accepted old core'; exit 1; fi
cp "$pkg/app/gen5w-core.apk" "$root/data/app/kr.gen5w.core-1.apk"
for result in '' 'package:/data/app/missing.apk' 'package:/data/app/../app/kr.gen5w.core-1.apk' 'package:/vendor/app/core.apk' $'package:/data/app/kr.gen5w.core-1.apk\npackage:/system/app/core.apk'; do
 printf '%s\n' "$result" > "$root/pm-path"
 if run; then echo 'FAIL accepted bad pm path'; exit 1; fi
done
printf 'package:/data/app/kr.gen5w.core-1.apk\n' > "$root/pm-path"
mv "$root/data/app" "$root/data/actual"
ln -s actual "$root/data/app"
if run; then echo 'FAIL accepted symlink ancestor'; exit 1; fi
rm "$root/data/app"; mv "$root/data/actual" "$root/data/app"
cp "$pkg/app/gen5w-core.apk" "$root/system/app/core.apk"
printf 'package:/system/app/core.apk\n' > "$root/pm-path"
run
echo 'PASS core-ready exact APK bytes, data/system paths, missing/multiple/malformed paths and symlink refusal'
