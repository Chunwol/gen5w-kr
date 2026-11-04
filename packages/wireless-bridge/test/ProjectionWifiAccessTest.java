package kr.gen5w.wireless;

import java.lang.reflect.Field;

public final class ProjectionWifiAccessTest {
    public static final class FakeConfig {
        public String ConnectivitySSID;
        public String ConnectivityPSK;

        FakeConfig(String ssid, String psk) {
            ConnectivitySSID = ssid;
            ConnectivityPSK = psk;
        }
    }

    public static final class FakeWifiManager {
        private final Object config;

        FakeWifiManager(Object config) { this.config = config; }

        public Object getWifiApConfiguration() { return config; }
    }

    private ProjectionWifiAccessTest() {}

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static ProjectionWifiAccess.CredentialObservation inspect(String ssid, String psk) {
        return ProjectionWifiAccess.inspect(new FakeWifiManager(new FakeConfig(ssid, psk)));
    }

    public static void main(String[] args) throws Exception {
        check(ProjectionWifiAccess.inspect(null).status ==
                ProjectionWifiAccess.CredentialStatus.UNKNOWN,
                "missing Wi-Fi service is unknown");
        check(ProjectionWifiAccess.inspect(new Object()).status ==
                ProjectionWifiAccess.CredentialStatus.UNKNOWN,
                "missing reflected method is unknown");
        check(ProjectionWifiAccess.inspect(new FakeWifiManager(null)).status ==
                ProjectionWifiAccess.CredentialStatus.UNKNOWN,
                "missing AP configuration is unknown");

        check(inspect(null, "secret").status == ProjectionWifiAccess.CredentialStatus.MISSING,
                "null connectivity SSID is missing");
        check(inspect("   ", "secret").status == ProjectionWifiAccess.CredentialStatus.MISSING,
                "blank connectivity SSID is missing");
        check(inspect("projection", null).status == ProjectionWifiAccess.CredentialStatus.MISSING,
                "null connectivity PSK is missing");
        check(inspect("projection", " \t").status == ProjectionWifiAccess.CredentialStatus.MISSING,
                "blank connectivity PSK is missing");
        check(inspect("projection", "secret").status == ProjectionWifiAccess.CredentialStatus.PRESENT,
                "both connectivity fields present reports presence");

        for (Field field : ProjectionWifiAccess.CredentialObservation.class.getDeclaredFields()) {
            check(field.getType() != String.class,
                    "credential observation has no string field");
        }

        check(ProjectionWifiAccess.classifyApState(12) == ProjectionWifiAccess.ApProgress.ENABLING,
                "AP enabling state");
        check(ProjectionWifiAccess.classifyApState(13) == ProjectionWifiAccess.ApProgress.READY,
                "AP ready state");
        check(ProjectionWifiAccess.classifyApState(14) == ProjectionWifiAccess.ApProgress.FAILED,
                "AP failed state");
        check(ProjectionWifiAccess.classifyApState(10) == ProjectionWifiAccess.ApProgress.OFF,
                "AP disabled state");
        check(ProjectionWifiAccess.classifyApState(11) == ProjectionWifiAccess.ApProgress.OFF,
                "AP disabling state");
        check(ProjectionWifiAccess.classifyApState(9) == ProjectionWifiAccess.ApProgress.UNKNOWN,
                "unknown AP state remains unknown");

        String source = new String(java.nio.file.Files.readAllBytes(
                java.nio.file.Paths.get("packages/wireless-bridge/src/kr/gen5w/wireless/ProjectionWifiAccess.java")),
                java.nio.charset.StandardCharsets.UTF_8);
        check(!source.contains("setWifiApEnabled") && !source.contains("startSoftAp"),
                "observer source contains no AP mutation method");
        System.out.println("PASS ProjectionWifiAccessTest");
    }
}
