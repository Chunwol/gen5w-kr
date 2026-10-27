package kr.gen5w.probe;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Starts the probe after boot and after the head unit's quick power-on. */
public final class StartReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent i) {
        c.startService(new Intent(c, ProbeService.class));
    }
}
