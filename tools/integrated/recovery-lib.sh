# Root-owned recovery bundle. MD5 is corruption detection, not authentication.
RD=${IT_DATA:-/data}/nemesis
RB=$RD/gen5wkr.recovery
RT=$RD/gen5w-kr-integrated
recovery_reason=unknown
r_fail() { recovery_reason=$1; return 1; }
r_safe() {
    local p=$1 target=$1 info mode owner parent name line found expected=0
    # Host harness runs unprivileged; production always requires uid 0.
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
        [ "$owner" = "$expected" ] || { [ "$p" != "$target" ] && [ "$owner" = 0 ]; } || return 1
        case "$mode" in
            d????????t) [ "$p" != "$target" ] || return 1;;
            ?????w*|????????w*) return 1;;
        esac
        p=${p%/*}; [ -n "$p" ] || p=/
    done
}
r_no_links() {
    local p
    for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ ! -L "$p" ] || return 1
        [ ! -d "$p" ] || r_no_links "$p" || return 1
    done
}
r_inventory() {
    local root=$1 dir=${2:-$1} p rel sum
    for p in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [ ! -L "$p" ] || return 1
        [ -e "$p" ] || continue
        if [ -d "$p" ]; then r_inventory "$root" "$p" || return 1; continue; fi
        [ -f "$p" ] || return 1
        rel=${p#"$root/"}
        case "$rel" in complete|RECOVERY.md5|RECOVERY.md5.tmp|RECOVERY.receipt) continue;;
            ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        sum=$(r_hash "$p") || return 1
        echo "$sum  $rel"
    done
}
r_hash() { local x; x=$(md5 "$1") || return 1; set -- $x; echo "$1"; }
r_manifest() {
    local root=$1 sum rel extra seen='|' count=0 part receipt
    [ -f "$root/RECOVERY.md5" ] && [ ! -L "$root/RECOVERY.md5" ] || return 1
    [ -f "$root/RECOVERY.receipt" ] && [ ! -L "$root/RECOVERY.receipt" ] || return 1
    IFS= read -r receipt < "$root/RECOVERY.receipt" || return 1
    case "$receipt" in ''|*[!0-9a-f]*) return 1;; esac
    [ "${#receipt}" = 32 ] && [ "$(r_hash "$root/RECOVERY.md5")" = "$receipt" ] || return 1
    while IFS=' ' read -r sum rel extra; do
        case "$sum" in ''|*[!0-9a-f]*) return 1;; esac
        [ "${#sum}" = 32 ] && [ -z "$extra" ] || return 1
        case "$rel" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        case "$seen" in *"|$rel|"*) return 1;; esac
        seen=$seen$rel'|'; count=$((count + 1)); [ "$count" -le 4096 ] || return 1
        [ -f "$root/$rel" ] || return 1
        part=$root/$rel
        while [ "$part" != "$root" ]; do [ ! -L "$part" ] || return 1; part=${part%/*}; done
        [ "$(r_hash "$root/$rel")" = "$sum" ] || return 1
    done < "$root/RECOVERY.md5"
    [ "$count" -gt 0 ]
}
r_snapshot() {
    local f sum extra id
    [ -d "$RT/prior" ] && [ ! -L "$RT/prior" ] && [ -f "$RT/prior/complete" ] && [ ! -L "$RT/prior/complete" ] || return 1
    r_no_links "$RT/prior" || return 1
    r_manifest "$RT/prior" || return 1
    [ -f "$RT/prior/wireless-mode" ] && [ -f "$RT/prior/ap-markers" ] || return 1
    for f in "$RT"/attempt.*; do
        [ -f "$f" ] || continue
        [ ! -L "$f" ] || return 1
        id=${f##*/attempt.}
        case "$id" in gen5w.kr.dongle|gen5w.kr.localhotspot|gen5w.kr.wireless|gen5w.kr.audio|gen5w.kr.bridge|gen5w.kr.core|gen5w.kr.timer|gen5w.kr.bluelink|gen5w.kr.drivelog|wireless.carplay.aa) ;; *) return 1;; esac
        if [ -e "$RT/prior/$id" ] || [ -e "$RT/prior/$id.md5" ]; then
            [ -f "$RT/prior/$id.zip" ] || return 1
        fi
        if [ -e "$RT/prior/$id.zip" ]; then
            IFS=' ' read -r sum extra < "$RT/prior/$id.md5" || return 1
            [ -z "$extra" ] && [ "$(r_hash "$RT/prior/$id.zip")" = "$sum" ] || return 1
        fi
    done
}
r_check() {
    local required
    r_safe "$RD" && r_safe "$RT" || { r_fail unsafe-path; return 1; }
    [ -f "$RT/state" ] && [ ! -L "$RT/state" ] && [ ! -L "$RT/state.tmp" ] || { r_fail unsafe-path; return 1; }
    case "$(cat "$RT/state" 2>/dev/null)" in recovery-required|applying|removing|recovering) ;; *) r_fail state-not-recoverable; return 1;; esac
    r_safe "$RB/current" && r_manifest "$RB/current" || { r_fail runner-unavailable; return 1; }
    r_snapshot || { r_fail snapshot-invalid; return 1; }
    [ -x "${IT_NEM:-/system/xbin/nemesis}" ] && [ -x "${IT_SHELL:-/system/bin/sh}" ] && [ -x "$RB/current/zipstore" ] || { r_fail runner-unavailable; return 1; }
    for required in common.sh recovery.sh recovery-lib.sh rollback.sh report.sh errors.sh; do
        [ -f "$RB/current/$required" ] &&
            grep -qxF "$(r_hash "$RB/current/$required")  $required" "$RB/current/RECOVERY.md5" || { r_fail runner-unavailable; return 1; }
    done
    recovery_reason=ready
}
r_prepare() {
    local sum rel extra parent
    r_safe "$RD" && r_manifest . || { r_fail bundle-invalid; return 1; }
    if [ -e "$RT/lock" ] || [ -L "$RT/lock" ]; then
        [ ! -L "$RT/lock" ] && [ "$(cat "$RT/lock/pid" 2>/dev/null)" = "$$" ] || { r_fail busy; return 1; }
    fi
    [ ! -L "$RB" ] || return 1
    mkdir -p "$RB" && chmod 700 "$RB" && r_safe "$RB" || return 1
    if [ -f "$RB/current/RECOVERY.md5" ] && [ "$(r_hash "$RB/current/RECOVERY.md5")" = "$(r_hash RECOVERY.md5)" ] && r_manifest "$RB/current"; then return 0; fi
    if [ -e "$RB/staging" ] || [ -L "$RB/staging" ]; then
        r_safe "$RB/staging" && r_no_links "$RB/staging" || { r_fail unsafe-path; return 1; }
        rm -rf "$RB/staging" || return 1
    fi
    mkdir "$RB/staging" || { r_fail staging-exists; return 1; }
    while IFS=' ' read -r sum rel extra; do
        parent=${rel%/*}; [ "$parent" != "$rel" ] || parent=.
        mkdir -p "$RB/staging/$parent" && cp "./$rel" "$RB/staging/$rel" || return 1
    done < RECOVERY.md5
    cp RECOVERY.md5 "$RB/staging/RECOVERY.md5" && cp RECOVERY.receipt "$RB/staging/RECOVERY.receipt" && r_manifest "$RB/staging" || return 1
    if [ -e "$RB/previous" ] || [ -L "$RB/previous" ]; then
        r_safe "$RB/previous" && r_manifest "$RB/previous" && r_no_links "$RB/previous" || { r_fail unsafe-path; return 1; }
        rm -rf "$RB/previous" || return 1
    fi
    if [ -e "$RB/current" ]; then mv "$RB/current" "$RB/previous" || return 1; fi
    mv "$RB/staging" "$RB/current" && sync
}
r_record() {
    local result=$1 reason=$2 token=$3 out=$RD/gen5wkr.recovery-result
    [ ! -L "$out" ] && [ ! -L "$out.tmp" ] || return 1
    { echo "recovery_request=$token"; echo "recovery_result=$result"; echo "recovery_reason=$reason";
        echo "recovery_boot=$(cat /proc/sys/kernel/random/boot_id)"; } > "$out.tmp" &&
        chmod 644 "$out.tmp" && mv "$out.tmp" "$out" && sync
}
r_run() {
    local token=$1 rc=1
    case "$token" in ''|*[!0-9]*) r_fail invalid-request; return 1;; esac
    [ "${#token}" -le 10 ] || return 1
    r_safe "$RB/current" || return 1
    cd "$RB/current" || return 1
    . ./common.sh
    acquire || return 1
    local first bootline current_boot=$(cat /proc/sys/kernel/random/boot_id)
    if [ -f "$RD/gen5wkr.recovery-result" ] && [ ! -L "$RD/gen5wkr.recovery-result" ]; then
        first=; bootline=
        while IFS= read -r first; do
            case "$first" in recovery_request=*) bootline=${first#*=};;
                recovery_boot=*) [ "$bootline" != "$token" ] || [ "${first#*=}" != "$current_boot" ] || { r_fail duplicate-request; return 1; };;
            esac
        done < "$RD/gen5wkr.recovery-result"
    fi
    # Consume under the lock even when validation fails, never loop on a stale
    # UI request. A deliberate retry must carry a new token.
    r_record working ready "$token" || return 1
    r_check || { r_record failed "$recovery_reason" "$token"; return 1; }
    trap '' HUP
    R_TOKEN=$token
    trap 'set_state recovery-required; r_record failed interrupted "$R_TOKEN"; transaction_exit 1' EXIT
    : > "$NOREBOOT" || return 1
    KEEP_NOREBOOT=1
    if rollback_transaction && bootguard_reconcile_previous rolled-back; then
        # Persist before reboot (and before the collector/core might disappear).
        r_record restored ready "$token" || return 1
        rm -f "$NOREBOOT" || return 1
        trap 'transaction_exit $?' EXIT
        cold_reboot
        return $?
    fi
    set_state recovery-required
    r_record failed rollback-failed "$token" || return 1
    trap 'transaction_exit $?' EXIT
    r_fail rollback-failed
}
