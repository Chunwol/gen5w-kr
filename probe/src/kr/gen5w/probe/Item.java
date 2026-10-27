package kr.gen5w.probe;

import java.util.ArrayList;
import java.util.List;

/** One iAP2 message item, copied out of the system library's objects. */
public final class Item {
    public int id;
    public int type;
    public int[] ints;
    public long[] longs;
    public String[] strings;
    public byte[] bytes;
    /** For group items: one list of items per group element. */
    public final List<List<Item>> groups = new ArrayList<List<Item>>();
}
