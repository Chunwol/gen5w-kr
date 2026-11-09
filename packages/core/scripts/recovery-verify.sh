# Trusted verifier shipped in core. Never source executable code from a bundle
# until its entire inventory and required entry files have passed these checks.
rv_hash() { local x; x=$(md5 "$1") || return 1; set -- $x; echo "$1"; }
rv_safe() {
    local p=$1 target=$1 platform=${IT_DATA:-/data} info mode owner parent name line found expected=0
    if [ -n "${IT_DATA:-}" ]; then expected=$(id); expected=${expected#uid=}; expected=${expected%%\(*}; fi
    while [ -n "$p" ] && [ "$p" != / ]; do
        [ -e "$p" ] && [ ! -L "$p" ] || return 1
        parent=${p%/*}; [ -n "$parent" ] || parent=/
        name=${p##*/}; found=0
        info=$(ls -ln "$parent") || return 1
        while IFS= read -r line; do
            [ "${line##* }" = "$name" ] || continue
            set -- $line; mode=$1
            if [ -x /system/bin/toolbox ]; then owner=$2; else owner=$3; fi
            found=1; break
        done <<EOF
$info
EOF
        [ "$found" = 1 ] || return 1
        if [ "$p" = "$platform" ]; then
            # Android /data is normally system:system 0771. Its privileged
            # system group is trusted; arbitrary world-writable /data is not.
            case "$owner" in 0|1000|"$expected") ;; *) return 1;; esac
            case "$mode" in d???????w*) return 1;; d*) return 0;; *) return 1;; esac
        fi
        [ "$owner" = "$expected" ] || { [ "$p" != "$target" ] && [ "$owner" = 0 ]; } || return 1
        case "$mode" in d????????t) [ "$p" != "$target" ] || return 1;; ?????w*|????????w*) return 1;; esac
        p=${p%/*}; [ -n "$p" ] || p=/
    done
}
rv_manifest() {
    local root=$1 sum rel extra seen='|' count=0 part receipt
    [ -f "$root/RECOVERY.md5" ] && [ ! -L "$root/RECOVERY.md5" ] &&
        [ -f "$root/RECOVERY.receipt" ] && [ ! -L "$root/RECOVERY.receipt" ] || return 1
    IFS= read -r receipt < "$root/RECOVERY.receipt" || return 1
    case "$receipt" in ''|*[!0-9a-f]*) return 1;; esac
    [ "${#receipt}" = 32 ] && [ "$(rv_hash "$root/RECOVERY.md5")" = "$receipt" ] || return 1
    while IFS=' ' read -r sum rel extra; do
        case "$sum" in ''|*[!0-9a-f]*) return 1;; esac
        [ "${#sum}" = 32 ] && [ -z "$extra" ] || return 1
        case "$rel" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        case "$seen" in *"|$rel|"*) return 1;; esac
        seen=$seen$rel'|'; count=$((count+1)); [ "$count" -le 4096 ] || return 1
        [ -f "$root/$rel" ] || return 1
        part=$root/$rel
        while [ "$part" != "$root" ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; done
        [ "$(rv_hash "$root/$rel")" = "$sum" ] || return 1
    done < "$root/RECOVERY.md5"
    [ "$count" -gt 0 ]
}
