# Run from the bundle root. All journals and prior packages stay on the unit.
export EV6_TEST_ROOT=1
DATA=${IT_DATA:-/data}
SYS=${IT_SYSTEM:-/system}
NEM=${IT_NEM:-/system/xbin/nemesis}
SH=${IT_SHELL:-/system/bin/sh}
APPS=$DATA/nemesis/apps
TX=$DATA/nemesis/gen5w-kr-integrated
NOREBOOT=$DATA/nemesis/gen5wkr.noreboot
WIRELESS_OFF=$DATA/nemesis/gen5wkr.wireless-disabled
IDS='gen5w.kr.wireless gen5w.kr.audio gen5w.kr.hotspot gen5w.kr.bridge gen5w.kr.core gen5w.kr.notice'
ALL_IDS="$IDS gen5w.kr.consent"
VARIANT=standard
if [ -f GEN5W-VARIANT ]; then
    IFS= read -r VARIANT < GEN5W-VARIANT
    VARIANT=${VARIANT%$'\r'}
    case "$VARIANT" in
        standard) ;;
        dongle) ;;
        *) echo 'REFUSED unknown bundle variant'; exit 1;;
    esac
fi
BACKEND=builtin
if [ -f GEN5W-BACKEND ]; then
    IFS= read -r BACKEND < GEN5W-BACKEND
    BACKEND=${BACKEND%$'\r'}
fi
if [ "$VARIANT" = dongle ] || [ "$BACKEND" = dongle ]; then
    IDS='gen5w.kr.dongle gen5w.kr.wireless gen5w.kr.audio gen5w.kr.hotspot gen5w.kr.bridge gen5w.kr.core gen5w.kr.notice'
fi
[ "$BACKEND" = builtin ] || [ "$BACKEND" = dongle ] || { echo 'REFUSED: USB Wi-Fi backend is not available in this build'; exit 1; }
REVERSE='gen5w.kr.notice gen5w.kr.consent gen5w.kr.core gen5w.kr.bridge gen5w.kr.hotspot gen5w.kr.audio gen5w.kr.wireless gen5w.kr.dongle wireless.carplay.aa'
. ./report.sh
. ./hotspot-repair.sh
digest() { local v; v=$(md5 "$1" 2>/dev/null) || v=$(md5sum "$1" 2>/dev/null) || return 1; set -- $v; echo "$1"; }
report() {
    echo "$1"; echo "$1" >> "$TX/report"
    case "$1" in FAILED*|REFUSED*|MISSING*|RECOVERY*) echo "$1" >> "$TX/failure";; esac
}
set_state() { echo "$1" > "$TX/state.tmp" && mv "$TX/state.tmp" "$TX/state" && sync; }
meta() {
    local section= line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in '['*']') section=$line;; "$2="*) [ "$section" = '[nemesis]' ] && { echo "${line#*=}"; return 0; };; esac
    done < "$1"
    return 1
}
gate() {
    local tree=$1 name=$2 path helper
    [ -f "$tree/NEMESIS.data" ] || return 1
    # Native ZIP extraction sets every member to 0644, including our helpers.
    for helper in "$tree"/bin/*; do
        [ ! -f "$helper" ] || { [ ! -L "$helper" ] && chmod 755 "$helper"; } || return 1
    done
    path=$(meta "$tree/NEMESIS.data" "$name") || return 0
    case "$path" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) report 'REFUSED unsafe hook path'; return 1;; esac
    [ -f "$tree/$path" ] && [ ! -L "$tree/$path" ] || return 1
    (cd "$tree" && "$SH" "$path")
}
hook() { gate "$APPS/$1" "$2"; }
durable() {
    case "$1" in gen5w.kr.hotspot) [ -d "$SYS/etc/gen5w-kr-backup/hotspot" ];;
        gen5w.kr.wireless|gen5w.kr.audio|gen5w.kr.bridge|gen5w.kr.notice|gen5w.kr.consent|gen5w.kr.dongle)
        [ -d "$SYS/etc/gen5w-kr-backup/${1##*.}" ];; *) return 1;; esac
}
check_stage() {
    local id=$1
    [ -f "checks/$id/FILES.md5" ] && [ -f "checks/$id/PACKAGE.md5" ] || return 1
    [ "$(digest "packages/$id.zip")" = "$(cat "checks/$id/PACKAGE.md5")" ] || return 1
    check_stage_tree "$id"
}
check_stage_tree() {
    local id=$1 sum path extra
    [ -f "checks/$id/FILES.md5" ] || return 1
    while read -r sum path extra; do
        case "$path" in ''|/*|*..*|*[!a-zA-Z0-9_./-]*) return 1;; esac
        [ -z "$extra" ] && [ ! -L "checks/$id/$path" ] || return 1
        [ "$(digest "checks/$id/$path")" = "$sum" ] || return 1
    done < "checks/$id/FILES.md5"
}
safe_remove() {
    local id=$1
    if [ ! -f "$APPS/$id/NEMESIS.data" ]; then
        durable "$id" || return 0
        check_stage_tree "$id" || return 1
        gate "$(pwd)/checks/$id" preuninstall || return 1
        report "RESTORED $id: recovered durable ownership after data reset"
        return 0
    fi
    # Native NEMESIS ignores this hook's return value. Check it ourselves first.
    hook "$id" preuninstall || return 1
    "$NEM" uninstall "$id" || return 1
    if [ -e "$APPS/$id" ]; then
        rm -rf "$APPS/$id" || return 1
    fi
    return 0
}
snapshot() {
    local id=$1 info tree=$APPS/$1
    if [ ! -f "$tree/NEMESIS.data" ]; then
        durable "$id" || return 0
        if [ "$id" = gen5w.kr.consent ]; then
            return 0
        fi
        check_stage_tree "$id" || return 1
        tree=$(pwd)/checks/$id
    fi
    [ "$(meta "$tree/NEMESIS.data" id)" = "$id" ] || return 1
    ./zipstore "$tree" "$TX/prior/$id.zip" || return 1
    info=$("$NEM" pkg-info "$TX/prior/$id.zip") || return 1
    echo "$info" | grep -qx "id=$id" || return 1
    digest "$TX/prior/$id.zip" > "$TX/prior/$id.md5" || return 1
    mkdir "$TX/prior/$id" && cp -R "$tree/." "$TX/prior/$id/" || return 1
}
rollback_transaction() {
    local id rc=0
    [ -f "$TX/prior/complete" ] || { report 'REFUSED incomplete snapshot; no rollback mutation'; return 1; }
    # Restore the mode before re-registering services from the snapshot.
    restore_wireless_mode || {
        set_state recovery-required
        report 'RECOVERY REQUIRED: wireless mode could not be restored'
        return 1
    }
    set_state recovering || return 1
    for id in $REVERSE; do
        [ -f "$TX/attempt.$id" ] || continue
        safe_remove "$id" || { rc=1; break; }
    done
    if [ "$rc" = 0 ]; then
        for id in wireless.carplay.aa $ALL_IDS; do
            [ -f "$TX/attempt.$id" ] && [ -f "$TX/prior/$id.zip" ] || continue
            [ "$(digest "$TX/prior/$id.zip")" = "$(cat "$TX/prior/$id.md5")" ] || { rc=1; break; }
            gate "$TX/prior/$id" preinstall || { rc=1; break; }
            "$NEM" install "$TX/prior/$id.zip" || { rc=1; break; }
            hook "$id" postinstall || { rc=1; break; }
            report "RESTORED $id"
        done
    fi
    if [ "$rc" = 0 ]; then
        set_state rolled-back; rm -f "$NOREBOOT"
        for id in $ALL_IDS; do
            [ -f "$TX/attempt.$id" ] || continue
            case "$(cat "$TX/result.$id" 2>/dev/null)" in failed*) result "$id" failed-restored;; *) result "$id" restored;; esac
        done
    else
        set_state recovery-required; report 'RECOVERY REQUIRED: prior packages retained; no reboot'
        for id in $ALL_IDS; do [ ! -f "$TX/attempt.$id" ] || result "$id" recovery-required; done
    fi
    return "$rc"
}
acquire() {
    chmod 755 ./zipstore 2>/dev/null || true
    mkdir -p "$TX" || return 1
    if ! mkdir "$TX/lock" 2>/dev/null; then
        local pid=
        [ ! -f "$TX/lock/pid" ] || pid=$(cat "$TX/lock/pid")
        case "$pid" in ''|*[!0-9]*) rm -rf "$TX/lock" 2>/dev/null || true;; esac
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then report 'REFUSED another transaction is running'; return 1; fi
        rm -rf "$TX/lock" 2>/dev/null || true
        mkdir "$TX/lock" || return 1
    fi
    echo $$ > "$TX/lock/pid"
    trap 'transaction_exit $?' EXIT
}
finish() {
    set_state committed || return 1
    rm -f "$NOREBOOT"
    report 'COMMITTED: module hooks checked; vehicle audio/HUD/connection test pending'
    write_summary || echo '결과 문서를 USB에 저장하지 못했습니다. Manager 로그를 확인하세요.'
    sync
    [ "${IT_NO_REBOOT:-0}" = 1 ] || /system/bin/reboot
}
begin() {
    local state= id
    if [ -f "$TX/state" ]; then
        state=$(cat "$TX/state" 2>/dev/null)
        case "$state" in
            applying|recovering)
                if [ -f "$TX/prior/complete" ]; then
                    report 'RECOVERING interrupted prior transaction before new installation'
                    rollback_transaction || { report 'REFUSED cannot recover prior transaction'; return 1; }
                else
                    report 'REFUSED interrupted transaction without complete snapshot'
                    return 1
                fi
                ;;
            recovery-required)
                report 'REFUSED unresolved system recovery required'
                return 1
                ;;
        esac
    fi
    rm -f "$NOREBOOT" 2>/dev/null || true
    set_state capturing || return 1
    rm -rf "$TX/prior" || return 1
    rm -f "$TX"/attempt.*
    mkdir "$TX/prior" || return 1
    : > "$NOREBOOT" || return 1
    # Capture every prior tree before any hook can mutate the system.
    for id in wireless.carplay.aa $ALL_IDS; do
        snapshot "$id" || { report "FAILED snapshot $id"; return 1; }
    done
    [ ! -L "$WIRELESS_OFF" ] || return 1
    if [ -f "$WIRELESS_OFF" ]; then echo disabled; else echo enabled; fi > "$TX/prior/wireless-mode" || return 1
    echo 1 > "$TX/prior/complete" && sync
}
install_transaction() {
    local id info rc wireless_ready
    reset_results
    # Validate every input identity before the first installed package is removed.
    for id in $IDS; do
        [ -f "packages/$id.zip" ] || { result "$id" failed; report "MISSING $id"; return 1; }
        info=$("$NEM" pkg-info "packages/$id.zip") || { result "$id" failed; return 1; }
        echo "$info" | grep -qx "id=$id" || { result "$id" failed; report "REFUSED wrong package identity $id"; return 1; }
        check_stage "$id" || { result "$id" failed; report "REFUSED staged payload integrity $id"; return 1; }
    done
    begin || return 1
    # Choose the branch before removing any installed package.
    if [ "${IT_FORCE_WIRED:-0}" = 1 ]; then rc=77
    else gate "$(pwd)/checks/gen5w.kr.wireless" preinstall; rc=$?; fi
    case "$rc" in
        0) wireless_ready=yes; report 'PLAN wireless: supported';;
        77) wireless_ready=no; report 'PLAN wired-only: wireless unavailable; restore wireless changes first';;
        *) result gen5w.kr.wireless failed
           report "FAILED wireless preflight rc=$rc"
           rollback_transaction; return 1;;
    esac
    set_state applying || return 1
    if [ -e "$APPS/wireless.carplay.aa" ]; then
        if [ -f "$APPS/wireless.carplay.aa/NEMESIS.data" ]; then
            : > "$TX/attempt.wireless.carplay.aa"; sync
            safe_remove wireless.carplay.aa || { rollback_transaction; return 1; }
            report 'MIGRATED wireless.carplay.aa (prior package retained on unit)'
        else
            report 'PRESERVED incomplete prior package; checking original files for normal installation'
        fi
    fi
    # Restore any previous local notice-disabling installation before the timer.
    if [ "$VARIANT" = standard ]; then
        id=gen5w.kr.consent
        if [ -f "$APPS/$id/NEMESIS.data" ] || durable "$id"; then
            : > "$TX/attempt.$id"; sync
            safe_remove "$id" 2>/dev/null || true
        fi
        result "$id" disabled
    fi
    for id in $IDS; do
        # Native NEMESIS ignores hook exit status. Gate before removing any old module.
        if [ -f "$WIRELESS_OFF" ]; then
            case "$id" in gen5w.kr.audio|gen5w.kr.hotspot)
                result "$id" skipped; report "SKIPPED $id: wired-only mode"; continue;; esac
        fi
        if [ "$id" = gen5w.kr.wireless ]; then
            if [ "$wireless_ready" = yes ]; then rc=0; else rc=77; fi
        else gate "$(pwd)/checks/$id" preinstall; rc=$?; fi
        if [ "$id" = gen5w.kr.wireless ] && [ "$rc" = 77 ]; then
            disable_wireless || { rollback_transaction; return 1; }
            continue
        fi
        if [ "$rc" = 77 ]; then
            if [ "$id" = gen5w.kr.hotspot ]; then
                disable_wireless || { rollback_transaction; return 1; }
                report 'WIRED ONLY: native AP profile separation is not supported on this version'
                continue
            fi
            result "$id" skipped
            report "SKIPPED $id: unsupported preinstall; prior installation retained"
            continue
        fi
        if [ "$rc" != 0 ]; then
            result "$id" failed
            report "FAILED preinstall $id rc=$rc"
            rollback_transaction || return 1
            return 1
        fi
        if [ "$id" = gen5w.kr.wireless ]; then
            [ ! -L "$WIRELESS_OFF" ] && rm -f "$WIRELESS_OFF" || { rollback_transaction; return 1; }
        fi
        : > "$TX/attempt.$id"; sync
        safe_remove "$id" || {
            if [ "$id" = gen5w.kr.hotspot ]; then
                result "$id" skipped
                report "SKIPPED $id: safe_remove failed; continuing with core/HUD"
                continue
            fi
            result "$id" failed; rollback_transaction; return 1;
        }
        "$NEM" install "$(pwd)/packages/$id.zip"
        rc=$?
        if [ "$rc" != 0 ] || [ ! -f "$APPS/$id/NEMESIS.data" ]; then
            if [ "$id" = gen5w.kr.hotspot ]; then
                result "$id" skipped
                report "SKIPPED $id: package install failed rc=$rc; continuing with core/HUD"
                continue
            fi
            result "$id" failed
            report "FAILED $id rc=$rc"
            rollback_transaction; return 1
        fi
        hook "$id" postinstall || {
            if [ "$id" = gen5w.kr.hotspot ]; then
                result "$id" skipped
                report "SKIPPED $id: postinstall hook failed; continuing with core/HUD"
                continue
            fi
            result "$id" failed; report "FAILED postinstall $id"; rollback_transaction; return 1;
        }
        if [ "$id" = gen5w.kr.bridge ] && [ -f "$WIRELESS_OFF" ]; then result "$id" wired-only
        else result "$id" applied; fi
        report "INSTALLED $id"
    done
    finish
}

# Restore wireless-only changes while retaining the bridge's wired route APIs.
disable_wireless() {
    local item
    [ ! -L "$WIRELESS_OFF" ] || return 1
    echo disabled > "$WIRELESS_OFF" || return 1
    if [ -x /system/bin/am ]; then
        /system/bin/am broadcast -a kr.gen5w.wireless.STOP_BRIDGE >/dev/null 2>&1 || true
    fi
    for item in gen5w.kr.hotspot gen5w.kr.audio gen5w.kr.wireless; do
        : > "$TX/attempt.$item"; sync
        safe_remove "$item" || { result "$item" failed; report "FAILED wireless disable $item"; return 1; }
        result "$item" skipped
    done
    report 'WIRED ONLY: wireless settings restored; independent features continue'
}

restore_wireless_mode() {
    [ -f "$TX/prior/wireless-mode" ] || return 0
    [ ! -L "$WIRELESS_OFF" ] || return 1
    case "$(cat "$TX/prior/wireless-mode")" in
        disabled) echo disabled > "$WIRELESS_OFF";;
        enabled) rm -f "$WIRELESS_OFF";;
        *) return 1;;
    esac
}
