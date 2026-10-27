package kr.gen5w.probe;

import com.tcc.iap2.Iap2NotiMsg;

import java.util.ArrayList;
import java.util.List;

/** Copies the system library's message objects into our own Items. */
public final class Convert {
    private static final int MAX_DEPTH = 8;

    private Convert() {}

    public static List<Item> of(Iap2NotiMsg msg) {
        if (msg == null) return new ArrayList<Item>();
        return group(msg.getItemGroup(), 0);
    }

    private static List<Item> group(Iap2NotiMsg.Iap2ObjGroup g, int depth) {
        List<Item> out = new ArrayList<Item>();
        if (g == null || depth > MAX_DEPTH) return out;
        int n = g.getItemCnt();
        for (int i = 0; i < n; i++) {
            Iap2NotiMsg.Iap2ObjItem o = g.getObjItem(i);
            if (o == null) continue;
            Item it = new Item();
            it.id = o.getItemId();
            it.type = o.getItemParamType();
            if (it.type == Iap2NotiMsg.OBJ_GROUP) {
                Iap2NotiMsg.Iap2ObjGroup[] subs = o.getItemGroupArray();
                if (subs != null) for (Iap2NotiMsg.Iap2ObjGroup s : subs) it.groups.add(group(s, depth + 1));
            } else if (it.type == Iap2NotiMsg.OBJ_STRING) {
                it.strings = o.getItemStringArray();
            } else if (it.type == Iap2NotiMsg.OBJ_BLOB) {
                it.bytes = o.getItemByteArray();
            } else if (it.type == Iap2NotiMsg.OBJ_NUM64 || it.type == Iap2NotiMsg.OBJ_NUMU64) {
                it.longs = o.getItemLongArray();
            } else {
                it.ints = o.getItemIntArray();
                if (it.ints == null) it.longs = o.getItemLongArray();
            }
            out.add(it);
        }
        return out;
    }
}
