package kr.gen5w.hud;

import java.util.Calendar;
import java.util.TimeZone;

/** Arrival clock for the stock TBT sub-info packet (0x4D: hours, minutes, timeType 1, 24-hour format). */
public final class TimeFrame {
    /** Longest remaining time shown; longer or negative values read as "none". */
    public static final long MAX_SECONDS = 99L * 3600L;
    private TimeFrame() {}

    /** Local arrival clock {hours, minutes} for a trip ending {@code remainingSeconds} from now, or null. */
    public static int[] arrival(long nowMillis, long remainingSeconds, TimeZone zone) {
        if (remainingSeconds < 0 || remainingSeconds > MAX_SECONDS || zone == null) return null;
        Calendar c = Calendar.getInstance(zone);
        c.setTimeInMillis(nowMillis + remainingSeconds * 1000L);
        return new int[]{c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE)};
    }
}
