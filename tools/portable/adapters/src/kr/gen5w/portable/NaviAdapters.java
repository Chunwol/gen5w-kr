package kr.gen5w.portable;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** App-local adapter for com.mnsoft.navi: suppresses idle stock TBT overwrites while phone guidance is active. */
public final class NaviAdapters {
  static final String ACTION_PHONE_GUIDING = "kr.gen5w.action.PHONE_GUIDING";
  static final String PERM_HUD_INPUT = "kr.gen5w.permission.HUD_INPUT";
  static final long LEASE_MS = 15000L;
  private static final long MAX_CLOCK_SKEW_MS = 1000L;

  // Strict lock ordering: always acquire OUTPUT_LOCK before STATE_LOCK; never hold STATE_LOCK across Hook.original().
  private static final Object OUTPUT_LOCK = new Object();
  private static final Object STATE_LOCK = new Object();
  private static volatile ProjectionAdapters.Transaction transaction;
  private static volatile Context appContext;
  private static boolean stockActive;
  private static long yieldedAtMs;
  private static long lastSentAtMs;
  private static long guidingUntilMs;
  private static volatile boolean receiverScheduled;
  private static volatile boolean receiverRegistered;

  private NaviAdapters() {}

  // USB drive log (source 3, event 38): what the stock navigation wrote to the cluster while the
  // phone owned it, and whether it was dropped. Logged on a decision change or every 10 s per kind.
  static final int KIND_TBT = 1, KIND_SUB = 2, KIND_SUB2 = 3, KIND_SUB2C = 4, KIND_REMAIN = 5, KIND_TEXT = 6;
  private static final long[] DRIVE_AT = new long[7];
  private static final int[] DRIVE_STATE = new int[7];

  static void driveLog(int kind, boolean dropped, long a, long b) {
    long now = SystemClock.elapsedRealtime();
    synchronized (DRIVE_AT) {
      int state = dropped ? 2 : 1;
      if (DRIVE_STATE[kind] == state && now - DRIVE_AT[kind] < 10000L) return;
      DRIVE_STATE[kind] = state;
      DRIVE_AT[kind] = now;
    }
    try {
      android.util.Log.i("Gen5wDrive", "D1|" + now + "|3|38|" + kind + "|" + (dropped ? 1 : 0)
          + "|" + a + "|" + b + "|" + (stockActive ? 1 : 0) + "|0");
    } catch (Throwable ignored) {}
  }

  private static int lastIcon = Integer.MIN_VALUE, lastSide = Integer.MIN_VALUE, lastCombi = Integer.MIN_VALUE;

  /** Event 42: every change of the stock navigation icon (code only, no position), so a real-car
   *  drive under/over passes records which stock icon codes the native engine actually sends. */
  static void iconLog(int displayType, int sideStreet, int combiSideStreet, float distance, int distanceErr) {
    synchronized (DRIVE_AT) {
      if (displayType == lastIcon && sideStreet == lastSide && combiSideStreet == lastCombi) return;
      lastIcon = displayType; lastSide = sideStreet; lastCombi = combiSideStreet;
    }
    try {
      long d = Float.isNaN(distance) ? -1L : (long) Math.max(-1f, Math.min(distance, 99999999f));
      android.util.Log.i("Gen5wDrive", "D1|" + SystemClock.elapsedRealtime() + "|3|42|" + displayType + "|"
          + sideStreet + "|" + combiSideStreet + "|" + d + "|" + distanceErr + "|" + (stockActive ? 1 : 0));
    } catch (Throwable ignored) {}
  }


  private static final java.util.HashMap<String, String> RAW_LAST = new java.util.HashMap<String, String>();

  /** Full-value record of every stock cluster call (on change per method) for stock-vs-phone comparison. */
  static void rawLog(String method, Object... args) {
    try {
      StringBuilder b = new StringBuilder();
      for (int i = 0; i < args.length; i++) { if (i > 0) b.append(' '); dumpValue(b, args[i], 0); }
      String v = b.toString();
      synchronized (RAW_LAST) {
        if (v.equals(RAW_LAST.get(method))) return;
        RAW_LAST.put(method, v);
      }
      android.util.Log.i("Gen5wNavi", "STOCK " + method + (stockActive ? " active " : " idle ") + v);
    } catch (Throwable ignored) {}
  }

  static void dumpValue(StringBuilder b, Object o, int depth) {
    if (o == null) { b.append("null"); return; }
    if (o instanceof byte[]) {
      byte[] a = (byte[]) o; b.append("bytes[").append(a.length).append("]=");
      for (int i = 0; i < a.length; i++) { int x = a[i] & 255; b.append(Character.forDigit(x >> 4, 16)).append(Character.forDigit(x & 15, 16)); }
      return;
    }
    if (o instanceof int[]) { b.append(java.util.Arrays.toString((int[]) o)); return; }
    if (o instanceof Number || o instanceof Boolean || o instanceof Character) { b.append(o); return; }
    if (o instanceof CharSequence) { b.append('"').append(o).append('"'); return; }
    if (o.getClass().isArray()) {
      int n = java.lang.reflect.Array.getLength(o); b.append('[');
      for (int i = 0; i < n; i++) { if (i > 0) b.append(','); dumpValue(b, java.lang.reflect.Array.get(o, i), depth + 1); }
      b.append(']'); return;
    }
    if (depth > 2) { b.append(o); return; }
    b.append(o.getClass().getSimpleName()).append('{');
    boolean first = true;
    for (java.lang.reflect.Field f : o.getClass().getDeclaredFields()) {
      if (java.lang.reflect.Modifier.isStatic(f.getModifiers())) continue;
      try {
        f.setAccessible(true);
        if (!first) b.append(',');
        first = false;
        b.append(f.getName()).append('=');
        dumpValue(b, f.get(o), depth + 1);
      } catch (Throwable e) { b.append('?'); }
    }
    b.append('}');
  }

  private static void ensureReceiver() {
    if (!receiverRegistered && !receiverScheduled) {
      scheduleReceiver(appContext, transaction);
    }
  }

  private static boolean isPhoneGuidingLocked() {
    synchronized (STATE_LOCK) {
      if (stockActive) return false;
      return guidingUntilMs > 0L && SystemClock.elapsedRealtime() < guidingUntilMs;
    }
  }

  static boolean isPhoneGuiding() {
    ensureReceiver();
    return isPhoneGuidingLocked();
  }

  static void setPhoneGuiding(boolean active) {
    setPhoneGuiding(active, SystemClock.elapsedRealtime());
  }

  static void setPhoneGuiding(boolean active, long sentAtMs) {
    long now = SystemClock.elapsedRealtime();
    synchronized (STATE_LOCK) {
      if (sentAtMs < 0L || sentAtMs > now + MAX_CLOCK_SKEW_MS) return;
      if (lastSentAtMs > 0L && sentAtMs < lastSentAtMs) return;
      if (!active) {
        lastSentAtMs = sentAtMs;
        guidingUntilMs = 0L;
        return;
      }
      if (stockActive) return;
      if (yieldedAtMs > 0L && sentAtMs <= yieldedAtMs) return;
      long expiry = sentAtMs + LEASE_MS;
      if (expiry <= now) return;
      lastSentAtMs = sentAtMs;
      guidingUntilMs = expiry;
    }
  }

  public static synchronized boolean install(Context context) throws Throwable {
    beginInstall(context).commit();
    return true;
  }

  public static synchronized ProjectionAdapters.Transaction beginInstall(
      final Context context) throws Throwable {
    if (context == null) throw new NullPointerException("context");
    appContext = context;
    if (transaction != null && !transaction.isRolledBack()) {
      if (transaction.isCommitted()) {
        scheduleReceiver(context, transaction);
        return transaction;
      }
      throw new ProjectionAdapters.RollbackFailure(
          new IllegalStateException("previous adapter transaction is unresolved"));
    }
    Class<?> nc = Class.forName(
        "com.hkmc.cluster.NavigationCluster", false, context.getClassLoader());
    Method tbtInfo = findVoid(nc, "updateTBTInfo",
        Integer.TYPE, Integer.TYPE, Float.TYPE, Float.TYPE,
        Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE);
    if (tbtInfo == null)
      throw new IllegalStateException("NavigationCluster.updateTBTInfo missing");

    ProjectionAdapters.Transaction tx = new ProjectionAdapters.Transaction();
    try {
      tx.add(tbtInfo, NaviAdapters.class.getDeclaredMethod(
          "updateTBTInfo", Object.class, Integer.TYPE, Integer.TYPE, Float.TYPE,
          Float.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
          Integer.TYPE, Integer.TYPE));

      installIfPresent(tx, nc, "updateTBTSubInfo",
          NaviAdapters.class.getDeclaredMethod(
              "dropTbtSubInfo9", Object.class, Float.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE),
          Float.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
          Integer.TYPE, Integer.TYPE, Float.TYPE, Integer.TYPE);

      installIfPresent(tx, nc, "updateTBTSubInfo",
          NaviAdapters.class.getDeclaredMethod(
              "dropTbtSubInfo10", Object.class, Float.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE),
          Float.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
          Integer.TYPE, Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE);

      installIfPresent(tx, nc, "updateTBTSubInfo2",
          NaviAdapters.class.getDeclaredMethod(
              "dropTbtSubInfo2_7", Object.class, Float.TYPE, Integer.TYPE,
              Float.TYPE, Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE),
          Float.TYPE, Integer.TYPE, Float.TYPE, Integer.TYPE, Float.TYPE,
          Integer.TYPE, Integer.TYPE);

      installIfPresent(tx, nc, "updateTBTSubInfo2",
          NaviAdapters.class.getDeclaredMethod(
              "dropTbtSubInfo2_9", Object.class, Float.TYPE, Integer.TYPE,
              Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE, Float.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE),
          Float.TYPE, Integer.TYPE, Integer.TYPE, Float.TYPE, Integer.TYPE,
          Integer.TYPE, Float.TYPE, Integer.TYPE, Integer.TYPE);

      installIfPresent(tx, nc, "updateTBTSubInfo2C",
          NaviAdapters.class.getDeclaredMethod(
              "dropTbtSubInfo2C", Object.class, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE),
          Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
          Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE);

      installIfPresent(tx, nc, "updateRemainDis",
          NaviAdapters.class.getDeclaredMethod(
              "dropRemainDis", Object.class, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE),
          Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE);

      // Four-argument API delegates to this six-argument method (NavigationCluster:1693).
      installIfPresent(tx, nc, "updateSTD_NAVI_PE_00_Info",
          NaviAdapters.class.getDeclaredMethod("dropPe00", Object.class,
              Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE,
              Integer.TYPE, Integer.TYPE, Integer.TYPE),
          Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE, Integer.TYPE);

      Method oneArg = NaviAdapters.class.getDeclaredMethod(
          "dropOneArg", Object.class, Object.class, Integer.TYPE);
      installSingleRefIfPresent(tx, nc, "updateTPCrossroadName", oneArg);
      installSingleRefIfPresent(tx, nc, "updateTPFlexibleDestinationName", oneArg);
      installSingleRefIfPresent(tx, nc, "updateTPTurnList", oneArg);
      installSingleRefIfPresent(tx, nc, "updateTPTurnListNew", oneArg);
      installSingleRefIfPresent(tx, nc, "updateTPLaneInfo", oneArg);
      installSingleRefIfPresent(tx, nc, "updateLaneInfo", oneArg);

      scheduleReceiver(context, tx);
      transaction = tx;
      return tx;
    } catch (RuntimeException failure) {
      rollback(tx, failure);
      throw failure;
    } catch (Error failure) {
      rollback(tx, failure);
      throw failure;
    }
  }

  private static void rollback(ProjectionAdapters.Transaction tx, Throwable failure) {
    try {
      tx.rollback();
    } catch (ProjectionAdapters.RollbackFailure r) {
      r.addSuppressed(failure);
      throw r;
    }
  }

  private static synchronized void scheduleReceiver(
      final Context context, final ProjectionAdapters.Transaction tx) {
    if (receiverScheduled || receiverRegistered || context == null || tx == null) return;
    Looper looper = null;
    try {
      looper = context.getMainLooper();
    } catch (Throwable ignored) {}
    if (looper == null) return;
    receiverScheduled = true;
    final Handler handler = new Handler(looper);
    boolean posted = false;
    try {
      posted = handler.post(new Runnable() {
        private int retries;
        public void run() {
          boolean registered = false;
          boolean rescheduled = false;
          try {
            if (tx.isRolledBack()) return;
            if (!tx.isCommitted()) {
              if (retries++ < 20) {
                try {
                  rescheduled = handler.postDelayed(this, 50L);
                } catch (Throwable ignored) {}
              }
              return;
            }
            context.registerReceiver(new BroadcastReceiver() {
              public void onReceive(Context c, Intent intent) {
                if (intent != null && ACTION_PHONE_GUIDING.equals(intent.getAction())) {
                  setPhoneGuiding(
                      intent.getBooleanExtra("active", false),
                      intent.getLongExtra("ts", -1L));
                }
              }
            }, new IntentFilter(ACTION_PHONE_GUIDING), PERM_HUD_INPUT, null);
            registered = true;
          } catch (Throwable ignored) {
          } finally {
            synchronized (NaviAdapters.class) {
              if (registered) {
                receiverRegistered = true;
                receiverScheduled = false;
              } else if (!rescheduled) {
                receiverScheduled = false;
              }
            }
          }
        }
      });
    } finally {
      if (!posted) receiverScheduled = false;
    }
  }

  private static Method findVoid(Class<?> type, String name, Class<?>... params) {
    try {
      Method m = type.getDeclaredMethod(name, params);
      if (Modifier.isAbstract(m.getModifiers())
          || Modifier.isNative(m.getModifiers())
          || m.getReturnType() != Void.TYPE) return null;
      return m;
    } catch (NoSuchMethodException e) {
      return null;
    }
  }

  private static void installIfPresent(ProjectionAdapters.Transaction tx,
      Class<?> nc, String name, Method replacement, Class<?>... params) {
    Method m = findVoid(nc, name, params);
    if (m != null) tx.add(m, replacement);
  }

  private static void installSingleRefIfPresent(ProjectionAdapters.Transaction tx,
      Class<?> nc, String name, Method replacement) {
    for (Method m : nc.getDeclaredMethods()) {
      if (!name.equals(m.getName())) continue;
      if (Modifier.isAbstract(m.getModifiers())
          || Modifier.isNative(m.getModifiers())
          || m.getReturnType() != Void.TYPE) continue;
      Class<?>[] p = m.getParameterTypes();
      if (p.length == 1 && !p[0].isPrimitive()) {
        tx.add(m, replacement);
        return;
      }
    }
  }

  public static void updateTBTInfo(Object receiver, int displayType, int sideStreet,
      float direction, float distance, int distanceErr, int combiSideStreet,
      int scale, int barGraphLevel, int barGraphLevelErr, int handle) throws Throwable {
    ensureReceiver();
    synchronized (OUTPUT_LOCK) {
      boolean suppress = false;
      synchronized (STATE_LOCK) {
        if (displayType != 8 && displayType != 0) {
          // Stock navigation began an active route turn; immediately yield cluster control.
          stockActive = true;
          guidingUntilMs = 0L;
          yieldedAtMs = SystemClock.elapsedRealtime();
        } else {
          stockActive = false;
          suppress = guidingUntilMs > 0L && SystemClock.elapsedRealtime() < guidingUntilMs;
        }
      }
      driveLog(KIND_TBT, suppress, displayType, distanceErr);
      rawLog("updateTBTInfo", displayType, sideStreet, direction, distance, distanceErr, combiSideStreet, scale, barGraphLevel, barGraphLevelErr);
      iconLog(displayType, sideStreet, combiSideStreet, distance, distanceErr);
      if (suppress) return;
      Hook.original(handle, receiver, new Object[] {
          Integer.valueOf(displayType), Integer.valueOf(sideStreet),
          Float.valueOf(direction), Float.valueOf(distance),
          Integer.valueOf(distanceErr), Integer.valueOf(combiSideStreet),
          Integer.valueOf(scale), Integer.valueOf(barGraphLevel),
          Integer.valueOf(barGraphLevelErr)});
    }
  }

  /** Stock message/a.java:1146-1162 forwards the complete engine packet without
   * a route-state gate. Never suppress parking or HVAC information: it is independent
   * of phone navigation. Such a packet may replace the phone tunnel; no timer fights it. */
  public static void dropPe00(Object receiver, int distance, int roadClass, int exist,
      int parking, int warning, int type, int handle) throws Throwable {
    ensureReceiver();
    rawLog("PE_00", distance, roadClass, exist, parking, warning, type);
    synchronized (OUTPUT_LOCK) {
      if (isPhoneGuidingLocked() && parking == 0 && warning == 0 && type == 0) return;
      Hook.original(handle, receiver, new Object[] {
          Integer.valueOf(distance), Integer.valueOf(roadClass), Integer.valueOf(exist),
          Integer.valueOf(parking), Integer.valueOf(warning), Integer.valueOf(type)});
    }
  }

  public static void dropTbtSubInfo9(Object receiver, float distance, int distanceErr,
      int unit, int hours, int minutes, int timeType, int timeFormat,
      float compassDegree, int compassDegreeErr, int handle) throws Throwable {
    ensureReceiver();
    rawLog("updateTBTSubInfo9", distance, distanceErr, unit, hours, minutes, timeType, timeFormat, compassDegree, compassDegreeErr);
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_SUB, drop, distanceErr, (long) distance);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Float.valueOf(distance), Integer.valueOf(distanceErr),
          Integer.valueOf(unit), Integer.valueOf(hours), Integer.valueOf(minutes),
          Integer.valueOf(timeType), Integer.valueOf(timeFormat),
          Float.valueOf(compassDegree), Integer.valueOf(compassDegreeErr)});
    }
  }

  public static void dropTbtSubInfo10(Object receiver, float distance, int distanceErr,
      int unit, int hours, int minutes, int timeType, int timeFormat,
      float compassDegree, int compassDegreeErr, int estPointType,
      int handle) throws Throwable {
    ensureReceiver();
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_SUB, drop, distanceErr, (long) distance);
      rawLog("updateTBTSubInfo10", distance, distanceErr, unit, hours, minutes, timeType, timeFormat, compassDegree, compassDegreeErr, estPointType);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Float.valueOf(distance), Integer.valueOf(distanceErr),
          Integer.valueOf(unit), Integer.valueOf(hours), Integer.valueOf(minutes),
          Integer.valueOf(timeType), Integer.valueOf(timeFormat),
          Float.valueOf(compassDegree), Integer.valueOf(compassDegreeErr),
          Integer.valueOf(estPointType)});
    }
  }

  public static void dropTbtSubInfo2_7(Object receiver, float p1, int p1Err,
      float p2, int p2Err, float p3, int p3Err, int unit, int handle) throws Throwable {
    ensureReceiver();
    rawLog("updateTBTSubInfo2_7", p1, p1Err, p2, p2Err, p3, p3Err, unit);
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_SUB2, drop, p1Err, (long) p1);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Float.valueOf(p1), Integer.valueOf(p1Err), Float.valueOf(p2),
          Integer.valueOf(p2Err), Float.valueOf(p3), Integer.valueOf(p3Err),
          Integer.valueOf(unit)});
    }
  }

  public static void dropTbtSubInfo2_9(Object receiver, float p1, int p1Err,
      int p1Unit, float p2, int p2Err, int p2Unit, float p3, int p3Err,
      int p3Unit, int handle) throws Throwable {
    ensureReceiver();
    rawLog("updateTBTSubInfo2_9", p1, p1Err, p1Unit, p2, p2Err, p2Unit, p3, p3Err, p3Unit);
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_SUB2, drop, p1Err, (long) p1);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Float.valueOf(p1), Integer.valueOf(p1Err), Integer.valueOf(p1Unit),
          Float.valueOf(p2), Integer.valueOf(p2Err), Integer.valueOf(p2Unit),
          Float.valueOf(p3), Integer.valueOf(p3Err), Integer.valueOf(p3Unit)});
    }
  }

  public static void dropTbtSubInfo2C(Object receiver, int u1, int f1, int i1,
      int u2, int f2, int i2, int u3, int f3, int i3, int handle) throws Throwable {
    ensureReceiver();
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_SUB2C, drop, u1, i1);
      rawLog("updateTBTSubInfo2C", u1, f1, i1, u2, f2, i2, u3, f3, i3);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Integer.valueOf(u1), Integer.valueOf(f1), Integer.valueOf(i1),
          Integer.valueOf(u2), Integer.valueOf(f2), Integer.valueOf(i2),
          Integer.valueOf(u3), Integer.valueOf(f3), Integer.valueOf(i3)});
    }
  }

  public static void dropRemainDis(Object receiver, int rem, int unit,
      int dec, int tg, int handle) throws Throwable {
    ensureReceiver();
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_REMAIN, drop, rem, unit);
      rawLog("updateRemainDis", rem, unit, dec, tg);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {
          Integer.valueOf(rem), Integer.valueOf(unit),
          Integer.valueOf(dec), Integer.valueOf(tg)});
    }
  }

  public static void dropOneArg(Object receiver, Object arg, int handle) throws Throwable {
    ensureReceiver();
    synchronized (OUTPUT_LOCK) {
      boolean drop = isPhoneGuidingLocked();
      driveLog(KIND_TEXT, drop, 0, 0);
      rawLog("oneArg:" + (arg == null ? "null" : arg instanceof byte[] ? "bytes" + ((byte[]) arg).length : arg.getClass().getSimpleName()), arg);
      if (drop) return;
      Hook.original(handle, receiver, new Object[] {arg});
    }
  }
}
