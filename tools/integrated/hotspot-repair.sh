# Called under the existing transaction lock; never touches firmware/packages.
repair_hotspot() {
    local id=gen5w.kr.hotspot dex output rc
    check_stage_tree "$id" || { result "$id" failed; report 'FAILED hotspot repair: staged integrity'; return 1; }
    dex=$(pwd)/checks/$id/app/match.dex
    case "$dex" in *[!a-zA-Z0-9_./-]*) result "$id" failed; report 'REFUSED hotspot repair: unsupported package path'; return 1;; esac
    [ -f "$dex" ] && [ ! -L "$dex" ] || { result "$id" failed; report 'FAILED hotspot repair: helper missing'; return 1; }
    output=$("$NEM" root 1000 -c "CLASSPATH=$dex app_process /system/bin kr.gen5w.hotspot.HotspotMatch apply" 2>/dev/null)
    rc=$?
    case "$output" in
        *'RESULT applied'*|*'RESULT already-match'*)
            [ "$rc" = 0 ] || { result "$id" failed; report 'FAILED hotspot repair: command exit status'; return 1; }
            result "$id" applied
            report 'APPLIED hotspot repair: configuration matches; phone connection unverified';;
        *'carplay-settings-missing'*) result "$id" failed; report 'FAILED hotspot repair: CarPlay settings unavailable; connect paired phone and retry'; return 1;;
        *'ap-did-not-stop'*) result "$id" failed; report 'FAILED hotspot repair: hotspot stop timeout'; return 1;;
        *) result "$id" failed; report 'FAILED hotspot repair: Wi-Fi helper could not confirm matching settings'; return 1;;
    esac
}
auto_hotspot_recovery() {
    report 'Automatic recovery: previous system state preserved; checking hotspot configuration'
    echo hotspot-only > "$TX/recovery-mode"
    repair_hotspot || return 1
    set_state hotspot-repaired
    report 'LIMITED RESULT: hotspot repaired; full installation was not completed'
}
