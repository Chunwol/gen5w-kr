package kr.gen5w.portable;

import android.bluetooth.BluetoothProfile;
import android.content.ComponentName;
import android.content.Context;
import android.content.ServiceConnection;
import android.os.IBinder;
import com.daudio.app.dipo.telechips.CarPlayService;
import com.tcc.iap2.IIap2Listener;
import com.tcc.iap2.IIap2Service;
import com.tcc.iap2.Iap2NotiMsg;
import dalvik.system.DexFile;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import kr.gen5w.dipo.RelayBridge;

/** App-local, opt-in adapters. Loading this class installs nothing. */
public final class DipoAdapters {
  private static ProjectionAdapters.Transaction transaction;
  private static Field binderLocal, localOwner;
  private static Method notifications;
  private static Field detailsService, serviceOwner, serviceBluetooth;
  private static final ThreadLocal<Reconnect> reconnect =
      new ThreadLocal<Reconnect>();
  private static final class Reconnect {
    final Object owner, bluetooth;
    final String session;
    boolean missing;
    Reconnect(Object owner, Object bluetooth, String session) {
      this.owner = owner;
      this.bluetooth = bluetooth;
      this.session = session;
    }
  }
  private static Method uniqueMethod(Class<?> type, Class<?> returns,
                                     Class<?>... parameters) {
    Method selected = null;
    for (Method value : type.getDeclaredMethods()) {
      int flags = value.getModifiers();
      if (Modifier.isPublic(flags) && Modifier.isSynchronized(flags) &&
          !Modifier.isStatic(flags) && value.getReturnType() == returns &&
          java.util.Arrays.equals(value.getParameterTypes(), parameters)) {
        if (selected != null)
          throw new IllegalArgumentException("ambiguous synchronized method");
        selected = value;
      }
    }
    if (selected == null)
      throw new IllegalArgumentException("missing synchronized method");
    return selected;
  }
  private static final Object[] NONE = new Object[0];
  private DipoAdapters() {}

  private static final class Entry {
    final Method target, replacement;
    Entry(Method target, String replacement, Class<?>... parameters)
        throws Exception {
      this.target = target;
      this.replacement =
          DipoAdapters.class.getDeclaredMethod(replacement, parameters);
      if (Modifier.isStatic(target.getModifiers()) ||
          Modifier.isAbstract(target.getModifiers()) ||
          Modifier.isNative(target.getModifiers()) ||
          target.getReturnType() != this.replacement.getReturnType())
        throw new IllegalArgumentException("unsupported target " + target);
    }
  }
  private static Method method(Class<?> type, String name, Class<?> returns,
                               Class<?>... parameters) throws Exception {
    Method value = type.getDeclaredMethod(name, parameters);
    if (value.getReturnType() != returns)
      throw new IllegalArgumentException("return changed: " + value);
    return value;
  }
  private static Class<?> unique(List<Class<?>> candidates, String role) {
    if (candidates.size() != 1)
      throw new IllegalArgumentException("ambiguous/missing " + role + ": " +
                                         candidates.size());
    return candidates.get(0);
  }
  private static Field uniqueField(Class<?> owner, Class<?> type) {
    Field selected = null;
    for (Field field : owner.getDeclaredFields()) {
      if (!Modifier.isStatic(field.getModifiers()) && field.getType() == type) {
        if (selected != null)
          throw new IllegalArgumentException("ambiguous owner link");
        selected = field;
      }
    }
    if (selected == null)
      throw new IllegalArgumentException("missing owner link");
    return selected;
  }
  private static List<Class<?>> classes(Context context) throws Exception {
    List<Class<?>> values = new ArrayList<Class<?>>();
    DexFile dex = new DexFile(context.getPackageCodePath());
    try {
      Enumeration<String> names = dex.entries();
      while (names.hasMoreElements()) {
        String name = names.nextElement();
        if (name.startsWith("com.daudio.app.dipo."))
          values.add(Class.forName(name, false, context.getClassLoader()));
      }
    } finally {
      dex.close();
    }
    return values;
  }
  private static List<Entry> dipo(Context context) throws Exception {
    List<Class<?>> all = classes(context), binder = new ArrayList<Class<?>>(),
                   local = new ArrayList<Class<?>>(),
                   feature = new ArrayList<Class<?>>();
    Class<?> service =
        Class.forName("com.daudio.app.dipo.telechips.CarPlayService", false,
                      context.getClassLoader());
    for (Class<?> type : all) {
      if (type.isInterface() || Modifier.isAbstract(type.getModifiers()))
        continue;
      if (IIap2Listener.Stub.class.isAssignableFrom(type))
        binder.add(type);
      else if (IIap2Listener.class.isAssignableFrom(type))
        local.add(type);
      try {
        Method value = type.getDeclaredMethod("isSupportWirelessCarPlay");
        if (value.getReturnType() == Boolean.TYPE &&
            !Modifier.isStatic(value.getModifiers()))
          feature.add(type);
      } catch (NoSuchMethodException absent) { /* unrelated class */
      }
    }
    Class<?> binderType = unique(binder, "binder listener"),
             localType = unique(local, "local listener");
    Field binderLink = uniqueField(binderType, localType);
    // The local listener's synthetic outer owner also owns its
    // ServiceConnection.
    List<Class<?>> owners = new ArrayList<Class<?>>();
    for (Field field : localType.getDeclaredFields())
      if (field.isSynthetic() && !Modifier.isStatic(field.getModifiers()) &&
          field.getType().getName().startsWith("com.daudio.app.dipo."))
        owners.add(field.getType());
    Class<?> owner = unique(owners, "local listener owner");
    Field ownerLink = uniqueField(localType, owner);
    Method notifySetter = null;
    for (Method candidate : owner.getDeclaredMethods()) {
      Class<?>[] params = candidate.getParameterTypes();
      if (Modifier.isStatic(candidate.getModifiers()) &&
          candidate.isSynthetic() &&
          candidate.getReturnType() == Boolean.TYPE && params.length == 2 &&
          params[0] == owner && params[1] == Boolean.TYPE) {
        if (notifySetter != null)
          throw new IllegalArgumentException("ambiguous notification setter");
        notifySetter = candidate;
      }
    }
    if (notifySetter == null)
      throw new IllegalArgumentException("missing notification setter");
    binderLink.setAccessible(true);
    ownerLink.setAccessible(true);
    notifySetter.setAccessible(true);
    binderLocal = binderLink;
    localOwner = ownerLink;
    notifications = notifySetter;
    List<Class<?>> connections = new ArrayList<Class<?>>();
    for (Class<?> type : all)
      if (!type.isInterface() && !Modifier.isAbstract(type.getModifiers()) &&
          ServiceConnection.class.isAssignableFrom(type)) {
        for (Field field : type.getDeclaredFields())
          if (!Modifier.isStatic(field.getModifiers()) &&
              field.getType() == owner) {
            uniqueField(type, owner);
            connections.add(type);
            break;
          }
      }
    if (connections.isEmpty() || connections.size() > 8)
      throw new IllegalArgumentException(
          "missing/excess owner service connections");
    Class<?> wireless = unique(feature, "wireless capability");
    Class<?> dipoService =
        Class.forName("com.daudio.app.dipo.service.DipoService", false,
                      context.getClassLoader());
    List<Class<?>> bluetoothTypes = new ArrayList<Class<?>>();
    List<Method> detailMethods = new ArrayList<Method>();
    for (Class<?> type : all) {
      if (type.isInterface() || Modifier.isAbstract(type.getModifiers()))
        continue;
      if (BluetoothProfile.ServiceListener.class.isAssignableFrom(type)) {
        try {
          uniqueMethod(type, Void.TYPE, String.class);
          bluetoothTypes.add(type);
        } catch (IllegalArgumentException
                     unsupported) { /* not the saved-address manager */
        }
      }
      for (Method candidate : type.getDeclaredMethods())
        if (!Modifier.isStatic(candidate.getModifiers()) &&
            candidate.getReturnType() == Void.TYPE &&
            java.util.Arrays.equals(candidate.getParameterTypes(),
                                    new Class<?>[] {String.class, String.class,
                                                    String.class,
                                                    String.class}))
          detailMethods.add(candidate);
    }
    Class<?> bluetoothType =
        unique(bluetoothTypes, "Bluetooth address manager");
    if (detailMethods.size() != 1)
      throw new IllegalArgumentException("ambiguous session-details callback");
    Method details = detailMethods.get(0),
           identity = uniqueMethod(owner, String.class),
           saveAddress = uniqueMethod(bluetoothType, Void.TYPE, String.class);
    Field detailsLink = uniqueField(details.getDeclaringClass(), dipoService);
    if (!detailsLink.isSynthetic())
      throw new IllegalArgumentException("unreviewed session-details owner");
    Field ownerInService = uniqueField(dipoService, owner),
          bluetoothInService = uniqueField(dipoService, bluetoothType);
    detailsLink.setAccessible(true);
    ownerInService.setAccessible(true);
    bluetoothInService.setAccessible(true);
    detailsService = detailsLink;
    serviceOwner = ownerInService;
    serviceBluetooth = bluetoothInService;
    List<Entry> plan = new ArrayList<Entry>();
    plan.add(new Entry(method(service, "onSessionCreated", Void.TYPE),
                       "sessionCreated", Object.class, Integer.TYPE));
    plan.add(
        new Entry(method(service, "onSessionStarted", Void.TYPE, Integer.TYPE),
                  "sessionStarted", Object.class, Integer.TYPE, Integer.TYPE));
    plan.add(new Entry(
        method(service, "onSessionFinalized", Void.TYPE, Integer.TYPE),
        "sessionFinalized", Object.class, Integer.TYPE, Integer.TYPE));
    plan.add(new Entry(method(service, "oniAPSendMessage", Void.TYPE,
                              byte[].class, Integer.TYPE),
                       "fromCarPlay", Object.class, Object.class, Integer.TYPE,
                       Integer.TYPE));
    plan.add(new Entry(
        method(binderType, "connected", Void.TYPE, Integer.TYPE, String.class),
        "binderConnected", Object.class, Integer.TYPE, Object.class,
        Integer.TYPE));
    plan.add(new Entry(
        method(binderType, "disconnected", Void.TYPE, Integer.TYPE),
        "binderDisconnected", Object.class, Integer.TYPE, Integer.TYPE));
    plan.add(new Entry(method(binderType, "notify", Void.TYPE, Integer.TYPE,
                              Integer.TYPE, Integer.TYPE, Iap2NotiMsg.class),
                       "binderNotify", Object.class, Integer.TYPE, Integer.TYPE,
                       Integer.TYPE, Object.class, Integer.TYPE));
    plan.add(new Entry(
        method(localType, "connected", Void.TYPE, Integer.TYPE, String.class),
        "localConnected", Object.class, Integer.TYPE, Object.class,
        Integer.TYPE));
    plan.add(new Entry(
        method(localType, "disconnected", Void.TYPE, Integer.TYPE),
        "localDisconnected", Object.class, Integer.TYPE, Integer.TYPE));
    for (Class<?> connection : connections)
      plan.add(new Entry(method(connection, "onServiceConnected", Void.TYPE,
                                ComponentName.class, IBinder.class),
                         "serviceConnected", Object.class, Object.class,
                         Object.class, Integer.TYPE));
    plan.add(
        new Entry(method(wireless, "isSupportWirelessCarPlay", Boolean.TYPE),
                  "wirelessSupport", Object.class, Integer.TYPE));
    plan.add(new Entry(details, "sessionDetails", Object.class, Object.class,
                       Object.class, Object.class, Object.class, Integer.TYPE));
    plan.add(
        new Entry(identity, "reconnectIdentity", Object.class, Integer.TYPE));
    plan.add(new Entry(saveAddress, "saveAddress", Object.class, Object.class,
                       Integer.TYPE));
    return plan;
  }
  /**
   * Metadata-only dry run: no hook installation and no application class
   * initialization.
   */
  public static int validate(Context context) throws Exception {
    return dipo(context).size();
  }
  /**
   * Discover every target first, then install all or roll back in reverse
   * order.
   */
  public static synchronized boolean install(Context context) throws Throwable {
    ProjectionAdapters.Transaction attempt = beginInstall(context);
    if (attempt == null) return false;
    attempt.commit();
    return true;
  }
  public static synchronized ProjectionAdapters.Transaction beginInstall(Context context) throws Throwable {
    if (context == null)
      throw new NullPointerException("context");
    if (transaction != null && !transaction.isRolledBack()) {
      if (transaction.isCommitted()) return transaction;
      throw new ProjectionAdapters.RollbackFailure(
          new IllegalStateException("previous adapter transaction is unresolved"));
    }
    List<Entry> plan;
    String name = context.getPackageName();
    if ("com.daudio.app.dipo".equals(name))
      plan = dipo(context);
    else
      return null;
    transaction = new ProjectionAdapters.Transaction();
    try {
      for (Entry entry : plan)
        transaction.add(entry.target, entry.replacement);
      return transaction;
    } catch (Throwable failure) {
      try { transaction.rollback(); }
      catch (ProjectionAdapters.RollbackFailure rollback) {
        rollback.addSuppressed(failure);
        throw rollback;
      }
      throw failure;
    }
  }
  public static void sessionCreated(Object receiver, int handle)
      throws Throwable {
    RelayBridge.sessionCreated((CarPlayService)receiver);
    Hook.original(handle, receiver, NONE);
  }
  public static void sessionStarted(Object receiver, int transport, int handle)
      throws Throwable {
    RelayBridge.sessionStarted((CarPlayService)receiver, transport);
    Hook.original(handle, receiver, new Object[] {transport});
  }
  public static void sessionFinalized(Object receiver, int reason, int handle)
      throws Throwable {
    RelayBridge.sessionFinalized((CarPlayService)receiver);
    Hook.original(handle, receiver, new Object[] {reason});
  }
  public static void fromCarPlay(Object receiver, Object bytes, int length,
                                 int handle) throws Throwable {
    RelayBridge.fromCarPlay((CarPlayService)receiver, (byte[])bytes, length);
    Hook.original(handle, receiver, new Object[] {bytes, length});
  }
  public static void binderConnected(Object receiver, int component,
                                     Object name, int handle) throws Throwable {
    int mapped = RelayBridge.listenerComponent(component);
    if (mapped < 0) {
      try {
        notifications.invoke(null, localOwner.get(binderLocal.get(receiver)),
                             true);
      } catch (java.lang.reflect.InvocationTargetException failure) {
        throw failure.getCause();
      }
    }
    if (mapped >= 0)
      Hook.original(handle, receiver, new Object[] {mapped, name});
  }
  public static void binderDisconnected(Object receiver, int component,
                                        int handle) throws Throwable {
    if (!RelayBridge.ignoreListenerDisconnect(component))
      Hook.original(handle, receiver, new Object[] {component});
  }
  public static void binderNotify(Object receiver, int what, int arg1, int arg2,
                                  Object message, int handle) throws Throwable {
    if (!RelayBridge.dropListenerNotify(what))
      Hook.original(handle, receiver, new Object[] {what, arg1, arg2, message});
  }
  public static void localConnected(Object receiver, int component, Object name,
                                    int handle) throws Throwable {
    if (!RelayBridge.connected(component, (String)name))
      Hook.original(handle, receiver, new Object[] {component, name});
  }
  public static void localDisconnected(Object receiver, int component,
                                       int handle) throws Throwable {
    if (!RelayBridge.disconnected(component))
      Hook.original(handle, receiver, new Object[] {component});
  }
  public static void serviceConnected(Object receiver, Object name,
                                      Object binder, int handle)
      throws Throwable {
    boolean iap2 = false;
    if (name != null && binder != null) {
      try {
        iap2 = "com.tcc.iap2.IIap2Service".equals(
            ((IBinder)binder).getInterfaceDescriptor());
      } catch (
          android.os.RemoteException unavailable) { /* preserve original path */
      } catch (RuntimeException unavailable) {      /* preserve original path */
      }
    }
    if (iap2)
      RelayBridge.bind(IIap2Service.Stub.asInterface((IBinder)binder));
    Hook.original(handle, receiver, new Object[] {name, binder});
  }
  public static void sessionDetails(Object receiver, Object address,
                                    Object name, Object transport, Object extra,
                                    int handle) throws Throwable {
    Object service = detailsService.get(receiver);
    Reconnect previous = reconnect.get();
    Reconnect current =
        new Reconnect(service == null ? null : serviceOwner.get(service),
                      service == null ? null : serviceBluetooth.get(service),
                      (String)address);
    reconnect.set(current);
    try {
      Hook.original(handle, receiver,
                    new Object[] {address, name, transport, extra});
    } finally {
      if (previous == null)
        reconnect.remove();
      else
        reconnect.set(previous);
    }
  }
  public static String reconnectIdentity(Object receiver, int handle)
      throws Throwable {
    String original = (String)Hook.original(handle, receiver, NONE);
    Reconnect scope = reconnect.get();
    if (scope == null || scope.owner != receiver)
      return original;
    String selected = RelayBridge.reconnectAddress(original, scope.session);
    scope.missing = selected == null;
    return selected == null ? "" : selected;
  }
  public static void saveAddress(Object receiver, Object address, int handle)
      throws Throwable {
    Reconnect scope = reconnect.get();
    if (scope != null && scope.bluetooth == receiver && scope.missing &&
        "".equals(address))
      return;
    Hook.original(handle, receiver, new Object[] {address});
  }
  public static boolean wirelessSupport(Object receiver, int handle) {
    return false;
  }
}
