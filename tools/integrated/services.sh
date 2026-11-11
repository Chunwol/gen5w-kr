# Supported NEMESIS service controls only. Never edit its registry/stop files.
Q_ACTIVE=0
Q_TRACKED=
Q_EPOCH=
q_track_load() {
    local boot line n=0 saved= ended=0 pid parent start state extra rc epoch_seen=0 epoch
    [ ! -L "$TX/service-processes" ] && [ ! -L "$TX/service-processes.tmp" ] || return 1
    [ -f "$TX/service-processes" ] || return 0
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    while :; do
        line=; IFS= read -r line; rc=$?
        if [ "$rc" != 0 ]; then [ -z "$line" ] || return 1; break; fi
        [ "$ended" = 0 ] || return 1
        if [ -z "$saved" ]; then
            case "$line" in ''|*[!0-9a-f-]*) return 1;; esac
            [ "${#line}" = 36 ] || return 1
            saved=$line; continue
        fi
        if [ "$epoch_seen" = 0 ]; then
            case "$line" in supervisor=*) epoch=${line#supervisor=};; *) return 1;; esac
            if [ "$epoch" != none ]; then
                case "$epoch" in *[!0-9:]*|:*|*:) return 1;; esac
                pid=${epoch%%:*}; start=${epoch#*:}
                case "$start" in *:*) return 1;; esac
                [ "$saved" != "$boot" ] || Q_EPOCH=$epoch
            fi
            epoch_seen=1; continue
        fi
        case "$line" in complete=*) [ "$line" = "complete=$n" ] || return 1; ended=1; continue;; esac
        n=$((n+1)); [ "$n" -le 2048 ] || return 1
        IFS=: read -r pid parent start state extra <<EOF
$line
EOF
        case "$pid:$parent:$start" in *[!0-9:]*|:*|*::*|*:) return 1;; esac
        [ -z "$extra" ] && [ "$line" = "$pid:$parent:$start:$state" ] || return 1
        case "$state" in R|S|D|Z|T|t|X|x|I|W|K|P) ;; *) return 1;; esac
        [ "$saved" != "$boot" ] || Q_TRACKED="$Q_TRACKED $line"
    done < "$TX/service-processes"
    [ "$ended" = 1 ]
}
q_track_save() {
    local boot line n=0
    [ ! -L "$TX/service-processes" ] && [ ! -L "$TX/service-processes.tmp" ] || return 1
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    (umask 077; { echo "$boot"; echo "supervisor=${Q_EPOCH:-none}"; for line in $Q_TRACKED; do echo "$line"; n=$((n+1)); done; echo "complete=$n"; } > "$TX/service-processes.tmp") &&
        chmod 600 "$TX/service-processes.tmp" && mv "$TX/service-processes.tmp" "$TX/service-processes" && sync
}
q_fail() { report "REFUSED service quiescence: $1"; return 1; }
q_uncertain() {
    local boot
    [ ! -L "$TX/service-uncertain" ] || return 1
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    (umask 077; echo "$boot" > "$TX/service-uncertain") && chmod 600 "$TX/service-uncertain"
}
q_check_uncertain() {
    local blocked= boot=
    [ ! -L "$TX/service-uncertain" ] || return 1
    [ -f "$TX/service-uncertain" ] || return 0
    IFS= read -r blocked < "$TX/service-uncertain" || return 1
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    case "$blocked" in ''|*[!0-9a-f-]*) return 1;; esac
    [ "${#blocked}" = 36 ] || return 1
    [ "$blocked" != "$boot" ] || { q_fail 'process evidence uncertain in this boot; cold reboot required'; return 1; }
}
q_keys() {
    local ident rest
    for ident in $1; do rest=${ident#*:*:}; echo "${ident%%:*}:${rest%:*}"; done
}
# Waits (at most IT_Q_DRAIN seconds, default 30) until no captured service
# process and no process in an owned NEMESIS session is alive. Read-only: it
# never signals. Uses the caller's roots, protected and owned_sessions.
q_owned_drain() {
    local waited=0 busy old pid current rest value entry sid
    while [ "$waited" -lt "${IT_Q_DRAIN:-30}" ]; do
        busy=
        for old in $roots; do
            pid=${old%%:*}; case "$protected" in *" $pid "*) continue;; esac
            current=$(q_identity "$pid") || continue
            rest=${current#*:*:}; value=${old#*:*:}
            [ "${rest%:*}" != "${value%:*}" ] || [ "${current##*:}" = Z ] || { busy=1; break; }
        done
        if [ -z "$busy" ]; then
            for entry in /proc/[0-9]*/stat; do
                pid=${entry#/proc/}; pid=${pid%/stat}
                sid=$(q_session "$pid") || continue
                case "$owned_sessions" in *" $sid "*) ;; *) continue;; esac
                current=$(q_identity "$pid") || continue
                [ "${current##*:}" != Z ] || continue
                q_worker_process "$pid" && continue
                busy=1; break
            done
        fi
        [ -n "$busy" ] || return 0
        sleep 1; waited=$((waited + 1))
    done
    report "NOTE service children still running after ${IT_Q_DRAIN:-30}s wait"
    return 0
}
q_worker_process() {
    local candidate=$1 hop ident parent rest
    for hop in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
        [ "$candidate" != "$self" ] || return 0
        if [ -n "$root_pid" ] && [ "$candidate" = "$root_pid" ]; then
            ident=$(q_identity "$candidate") || return 1
            rest=${ident#*:*:}; [ "${rest%:*}" = "$root_start" ] && return 0
        fi
        ident=$(q_identity "$candidate") || return 1
        rest=${ident#*:}; parent=${rest%%:*}
        [ "$parent" != 0 ] && [ "$parent" != "$candidate" ] || return 1
        candidate=$parent
    done
    return 1
}
# Return 0: at least the threshold, 1: known older, 2: unreadable.
# Bounded decimal fields prevent shell arithmetic overflow and octal parsing.
q_at_least() {
    local v=$1 patch=$2 major minor part
    case "$v" in ''|*[!0-9.]*|.*|*.|*..*) return 2;; esac
    major=${v%%.*}; [ "$major" != "$v" ] || return 2
    v=${v#*.}; minor=${v%%.*}
    if [ "$minor" = "$v" ]; then v=0; else v=${v#*.}; fi
    for part in "$major" "$minor" "$v"; do
        case "$part" in ''|*[!0-9]*|0?*) return 2;; esac
        [ "${#part}" -le 6 ] || return 2
    done
    [ "$major" -gt 1 ] && return 0
    [ "$major" -eq 1 ] || return 1
    [ "$minor" -gt 16 ] && return 0
    [ "$minor" -eq 16 ] || return 1
    [ "$v" -ge "$patch" ]
}
q_unknown_version() {
    report 'WARNING NEMESIS version unreadable; compatibility is not verified'
    local file=GEN5W-ALLOW-UNKNOWN-NEMESIS line extra
    [ -f "$file" ] && [ ! -L "$file" ] || {
        q_fail 'confirm unknown-version risk using GEN5W-ALLOW-UNKNOWN-NEMESIS; see installation guide'; return 1;
    }
    { IFS= read -r line && ! IFS= read -r extra && [ -z "$extra" ]; } < "$file" || return 1
    [ "$line" = I_ACCEPT_UNKNOWN_NEMESIS_VERSION ] || return 1
    report 'WARNING proceeding with explicit unknown-version acknowledgement; all other checks remain required'
}
q_version_gate() {
    local v rc=2
    if v=$("$NEM" version 2>/dev/null); then q_at_least "$v" "$1"; rc=$?; fi
    case "$rc" in 0) return 0;; 2) q_unknown_version; return $?;; esac
    q_fail "NEMESIS 1.16.$1 or newer required; recover first, then update NEMESIS separately"
}
q_install_version() { q_version_gate 7; }
# Recovery/removal retain the earlier service contract, not the install floor.
q_version() { q_version_gate 4; }
q_legacy_version() {
    local v
    v=$("$NEM" version 2>/dev/null) || return 1
    case "$v" in 1.16.0|1.16.1|1.16.2|1.16.3|1.15|1.15.0) return 0;; esac
    return 1
}
q_owned() {
    case "$1" in gen5w.kr.wireless|gen5w.kr.audio|gen5w.kr.bridge|gen5w.kr.core|gen5w.kr.timer|gen5w.kr.bluelink|gen5w.kr.drivelog|gen5w.kr.dongle|gen5w.kr.localhotspot|wireless.carplay.aa) return 0;; esac
    return 1
}
# Result is pid:parent:starttime:state; comm can contain spaces and parentheses.
q_identity() {
    local line rest n=0 parent= start= state= token
    case "$1" in ''|*[!0-9]*) return 1;; esac
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    rest=${line##*) }
    [ "$rest" != "$line" ] || return 1
    for token in $rest; do
        n=$((n+1))
        case "$n" in 1) state=$token;; 2) parent=$token;; 20) start=$token; break;; esac
    done
    case "$parent:$start" in *[!0-9:]*|:*|*:) return 1;; esac
    echo "$1:$parent:$start:$state"
}
q_session() {
    local line rest token n=0
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    rest=${line##*) }
    for token in $rest; do
        n=$((n+1)); [ "$n" != 4 ] || {
            case "$token" in ''|*[!0-9]*) return 1;; esac
            echo "$token"; return 0;
        }
    done
    return 1
}
q_inventory() {
    local line name mode status pid extra id seen=' ' count=0
    Q_LIST=$("$NEM" service list 2>/dev/null) || { q_fail 'service inventory unavailable'; return 1; }
    [ "${#Q_LIST}" -le 32768 ] || return 1
    Q_NAMES=; Q_ROOTS=; Q_INSTANCES=
    while IFS='|' read -r name mode status pid extra; do
        [ -n "$name" ] || continue
        id=${name%%/*}
        q_owned "$id" || continue
        count=$((count+1)); [ "$count" -le 64 ] || return 1
        case "$name" in "$id/"*) ;; *) return 1;; esac
        case "${name#*/}" in ''|*/*|*..*|*[!a-zA-Z0-9_.-]*) return 1;; esac
        case "$seen" in *" $name "*) return 1;; esac
        seen="$seen$name "
        case "$mode" in restart|background|once) ;; *) return 1;; esac
        case "$status" in running|stopped|failed) ;; *) return 1;; esac
        case "$pid" in ''|*[!0-9]*) return 1;; esac
        [ -z "$extra" ] || return 1
        [ "$status:$pid" != running:0 ] || return 1
        Q_NAMES="$Q_NAMES $name"
        if [ "$pid" != 0 ]; then
            line=$(q_identity "$pid") || return 1
            Q_ROOTS="$Q_ROOTS $line"
        fi
    done <<EOF
$Q_LIST
EOF
    # A missing registry entry must not make a registered package look idle.
    local file section svc kind
    for id in gen5w.kr.wireless gen5w.kr.audio gen5w.kr.bridge gen5w.kr.core gen5w.kr.timer gen5w.kr.bluelink gen5w.kr.drivelog gen5w.kr.dongle gen5w.kr.localhotspot wireless.carplay.aa; do
        file=$APPS/$id/NEMESIS.data
        [ ! -L "$APPS/$id" ] && [ ! -L "$file" ] || return 1
        [ -f "$file" ] || continue
        section=; svc=; kind=
        while IFS= read -r line || [ -n "$line" ]; do
            line=${line%$'\r'}
            case "$line" in
                '['*']') section=$line; svc=; kind=;;
                name=*) case "$section" in '[service.'*']')
                    svc=${line#name=}
                    case "$seen" in *" $id/$svc "*) ;; *) return 1;; esac
                    [ "$kind" != instance ] || Q_INSTANCES="$Q_INSTANCES $id/$svc ";; esac;;
                kind=*) case "$section" in '[service.'*']')
                    kind=${line#kind=}
                    [ "$kind" != instance ] || [ -z "$svc" ] || Q_INSTANCES="$Q_INSTANCES $id/$svc ";; esac;;
            esac
        done < "$file"
    done
}
q_probe_apps() {
    local entry arg
    Q_APP_RUNNING=
    # Android instance launch PIDs can be gone while their services still run.
    for entry in /proc/[0-9]*/cmdline; do
        [ -r "$entry" ] || { [ ! -e "$entry" ] && continue; return 1; }
        arg=
        if ! IFS= read -r -d '' -n 512 arg < "$entry" 2>/dev/null; then
            [ ! -e "$entry" ] || [ -z "$arg" ] || return 1
        fi
        case "$arg" in kr.gen5w.core|kr.gen5w.core:*) Q_APP_RUNNING="$Q_APP_RUNNING core";;
            kr.gen5w.wirelesshost|kr.gen5w.wirelesshost:*) Q_APP_RUNNING="$Q_APP_RUNNING bridge";; esac
    done
}
q_apps() {
    local am=${IT_AM:-/system/bin/am}
    if [ -x "$am" ]; then
        "$am" force-stop kr.gen5w.core >/dev/null 2>&1 || return 1
        "$am" force-stop kr.gen5w.wirelesshost >/dev/null 2>&1 || return 1
    fi
    q_probe_apps || return 1
    [ -z "$Q_APP_RUNNING" ] || { q_fail 'Android component remains running'; return 1; }
}
q_epoch() {
    local pid extra ident rest
    [ ! -L "$DATA/nemesis/svcmgr.pid" ] || return 1
    read -r pid extra < "$DATA/nemesis/svcmgr.pid" 2>/dev/null || return 1
    ident=$(q_identity "$pid") || return 1
    rest=${ident#*:*:}
    echo "$pid:${rest%:*}"
}
q_inventory_guard() {
    local first last
    first=$(q_epoch) || first=
    q_inventory || return 1
    if [ -z "$Q_NAMES$Q_TRACKED$Q_EPOCH" ]; then Q_CHECK_EPOCH=; return 0; fi
    [ -n "$first" ] || { q_fail 'supervisor identity unavailable'; return 1; }
    last=$(q_epoch) || return 1
    [ "$first" = "$last" ] || { q_fail 'supervisor changed during inventory'; return 1; }
    [ -z "$Q_EPOCH" ] || [ "$first" = "$Q_EPOCH" ] || { q_fail 'supervisor changed since previous barrier; cold reboot required'; return 1; }
    Q_EPOCH=$first; Q_CHECK_EPOCH=$first
}
q_barrier() {
    if q_check_uncertain && q_barrier_impl; then Q_FAILED=0; return 0; fi
    Q_FAILED=1
    q_fail 'stop proof incomplete; packages must not change'
}
# NEMESIS runs an instance service as a short "am start" shell and lists it as
# running only while that shell lives (it is killed after 8 s). Package install
# starts it, so it can end in the middle of a capture. Let it finish first; a
# launcher still alive afterwards is stopped like any other service.
q_instance_settle() {
    local pass line name rest status
    for pass in 1 2 3 4 5 6 7 8 9 10 11 12; do
        # The launcher can exit between the list and its /proc read: retry.
        q_inventory || { sleep 1; continue; }
        [ -n "$Q_INSTANCES" ] || return 0
        status=idle
        while IFS='|' read -r name rest; do
            case "$Q_INSTANCES" in *" $name "*)
                case "$rest" in *'|running|'*) status=busy;; esac;; esac
        done <<EOF
$Q_LIST
EOF
        [ "$status" = busy ] || return 0
        sleep 1
    done
    return 0
}
q_barrier_impl() {
    [ "$Q_ACTIVE" = 1 ] || return 0
    local name mark value before after entry current pid old roots protected self line rest p depth changed pass worker root_pid= root_start= arg valid argc=0 baseline_roots baseline_keys key unexpected=0 sid all_sessions=' ' owned_sessions=' '
    q_instance_settle
    q_inventory_guard || { q_fail 'invalid inventory'; return 1; }
    before=$Q_CHECK_EPOCH
    baseline_roots=$(q_keys "$Q_ROOTS")
    if [ -z "$Q_NAMES$Q_TRACKED" ]; then
        # No service metadata means no owned launchers; still check own APKs.
        [ ! -f "$APPS/gen5w.kr.core/NEMESIS.data" ] && [ ! -f "$APPS/gen5w.kr.wireless/NEMESIS.data" ] || q_apps || return 1
        return 0
    fi
    # Freeze a bounded process ancestry snapshot BEFORE stopping service parents.
    roots=$Q_ROOTS; protected=
    IFS= read -r self < /proc/self/stat || return 1
    self=${self%% *}; protected=" $self "
    for old in $Q_ROOTS; do
        pid=${old%%:*}; sid=$(q_session "$pid") || return 1
        if [ "$pid" != "$self" ]; then
            [ "$sid" = "$pid" ] || { q_fail 'launcher session ownership unknown'; return 1; }
            owned_sessions="$owned_sessions$sid "
        fi
    done
    Q_TREE=
    for entry in /proc/[0-9]*/stat; do
        pid=${entry#/proc/}; pid=${pid%/stat}
        line=$(q_identity "$pid") || { [ ! -e "/proc/$pid/stat" ] && continue; q_fail 'process identity unreadable'; return 1; }
        sid=$(q_session "$pid") || { [ ! -e "/proc/$pid/stat" ] && continue; return 1; }
        case "$all_sessions" in *" $sid "*) ;; *) all_sessions="$all_sessions$sid ";; esac
        Q_TREE="$Q_TREE $line"
        [ "${#Q_TREE}" -le 131072 ] || return 1
    done
    if [ -n "${GEN5W_RECOVERY_ROOT:-}" ]; then
        root_pid=${GEN5W_RECOVERY_ROOT%%:*}; root_start=${GEN5W_RECOVERY_ROOT#*:}
        worker=$self; valid=0
        for pass in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
            line=$(q_identity "$worker") || return 1
            if [ "$worker" = "$root_pid" ]; then
                rest=${line#*:*:}; [ "${rest%:*}" = "$root_start" ] || return 1
                # R43 -n reads a raw chunk and consumes later NUL-delimited
                # arguments. Delimiter-only reads are required for iteration.
                while IFS= read -r -d '' arg; do
                    argc=$((argc+1))
                    [ "$argc" -le 16 ] && [ "${#arg}" -le 512 ] || return 1
                    [ "$arg" != "$APPS/gen5w.kr.core/scripts/recovery-launch.sh" ] || valid=1
                done < "/proc/$root_pid/cmdline"
                break
            fi
            rest=${line#*:}; worker=${rest%%:*}
        done
        [ "$valid" = 1 ] || { q_fail 'unverified recovery launcher'; return 1; }
        protected="$protected$root_pid "
    fi
    # All descendants of this independent worker are protected, even when the
    # old collector was its ancestor. No process-group or name-based signals.
    for pass in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
        changed=0
        for line in $Q_TREE; do
            pid=${line%%:*}; rest=${line#*:}; p=${rest%%:*}
            case "$protected" in *" $p "*) case "$protected" in *" $pid "*) ;; *) protected="$protected$pid "; changed=1;; esac;; esac
            case " $roots " in *" $p:"*) case " $roots " in *" $pid:"*) ;; *) roots="$roots $line"; changed=1;; esac;; esac
        done
        [ "$changed" = 1 ] || break
    done
    [ "$changed" = 0 ] || { q_fail 'process ancestry exceeds safety bound'; return 1; }
    for line in $roots; do
        case " $Q_TRACKED " in *" $line "*) ;; *) Q_TRACKED="$Q_TRACKED $line";; esac
    done
    [ "${#Q_TRACKED}" -le 65536 ] || return 1
    q_track_save || return 1
    roots=$Q_TRACKED
    # The supervisor can restart a launcher without itself changing identity.
    q_inventory_guard || return 1
    [ "$(q_keys "$Q_ROOTS")" = "$baseline_roots" ] || {
        q_uncertain || return 1
        q_fail 'launcher changed during capture; cold reboot required'; return 1;
    }
    # Persist BEFORE the first stop. An interruption or early error must not
    # forget a stopped launcher's session ownership on same-boot recovery.
    q_uncertain || return 1
    for name in $Q_NAMES; do
        "$NEM" service stop "$name" >/dev/null 2>&1 || { q_fail 'service stop failed'; return 1; }
        mark=$DATA/nemesis/pids/${name//\//+}.stopped
        [ ! -L "$DATA/nemesis/pids" ] && [ ! -L "$mark" ] && [ -f "$mark" ] || return 1
        IFS= read -r value < "$mark" || return 1
        [ "$value" = 1 ] || return 1
    done
    # Instance services can outlive the launch command's PID. Stop only our APKs.
    q_apps || return 1
    # Parent stop does not guarantee child stop. Do not guess ownership or send
    # signals from a non-atomic /proc inspection. Refuse if descendants survive.
    sleep 1
    # A stopped service shell can leave a short-lived child behind (an orphaned
    # "sleep 15" between polls). It ends by itself: wait for it, without
    # signalling anything. The strict checks below still refuse what remains.
    q_owned_drain
    # Known launchers/children must already be gone before looking for late
    # children; otherwise they could fork after the last process scan.
    for old in $roots; do
        pid=${old%%:*}; case "$protected" in *" $pid "*) continue;; esac
        current=$(q_identity "$pid") || { [ ! -e "/proc/$pid/stat" ] && continue; q_uncertain; return 1; }
        rest=${current#*:*:}; value=${old#*:*:}
        [ "${rest%:*}" != "${value%:*}" ] || [ "${current##*:}" = Z ] || { q_fail 'owned child remains; reboot before retry'; return 1; }
    done
    baseline_keys=$(q_keys "$Q_TREE")
    baseline_keys=" ${baseline_keys//$'\n'/ } "
    # A child born after the snapshot may already have been reparented. Do not
    # declare it absent merely because the stopped launcher PID was unlinked.
    # Unexplained new identities are retained, not signalled or silently ignored.
    for entry in /proc/[0-9]*/stat; do
        pid=${entry#/proc/}; pid=${pid%/stat}
        current=$(q_identity "$pid") || {
            [ ! -e "/proc/$pid/stat" ] && continue
            q_uncertain; q_fail 'post-stop process unreadable; cold reboot required'; return 1;
        }
        [ "${current##*:}" != Z ] || continue
        rest=${current#*:*:}; key=${current%%:*}:${rest%:*}
        sid=$(q_session "$pid") || { [ ! -e "/proc/$pid/stat" ] && continue; q_uncertain; return 1; }
        # NEMESIS launches owned services with setsid(). A child retains that
        # session even after reparenting. Existing foreign sessions may keep
        # doing stock work; an owned or newly unexplained session cannot pass.
        case "$owned_sessions" in *" $sid "*) q_worker_process "$pid" && continue;;
            *)
                case "$baseline_keys" in *" $key "*) continue;; esac
                q_worker_process "$pid" && continue
                case "$all_sessions" in *" $sid "*) continue;; esac;;
        esac
        case " $Q_TRACKED " in *" $current "*) ;; *) Q_TRACKED="$Q_TRACKED $current";; esac
        unexpected=1
    done
    [ "${#Q_TRACKED}" -le 65536 ] || return 1
    q_track_save || return 1
    [ "$unexpected" = 0 ] || { q_uncertain; q_fail 'new process appeared during stop; proof ambiguous, cold reboot required'; return 1; }
    q_inventory_guard || return 1
    [ -z "$Q_ROOTS" ] || { q_fail 'service restarted'; return 1; }
    for name in $Q_NAMES; do
        mark=$DATA/nemesis/pids/${name//\//+}.stopped
        [ ! -L "$mark" ] && [ -f "$mark" ] || return 1
        IFS= read -r value < "$mark" || return 1
        [ "$value" = 1 ] || return 1
    done
    after=$(q_epoch) || return 1
    [ "$before" = "$after" ] || { q_fail 'supervisor restarted; reboot before retry'; return 1; }
    [ ! -L "$TX/service-uncertain" ] && rm -f "$TX/service-uncertain" || return 1
    report 'QUIESCENT: owned services stopped; installer worker retained'
}
q_begin() {
    q_version || return 1
    q_check_uncertain || return 1
    q_track_load || return 1
    [ ! -L "$TX/service-prior" ] && [ ! -L "$TX/service-prior.tmp" ] || return 1
    q_inventory_guard || return 1
    local name mode status pid extra prior_state app owner ident rest
    prior_state=$(cat "$TX/state" 2>/dev/null)
    Q_PRIOR_SAFE=0
    case "$prior_state" in ''|committed|rolled-back|capturing) Q_PRIOR_SAFE=1;; esac
    q_probe_apps || return 1
    : > "$TX/service-prior.tmp" && chmod 600 "$TX/service-prior.tmp" || return 1
    while IFS='|' read -r name mode status pid extra; do
        q_owned "${name%%/*}" || continue
        [ "$status" != running ] || echo "$name" >> "$TX/service-prior.tmp" || return 1
    done <<EOF
$Q_LIST
EOF
    # Instance launcher state is not the Android component's actual state.
    for app in $Q_APP_RUNNING; do
        case "$app" in core) name=gen5w.kr.core/core;; bridge) name=gen5w.kr.bridge/bridge;; *) return 1;; esac
        case " $Q_NAMES " in *" $name "*) echo "$name" >> "$TX/service-prior.tmp" || return 1;;
            *) q_fail 'running APK has no registered owner service'; return 1;; esac
    done
    mv "$TX/service-prior.tmp" "$TX/service-prior" || return 1
    [ ! -L "$DATA/nemesis/gen5wkr.install-hold" ] || return 1
    IFS= read -r extra < /proc/sys/kernel/random/boot_id || return 1
    IFS= read -r owner < "$TX/lock/pid" || return 1
    ident=$(q_identity "$owner") || return 1
    rest=${ident#*:*:}
    { echo "$extra"; echo "$owner:${rest%:*}"; } > "$DATA/nemesis/gen5wkr.install-hold" && chmod 644 "$DATA/nemesis/gen5wkr.install-hold" || return 1
    Q_ACTIVE=1
    q_barrier
}
q_resume() {
    [ "$Q_ACTIVE" = 1 ] || return 0
    local state name
    state=$(cat "$TX/state" 2>/dev/null)
    case "${Q_MUTATING:-0}:$state" in
        0:|0:idle|0:committed|0:capturing|0:rolled-back|1:rolled-back|1:committed) ;;
        *) return 0;;
    esac
    [ "${Q_FAILED:-0}" = 0 ] || { q_fail 'services held after incomplete stop proof; cold reboot required'; return 1; }
    [ ! -L "$DATA/nemesis/gen5wkr.install-hold" ] && rm -f "$DATA/nemesis/gen5wkr.install-hold" || return 1
    [ "${Q_MUTATING:-0}:$state" != 1:committed ] || return 0
    [ "${Q_PRIOR_SAFE:-0}" = 1 ] || return 0
    [ ! -L "$TX/service-prior" ] && [ -f "$TX/service-prior" ] || return 1
    while IFS= read -r name; do
        q_owned "${name%%/*}" || return 1
        case "${name#*/}" in ''|*/*|*..*|*[!a-zA-Z0-9_.-]*) return 1;; esac
        "$NEM" service start "$name" >/dev/null 2>&1 || { q_fail 'could not resume prior service; cold reboot required'; return 1; }
    done < "$TX/service-prior"
}
