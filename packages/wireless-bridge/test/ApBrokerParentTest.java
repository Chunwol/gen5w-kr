import kr.gen5w.hotspot.ApBrokerParent;

public final class ApBrokerParentTest {
    public static void main(String[] args) {
        if (ApBrokerParent.parse("111 (app_process) S 44 1 2") != 44) throw new AssertionError("parent PID");
        if (ApBrokerParent.parse("111 (name ) with spaces) S 52 1") != 52) throw new AssertionError("process name");
        if (ApBrokerParent.parse("invalid") != -1) throw new AssertionError("invalid stat");
        if (ApBrokerParent.parse("111 (name) S nope") != -1) throw new AssertionError("invalid parent PID");
        System.out.println("ApBrokerParentTest passed");
    }
}
