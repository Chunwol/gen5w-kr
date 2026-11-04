package kr.gen5w.wireless;

import android.os.SystemClock;
import android.util.Log;

/** Keep in sync with the core schema; no device identifiers or free text. */
final class DriveLog {
    private DriveLog() {}
    static void bridge(int event, long a, long b, long c, long d, long e, long f) {
        Log.i("Gen5wDrive", "D1|" + SystemClock.elapsedRealtime() + "|1|" + event
                + "|" + a + "|" + b + "|" + c + "|" + d + "|" + e + "|" + f);
    }
}
