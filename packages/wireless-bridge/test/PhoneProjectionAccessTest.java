import kr.gen5w.wireless.PhoneProjectionAccess;
import kr.gen5w.wireless.StockProjectionSession;

public final class PhoneProjectionAccessTest {
    private static void check(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }

    public static final class FakeManager {
        String connected = "";
        int wirelessState;
        public String getCPConnectedBTAddress() { return connected; }
        public int getWirelessConnectState() { return wirelessState; }
    }

    private static PhoneProjectionAccess.ServiceProvider provider(final Object manager) {
        return new PhoneProjectionAccess.ServiceProvider() {
            public Object get(String name) { return "phoneprojection".equals(name) ? manager : null; }
        };
    }

    private static final class FakeProfileProvider implements PhoneProjectionAccess.ProfileProvider {
        PhoneProjectionAccess.Profile profile;
        public PhoneProjectionAccess.Profile find(String address) { return profile; }
    }

    private static final class FakeActionSender implements PhoneProjectionAccess.ActionSender {
        boolean allowed = true;
        int sends;
        String action;
        String packageName;
        String extra;
        String address;
        public boolean send(String action, String packageName, String extra, String address) {
            if (!allowed) return false;
            sends++;
            this.action = action;
            this.packageName = packageName;
            this.extra = extra;
            this.address = address;
            return true;
        }
    }

    public static void main(String[] args) {
        FakeManager manager = new FakeManager();
        PhoneProjectionAccess.ServiceProvider provider = provider(manager);
        StockProjectionSession.Observation state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(state.result == StockProjectionSession.Result.INVOKED && state.serviceAvailable,
                "OEM manager and required methods observed");
        check(!state.projectionActiveForCandidate && !state.otherProjectionActive,
                "empty connected address is not an active projection");
        manager.connected = null;
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(state.result == StockProjectionSession.Result.INVOKED && !state.projectionActiveForCandidate,
                "null connected address means no active projection");
        manager.connected = "candidate";
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(!state.projectionActiveForCandidate,
                "a remembered address without CONNECTED state is not active");
        manager.wirelessState = 3;
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(state.projectionActiveForCandidate && !state.otherProjectionActive,
                "matching address and OEM CONNECTED state are active");
        manager.connected = "another-device";
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(!state.projectionActiveForCandidate && state.otherProjectionActive,
                "another OEM connected address blocks candidate");
        manager.connected = "candidate";
        manager.wirelessState = 2;
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(!state.projectionActiveForCandidate && state.projectionConnectingForCandidate &&
                !state.otherProjectionActive,
                "same-address OEM CONNECTING state is observed without classifying it as foreign");
        manager.connected = "another-device";
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(!state.projectionConnectingForCandidate && state.otherProjectionActive,
                "another address connecting remains a foreign projection");
        manager.connected = "candidate";
        manager.wirelessState = 1;
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(!state.projectionConnectingForCandidate && state.otherProjectionActive,
                "OEM CANCEL state fails closed instead of triggering another connect");
        manager.wirelessState = 9;
        state = PhoneProjectionAccess.inspect(provider, "candidate");
        check(state.otherProjectionActive,
                "unrecognized OEM connection states fail closed");
        check(PhoneProjectionAccess.inspect(provider(null), "candidate").result ==
                StockProjectionSession.Result.SERVICE_UNAVAILABLE, "missing OEM service classified");
        PhoneProjectionAccess.ServiceProvider denied = new PhoneProjectionAccess.ServiceProvider() {
            public Object get(String name) { throw new SecurityException(); }
        };
        check(PhoneProjectionAccess.inspect(denied, "candidate").result == StockProjectionSession.Result.SECURITY,
                "service lookup permission error classified");
        FakeProfileProvider profiles = new FakeProfileProvider();
        FakeActionSender sender = new FakeActionSender();
        profiles.profile = new PhoneProjectionAccess.Profile("candidate",
                PhoneProjectionAccess.TYPE_CARPLAY, true, true);
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.OEM_ACTION_SENT,
                "a matching enabled auto-connect CarPlay profile dispatches the OEM action");
        check(sender.sends == 1 &&
                PhoneProjectionAccess.OEM_CONNECT_ACTION.equals(sender.action) &&
                PhoneProjectionAccess.OEM_PACKAGE.equals(sender.packageName) &&
                "deviceAddress".equals(sender.extra) && "candidate".equals(sender.address),
                "OEM action is package-scoped and carries only the profile Bluetooth address");
        profiles.profile = null;
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.PROFILE_UNAVAILABLE && sender.sends == 1,
                "missing saved profile does not send an action");
        profiles.profile = new PhoneProjectionAccess.Profile("another-device",
                PhoneProjectionAccess.TYPE_CARPLAY, true, true);
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.PROFILE_MISMATCH && sender.sends == 1,
                "profile for another address does not send an action");
        profiles.profile = new PhoneProjectionAccess.Profile("candidate",
                PhoneProjectionAccess.TYPE_ANDROID_AUTO, true, true);
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.PROFILE_MISMATCH && sender.sends == 1,
                "Android Auto profile does not dispatch CarPlay");
        profiles.profile = new PhoneProjectionAccess.Profile("candidate",
                PhoneProjectionAccess.TYPE_CARPLAY, false, true);
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.PROFILE_DISABLED && sender.sends == 1,
                "disabled wireless profile is not silently enabled");
        profiles.profile = new PhoneProjectionAccess.Profile("candidate",
                PhoneProjectionAccess.TYPE_CARPLAY, true, false);
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.AUTO_CONNECT_DISABLED && sender.sends == 1,
                "stock auto-connect opt-out is respected");
        PhoneProjectionAccess.ProfileProvider deniedProfile = new PhoneProjectionAccess.ProfileProvider() {
            public PhoneProjectionAccess.Profile find(String address) { throw new SecurityException(); }
        };
        check(PhoneProjectionAccess.requestProfileAction(deniedProfile, sender, "candidate") ==
                StockProjectionSession.RequestResult.SECURITY && sender.sends == 1,
                "profile read permission error prevents OEM action");
        profiles.profile = new PhoneProjectionAccess.Profile("candidate",
                PhoneProjectionAccess.TYPE_CARPLAY, true, true);
        sender.allowed = false;
        check(PhoneProjectionAccess.requestProfileAction(profiles, sender, "candidate") ==
                StockProjectionSession.RequestResult.CANCELLED && sender.sends == 1,
                "stale or timed-out attempt is cancelled immediately before OEM action");
        System.out.println("PASS PhoneProjectionAccessTest");
    }
}
