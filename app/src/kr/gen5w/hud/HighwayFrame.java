package kr.gen5w.hud;

/**
 * Builds HighwayMode items for cluster Highway Junction/Split display.
 * Pure logic without platform framework dependencies for JVM testability.
 */
public final class HighwayFrame {
    private HighwayFrame() {}

    public static final class Item {
        public int type;
        public int direction;
        public int traffic;
        public int unit;
        public float distance;
        public String name;
        public Item() {}
    }

    public static Item build(int icon, String name, float distanceMeters) {
        if (name == null || name.trim().isEmpty()) return null;
        String text = name.trim();
        int type = 0;
        if (ClusterIcon.hasAny(text, "휴게소", "졸음쉼터", "졸음 쉼터", "화물차라운지")) {
            type = 4;
        } else if (ClusterIcon.hasAny(text, "요금소", "톨게이트", "하이패스") || ClusterIcon.hasAny(text, "tg", "t.g")) {
            type = 3;
        } else if (ClusterIcon.hasAny(text, "분기점") || ClusterIcon.hasAny(text, "jc", "j.c")) {
            type = 2;
        } else if (ClusterIcon.hasAny(text, "나들목", "진출", "출구") || ClusterIcon.hasAny(text, "ic", "i.c")) {
            type = 1;
        } else {
            return null;
        }

        int direction = 1; // default straight
        if (icon == ClusterIcon.IC_EXIT_R || ClusterIcon.hasAny(text, "오른쪽", "우측")) {
            direction = 2;
        } else if (icon == ClusterIcon.IC_EXIT_L || ClusterIcon.hasAny(text, "왼쪽", "좌측")) {
            direction = 3;
        }

        Item item = new Item();
        item.type = type;
        item.direction = direction;
        item.traffic = 0; // normal
        item.unit = 0; // meters
        item.distance = distanceMeters >= 0 ? distanceMeters : 0f;
        item.name = text;
        return item;
    }
}
