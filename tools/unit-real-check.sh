#!/bin/bash
# Local check against the head unit's own mksh and toolbox, run under qemu-arm.
# CI cannot do this: those binaries belong to the manufacturer and stay private.
#
#   tools/unit-real-check.sh <system.img | dir with system/bin and system/lib>
#
# Needs qemu-arm (qemu-user), python3, unshare (util-linux); debugfs (e2fsprogs) for an image.
# No root needed. It checks:
#   1. every on-unit script parses with the unit's mksh (R43),
#   2. tests/unit/commands.txt and policy.txt match this unit's binaries,
#   3. the toolbox options we allow work, and the ones we refuse fail,
#   4. the shell builtins the scripts rely on behave as expected.
# Limits: Android's bionic hangs under qemu-user when mksh forks, so whole scripts
# cannot run here; the mock tests (tests/run.sh) cover behaviour.
set -u
cd "$(dirname "$0")/.." || exit 1
SRC=${1:-}
[ -n "$SRC" ] || { echo "usage: $0 <system.img | dir with system/bin and system/lib>"; exit 2; }
for t in qemu-arm python3 unshare; do command -v "$t" >/dev/null || { echo "missing: $t"; exit 2; }; done

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
ROOTFS=$W/root
mkdir -p "$ROOTFS/dev" "$W/scratch"
if [ -f "$SRC" ]; then
    command -v debugfs >/dev/null || { echo "missing: debugfs (e2fsprogs)"; exit 2; }
    mkdir -p "$ROOTFS/system"
    for d in bin lib xbin; do debugfs -R "rdump /$d $ROOTFS/system" "$SRC" >/dev/null 2>&1; done
else
    ln -s "$(cd "$SRC" && pwd)/system" "$ROOTFS/system"
fi
[ -f "$ROOTFS/system/bin/mksh" ] && [ -f "$ROOTFS/system/bin/toolbox" ] || { echo "no system/bin/mksh and toolbox in $SRC"; exit 2; }
# An empty Android property area; bionic will not start without one.
python3 - "$ROOTFS/dev/__properties__" <<'EOF'
import struct, sys
hdr = struct.pack('<4I', 20, 0, 0x504f5250, 0xfc6ed0ab)
open(sys.argv[1], 'wb').write(hdr + b'\0' * (128 * 1024 - len(hdr)))
EOF

fail=0; pass=0
ok()  { pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
# run a unit binary (user namespace: the property file must look root-owned)
unit() { unshare -r env QEMU_LD_PREFIX="$ROOTFS" timeout 30 qemu-arm "$@" 2>&1 | grep -v '__bionic_open_tzdata'; return "${PIPESTATUS[0]}"; }
tb() { unit "$ROOTFS/system/bin/toolbox" "$@"; }

echo "== 1. scripts parse with the unit's mksh"
echo "   $(unit "$ROOTFS/system/bin/mksh" -c 'echo $KSH_VERSION')"
n=0
python3 tests/unit_commands.py --list > "$W/scripts" || { echo "could not list on-unit scripts"; exit 2; }
while read -r f; do
    n=$((n+1))
    out=$(unit "$ROOTFS/system/bin/mksh" -n "$f") && [ -z "$out" ] && ok || bad "unit mksh -n $f: $out"
done < "$W/scripts"
echo "   $n scripts"

echo "== 2. command lists match this unit"
have() { [ -e "$ROOTFS/system/bin/$1" ] || [ -L "$ROOTFS/system/bin/$1" ] || [ -e "$ROOTFS/system/xbin/$1" ] || [ -L "$ROOTFS/system/xbin/$1" ]; }
while read -r name kind; do
    case "$name" in ''|'#'*) continue;; esac
    have "$name" && ok || bad "commands.txt lists $name, not on this unit"
    if [ "$kind" = toolbox ]; then
        [ "$(readlink "$ROOTFS/system/bin/$name" 2>/dev/null)" = toolbox ] && ok || bad "$name is not a toolbox applet here"
    fi
done < tests/unit/commands.txt
while read -r name _; do
    case "$name" in '!'*) name=${name#!};; *) continue;; esac
    case "$name" in busybox) continue;; esac  # present, but must not be relied on
    have "$name" && bad "policy.txt bans $name, but this unit has it" || ok
done < tests/unit/policy.txt

echo "== 3. toolbox options"
S=$W/scratch
expect() { # expect ok|fail <label> <toolbox args...>
    local want=$1 label=$2; shift 2
    if tb "$@" >/dev/null; then got=ok; else got=fail; fi
    [ "$got" = "$want" ] && ok || bad "toolbox $label: expected $want, got $got"
}
echo data > "$S/a"; echo data > "$S/same"; echo other > "$S/diff"; mkdir -p "$S/d/sub"; echo z > "$S/d/sub/z"
expect ok   'mv'            mv "$S/a" "$S/b"
expect fail 'mv -f'         mv -f "$S/b" "$S/a"
expect ok   'cmp same'      cmp "$S/b" "$S/same"
expect fail 'cmp different' cmp "$S/b" "$S/diff"
expect fail 'cmp missing'   cmp "$S/b" "$S/missing"
expect fail 'cmp -s'        cmp -s "$S/b" "$S/same"
expect ok   'cp -p'         cp -p "$S/b" "$S/c"
expect ok   'cp -R d/.'     cp -R "$S/d/." "$S/e"
[ -f "$S/e/sub/z" ] && ok || bad "toolbox cp -R d/. did not copy the tree"
expect ok   'rm -f missing' rm -f "$S/missing"
expect ok   'rm -rf'        rm -rf "$S/e"
expect ok   'rm -r'         rm -r "$S/d"
expect ok   'mkdir -p'      mkdir -p "$S/x/y"
expect ok   'ls -ln'        ls -ln "$S/b"
expect ok   'ls -l'         ls -l "$S/b"
expect ok   'ln -s'         ln -s "$S/b" "$S/l"
expect ok   'md5'           md5 "$S/b"
expect fail 'md5 missing'   md5 "$S/missing"
for o in -q -qx -qxF -qE -aqE -aqF -E -cE -c -n -o; do expect ok "grep $o" grep "$o" data "$S/b"; done
for o in -i -iE -iq; do expect ok "grep $o" grep "$o" DATA "$S/b"; done
expect fail "grep without -i is case-sensitive" grep -q DATA "$S/b"
for o in -v -vE; do expect ok "grep $o" grep "$o" zzz "$S/b"; done
expect fail 'grep -qx no match' grep -qx dat "$S/b"
for c in printf head stat; do expect fail "$c (not an applet)" "$c"; done

echo "== 4. mksh builtins the scripts rely on"
cat > "$S/builtins.sh" <<'EOF'
PATH=/nonexistent
cr=$'\r'; x="a.b<c>&\"d$cr"
x=${x//"$cr"/}; [ "${#x}" = 9 ] || echo "bad: \$'\\r' strip"
[ "${x:0:3}" = a.b ] || echo "bad: \${v:0:n}"
y=${x//\&/\&amp;}; y=${y//</\&lt;}; y=${y//>/\&gt;}; y=${y//\"/\&quot;}
[ "$y" = 'a.b&lt;c&gt;&amp;&quot;d' ] || echo "bad: \${v//p/r} html: $y"
z='ab?c d/é'; z=${z//[!a-zA-Z0-9_.:\/ -]/?}; [ "$z" = 'ab?c d/??' ] || echo "bad: class replace: $z"
print -rn -- 'a\n'; print -r -- '|'
IFS= read -r line < "$1"; [ "$line" = 'first line' ] || echo "bad: read -r"
f() { local q=1; [ "$q" = 1 ] || echo "bad: local"; }; f
[[ abc == a* ]] || echo "bad: [["
echo builtins-done
EOF
printf 'first line\nsecond\n' > "$S/in"
out=$(unit "$ROOTFS/system/bin/mksh" "$S/builtins.sh" "$S/in")
case "$out" in *bad:*) bad "builtins: $out";; *builtins-done*) ok;; *) bad "builtins did not finish: $out";; esac
case "$out" in *'a\n|'*) ok;; *) bad "print -rn -- did not print raw text: $out";; esac

echo "== unit-real-check: $pass passed, $fail failed"
[ "$fail" = 0 ]
