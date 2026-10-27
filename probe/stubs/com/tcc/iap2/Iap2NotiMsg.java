package com.tcc.iap2;

/** Only the getters we use. */
public class Iap2NotiMsg implements android.os.Parcelable {
    public static final int OBJ_NUM8 = 0, OBJ_NUM16 = 1, OBJ_NUM32 = 2, OBJ_NUM64 = 3;
    public static final int OBJ_NUMU8 = 4, OBJ_NUMU16 = 5, OBJ_NUMU32 = 6, OBJ_NUMU64 = 7;
    public static final int OBJ_ENUM = 8, OBJ_BOOLEAN = 9, OBJ_STRING = 10, OBJ_BLOB = 11;
    public static final int OBJ_NONE = 12, OBJ_GROUP = 13, OBJ_BLOBFD = 14;

    public Iap2ObjGroup getItemGroup() { throw new RuntimeException("stub"); }
    public int describeContents() { throw new RuntimeException("stub"); }
    public void writeToParcel(android.os.Parcel p, int f) { throw new RuntimeException("stub"); }

    public class Iap2ObjGroup {
        public int getItemCnt() { throw new RuntimeException("stub"); }
        public Iap2ObjItem getObjItem(int i) { throw new RuntimeException("stub"); }
    }

    public class Iap2ObjItem {
        public int getItemId() { throw new RuntimeException("stub"); }
        public int getItemParamType() { throw new RuntimeException("stub"); }
        public int getItemObjCount() { throw new RuntimeException("stub"); }
        public int[] getItemIntArray() { throw new RuntimeException("stub"); }
        public long[] getItemLongArray() { throw new RuntimeException("stub"); }
        public String[] getItemStringArray() { throw new RuntimeException("stub"); }
        public byte[] getItemByteArray() { throw new RuntimeException("stub"); }
        public Iap2ObjGroup[] getItemGroupArray() { throw new RuntimeException("stub"); }
    }
}
