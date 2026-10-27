package kr.gen5w.core;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class StartReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "com.hkmc.intent.action.SYSTEM_POWERON".equals(action)) {
            context.startService(new Intent(context, CoreService.class).setAction(action));
        }
    }
}
