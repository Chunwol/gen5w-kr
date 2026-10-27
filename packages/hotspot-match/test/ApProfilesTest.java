import kr.gen5w.hotspot.ApProfiles;

public final class ApProfilesTest {
    static void check(boolean ok, String name) { if (!ok) throw new AssertionError(name); }
    static final ApProfiles.Profile ORIGINAL = new ApProfiles.Profile("ordinary", "ordinary-key", "cp", "carplay-key", 1);
    static final class Fake implements ApProfiles.Port, ApProfiles.Guard {
        ApProfiles.Profile config = ORIGINAL, submitted;
        String liveSsid, liveKey;
        int state = 11, mode = 1, enables, disables;
        boolean fail, cancelled, hang, locked, ordinaryEditOnDisable, cpEditOnDisable;
        long time;
        public void check() throws Exception { if (cancelled) throw new Exception("cancelled generation"); }
        public void lock(ApProfiles.Guard guard) throws Exception { guard.check(); locked = true; }
        public void unlock() { locked = false; }
        public ApProfiles.Profile configuration() { return config; }
        public int state() { return state; }
        public int mode() { return mode; }
        public long now() { return time; }
        public void pause() { time += 250; }
        public void disable() {
            ApProfilesTest.check(locked, "disable under shared lock"); disables++; state = 11;
            if (ordinaryEditOnDisable) config = new ApProfiles.Profile("user-edited", "new-key", "cp", "carplay-key", 1);
            if (cpEditOnDisable) config = new ApProfiles.Profile("ordinary", "ordinary-key", "cp2", "carplay-key2", 1);
        }
        public void enable(ApProfiles.Profile expected) throws Exception {
            ApProfilesTest.check(locked, "enable under shared lock");
            ApProfilesTest.check(config.ssid.equals(expected.ssid) && config.key.equals(expected.key),
                    "never replace ordinary credentials when submitting OEM AP config");
            if (!config.carplaySsid.equals(expected.carplaySsid) || !config.carplayKey.equals(expected.carplayKey))
                throw new Exception("CP settings changed");
            submitted = expected; enables++;
            // Contract of the hash-gated native implementation: save unchanged
            // ordinary fields, select CP fields only for the live mode-2 command.
            config = new ApProfiles.Profile(expected.ssid, expected.key, expected.carplaySsid, expected.carplayKey, 2);
            mode = 2; state = hang ? 12 : 13;
            liveSsid = expected.carplaySsid; liveKey = expected.carplayKey;
            if (fail) throw new Exception("native start failed");
        }
    }
    static void preserved(Fake f) {
        check("ordinary".equals(f.config.ssid) && "ordinary-key".equals(f.config.key), "ordinary credentials unchanged");
        check("cp".equals(f.config.carplaySsid) && "carplay-key".equals(f.config.carplayKey), "CP settings unchanged");
        check(!f.locked, "release shared lock");
    }
    public static void main(String[] args) throws Exception {
        check(ApProfiles.securitySupported(4, ""), "WPA2 without factory override is supported");
        check(!ApProfiles.securitySupported(0, "") && !ApProfiles.securitySupported(1, ""), "open and WPA profiles rejected");
        check(!ApProfiles.securitySupported(4, "open") && !ApProfiles.securitySupported(4, "wpa2-psk"),
                "every nonempty factory auth override rejected");
        check(!ApProfiles.securitySupported(4, null), "unreadable factory auth fails closed");
        Fake f = new Fake(); ApProfiles controller = new ApProfiles();
        check(controller.ensure(f, f), "initial activation"); preserved(f);
        check("cp".equals(f.liveSsid) && "carplay-key".equals(f.liveKey), "native mode2 uses CP for live AP only");
        check(f.state == 13 && f.mode == 2, "native AP lifecycle remains active");
        check(!controller.ensure(f, f) && f.enables == 1 && f.disables == 0, "preserved ordinary profile cannot trigger restart");
        f.config = new ApProfiles.Profile("ordinary", "ordinary-key", "cp2", "carplay-key2", 2);
        check(controller.ensure(f, f) && f.enables == 2 && f.disables == 1, "new CP settings activate once");
        f = new Fake(); f.state = 13; f.mode = 2;
        new ApProfiles().ensure(f, f);
        check(f.disables == 1 && f.enables == 1, "unknown activator establishes credentials once"); preserved(f);
        f = new Fake(); f.fail = true;
        try { new ApProfiles().ensure(f, f); throw new AssertionError("must fail"); } catch (Exception expected) { }
        preserved(f); check(f.disables == 1 && f.state == 11, "failed owned start uses native stop");
        final Fake cancelled = new Fake();
        try { new ApProfiles().ensure(cancelled, new ApProfiles.Guard() {
            public void check() throws Exception { if (cancelled.enables > 0) throw new Exception("new generation"); }
        }); throw new AssertionError("must cancel"); } catch (Exception expected) { }
        preserved(cancelled); check(cancelled.disables == 0, "old generation cannot stop new generation AP");
        f = new Fake(); f.state = 13; f.ordinaryEditOnDisable = true;
        new ApProfiles().ensure(f, f);
        check("user-edited".equals(f.config.ssid) && "new-key".equals(f.config.key), "ordinary edits during stop reach fresh OEM config");
        f = new Fake(); f.state = 13; f.cpEditOnDisable = true;
        try { new ApProfiles().ensure(f, f); throw new AssertionError("must retry changed CP profile"); } catch (Exception expected) { }
        check(f.enables == 0 && "cp2".equals(f.config.carplaySsid) && !f.locked, "CP edits during stop abort stale activation");
        f = new Fake(); f.hang = true;
        try { new ApProfiles().ensure(f, f); throw new AssertionError("must time out"); } catch (Exception expected) { }
        preserved(f); check(f.time == 20000 && f.state == 11, "timeout bounded and owned AP stopped");
        f = new Fake(); f.config = new ApProfiles.Profile("ordinary", "ordinary-key", null, null, 1);
        try { new ApProfiles().ensure(f, f); throw new AssertionError("must reject missing CP settings"); } catch (Exception expected) { }
        check(f.enables == 0 && f.disables == 0 && !f.locked, "validate before any radio operation");
        System.out.println("AP native selection/preservation/failure/cancel/edit/reuse passed");
    }
}
