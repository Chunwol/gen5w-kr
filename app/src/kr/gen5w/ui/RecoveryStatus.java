package kr.gen5w.ui;

import java.util.List;

/** Bounded collector facts, not authority to mutate the system. */
public final class RecoveryStatus {
    private final String state, available, reason, stage, request, result;
    private RecoveryStatus(List<String> lines) {
        state = choice(value(lines,"recovery_state"),"none|required|working|restored|unknown");
        available = choice(value(lines,"recovery_available"),"yes|no");
        reason = choice(value(lines,"recovery_reason"),"ready|runner-unavailable|snapshot-invalid|unsafe-path|busy|rollback-failed|interrupted|stock-recovery-required|unknown");
        stage = choice(value(lines,"recovery_stage"),"install|rollback|localhotspot|wireless|audio|bridge|core|timer|bluelink|drivelog|unknown");
        String n=value(lines,"recovery_request"); request=n.matches("[0-9]{1,10}")?n:"0";
        result=choice(value(lines,"recovery_result"),"none|working|restored|failed|unavailable|interrupted");
    }
    public static RecoveryStatus parse(List<String> lines) { return new RecoveryStatus(lines); }
    private static String value(List<String> lines,String key) {
        String result=""; boolean seen=false;
        if(lines!=null) for(String s:lines) if(s!=null && s.startsWith(key+"=")) {
            if(seen) return "";
            seen=true; result=s.substring(key.length()+1);
        }
        return result.length()<=64?result:"";
    }
    private static String choice(String s,String choices) {
        return s.length()>0 && ("|"+choices+"|").contains("|"+s+"|")?s:"unknown";
    }
    public String state(){return state;}
    public String displayState(boolean fresh){return fresh?state:"unknown";}
    public String reason(){return reason;}
    public String stage(){return stage;}
    public String request(){return request;}
    public String result(){return result;}
    public boolean canRequest(boolean fresh){return fresh && state.equals("required") && available.equals("yes") && !needsStockRecovery();}
    /** A stock recovery was interrupted: only the stock recovery USB finishes it. */
    public boolean needsStockRecovery(){return reason.equals("stock-recovery-required");}
    public boolean blocksChanges(){return state.equals("required") || state.equals("working");}
}
