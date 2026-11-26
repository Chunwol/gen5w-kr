package kr.gen5w.hud;
import java.io.DataInputStream;
import java.io.InputStream;
import java.io.IOException;
/** One bounded frame from the process-local authenticated AA native producer. */
public final class AaWireFrame {
    public final int type;
    public final byte[] payload;
    private AaWireFrame(int type, byte[] payload) { this.type=type; this.payload=payload; }
    public static AaWireFrame read(InputStream source) throws IOException {
        DataInputStream in=new DataInputStream(source);
        if(in.readInt()!=0x47414e31) throw new IOException("AA frame magic");
        int type=in.readInt(), size=in.readInt();
        if((type!=0x8003 && type!=0x8006 && type!=0x8007) || size<0 || size>65536)
            throw new IOException("AA frame type or size");
        byte[] payload=new byte[size]; in.readFully(payload);
        return new AaWireFrame(type,payload);
    }
}
