package kr.gen5w.hud;

import java.util.ArrayList;
import java.util.List;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.Charset;

/** Authored bounded wire reader for AA native navigation (0x8003/6/7).
 * Wire field reference: mrmees/open-android-auto oaa/navigation (2026-11-24).
 * No generated protobuf code or reference implementation is included.
 */
public final class AaNavigationParser {
 private AaNavigationParser() {}
 /** Stock HKMC_GPM GpmNaviTBTManager fork icons: RIGHT 173 (0xad), LEFT 174 (0xae). */
 public static final int FORK_RIGHT=0xad, FORK_LEFT=0xae;
 /** Counterclockwise roundabout exit icons, one per 45 degrees of exit direction (0 = straight on,
  * clockwise): the stock navigation's own set 96,97,99,100,102,104,105,107. 103/106 are never used
  * (106's clockwise twin draws the loading spinner). Clockwise roundabouts use the same exit + 0x60. */
 private static final int[] ROUNDABOUT_CCW={0x60,0x61,0x63,0x64,0x66,0x68,0x69,0x6b};
 /**
  * AndroidX roundabout angle = amount travelled around the roundabout (1..360): in a counterclockwise
  * roundabout 90 = right exit, 180 = straight on, 270 = left, 360 = U-turn (Kakao/Naver/Tmap evidence,
  * same as stock GPM's ROUNDABOUT_ENTER_AND_EXIT table). Without an angle there is no exit to draw,
  * so straight-ahead is shown instead of the spinner code 0x40.
  */
 static int roundaboutIcon(int aaType,int angle){
  if(angle==Maneuver.UNKNOWN_ANGLE || angle<=0 || angle>360)return TurnFrame.ICON_STRAIGHT;
  boolean clockwise=aaType==32 || aaType==33;
  int direction=clockwise?(angle+180)%360:((180-angle)%360+360)%360;
  int bucket=((direction+22)/45)%8;
  return ROUNDABOUT_CCW[bucket]+(clockwise?0x60:0);
 }
 public static final class Event {
  public int messageId, status=-1;
  public final List<Step> steps=new ArrayList<Step>();
  public long distanceMeters=-1;
  public String currentRoad;
  public boolean clearsGuidance(){return status==0 || status==2;}
  public boolean rerouting(){return status==3;}
 }
 public static final class Step {
  public int aaType, roundaboutExit=-1, roundaboutAngle=Maneuver.UNKNOWN_ANGLE;
  public final Maneuver maneuver=new Maneuver();
  public final GuidanceParser.Lanes lanes=new GuidanceParser.Lanes();
  public int icon(){
   if(aaType==13 || aaType==15 || aaType==17 || aaType==19)return ClusterIcon.IC_ENTER_L;
   if(aaType==14 || aaType==16 || aaType==18 || aaType==20)return ClusterIcon.IC_ENTER_R;
   if(aaType==25 || aaType==26){
    // Korean apps send overpass/underpass/tunnel entries and side roads as forks; keep the
    // stock grade-separated icon when the text proves it, otherwise the stock GPM fork icon.
    int base=aaType==25?0x47:0x42;
    int refined=ClusterIcon.refineManeuver(base,maneuver.afterRoad,maneuver.desc);
    return refined!=base?refined:(aaType==25?FORK_LEFT:FORK_RIGHT);
   }
   if(aaType>=32 && aaType<=35)return roundaboutIcon(aaType,roundaboutAngle);
   return ClusterIcon.of(maneuver);
  }
  /** Roundabout entry/exit steps that carry no exit of their own. */
  public boolean roundaboutContinuation(){return aaType==30 || aaType==31;}
  public boolean roundaboutWithExit(){return aaType>=32 && aaType<=35;}
  public byte[] laneFrame(){return LaneFrame.encode(lanes,icon());}
 }
 public static Event parse(int id, byte[] payload){
  if(payload==null || payload.length>65536)throw new IllegalArgumentException("AA payload size");
  if(id!=0x8003 && id!=0x8006 && id!=0x8007)throw new IllegalArgumentException("AA message type");
  Event out=new Event();out.messageId=id; Reader r=new Reader(payload,0,payload.length);
  while(r.more()){
   int t=r.tag();
   if(id==0x8003 && t==8)out.status=r.integer();
   else if(id==0x8006 && t==10){if(out.steps.size()>=16)throw new IllegalArgumentException("AA step count");out.steps.add(step(r.child()));}
   else if(id==0x8007 && t==10){Reader s=r.child();while(s.more()){int st=s.tag();if(st==10)out.distanceMeters=distance(s.child());else s.skip(st);}}
   else if(id==0x8007 && t==26)out.currentRoad=text(r.child());
   else r.skip(t);
  }
  return out;
 }
 private static Step step(Reader r){
  Step s=new Step();s.maneuver.type=-1;
  while(r.more()){
   int t=r.tag();
   if(t==10){Reader m=r.child();while(m.more()){int mt=m.tag();if(mt==8)s.aaType=m.integer();else if(mt==16)s.roundaboutExit=m.integer();else if(mt==24)s.roundaboutAngle=m.integer();else m.skip(mt);}}
   else if(t==18)s.maneuver.desc=text(r.child());
   else if(t==26){if(s.lanes.lanes.size()>=8)throw new IllegalArgumentException("AA lane count");s.lanes.lanes.add(lane(r.child(),s.lanes.lanes.size()));}
   else if(t==34){Reader road=r.child();while(road.more()){int rt=road.tag();if(rt==10){String name=road.string();if(s.maneuver.afterRoad==null)s.maneuver.afterRoad=name;}else road.skip(rt);}}
   else r.skip(t);
  }
  map(s);return s;
 }
 private static GuidanceParser.Lane lane(Reader r,int index){
  GuidanceParser.Lane lane=new GuidanceParser.Lane();lane.index=index;lane.status=1;
  List<Integer> a=new ArrayList<Integer>(), h=new ArrayList<Integer>();
  while(r.more()){int t=r.tag();if(t!=10){r.skip(t);continue;}Reader d=r.child();int shape=0;boolean rec=false;
   while(d.more()){int dt=d.tag();if(dt==8)shape=d.integer();else if(dt==16)rec=d.varint()!=0;else d.skip(dt);}
   if(a.size()>=3)throw new IllegalArgumentException("AA lane direction count");
   int angle=shape==1?0:shape==2?-45:shape==3?45:shape==4?-90:shape==5?90:shape==6?-135:shape==7?135:shape==8?-180:shape==9?180:Integer.MIN_VALUE;
   a.add(angle);if(rec)h.add(angle);
  }
  lane.angles=ints(a);lane.highlights=ints(h);return lane;
 }
 private static int[] ints(List<Integer> x){int[] a=new int[x.size()];for(int i=0;i<a.length;i++)a[i]=x.get(i);return a;}
 private static void map(Step s){
  Maneuver m=s.maneuver;m.drivingSide=0;m.junctionType=0;m.exitAngle=0;
  switch(s.aaType){
   case 2:case 36:m.type=3;break;
   case 3:case 5:m.type=49;m.exitAngle=-45;break;
   case 4:case 6:m.type=50;m.exitAngle=45;break;
   case 7:m.type=1;m.exitAngle=-90;break;
   case 8:m.type=2;m.exitAngle=90;break;
   case 9:m.type=47;m.exitAngle=-135;break;
   case 10:m.type=48;m.exitAngle=135;break;
   case 11:m.type=4;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   case 12:m.type=4;m.drivingSide=1;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   case 13:case 15:case 17:case 19:m.type=9;break;
   case 14:case 16:case 18:case 20:m.type=9;break;
   case 21:case 23:m.type=22;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   case 22:case 24:m.type=23;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   // Forks are drawn by Step.icon(); the maneuver keeps the side for text refinement.
   case 25:m.type=13;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   case 26:m.type=14;m.exitAngle=Maneuver.UNKNOWN_ANGLE;break;
   // Stock GPM shows MERGE as straight ahead (65).
   case 27:case 28:case 29:m.type=3;break;
   // ROUNDABOUT_ENTER/EXIT without an exit: straight ahead unless a previous exit is kept.
   case 30:case 31:m.type=3;break;
   case 32:case 33:case 34:case 35:{
    boolean cw=s.aaType==32 || s.aaType==33;
    m.type=3;
    m.junctionType=1;
    m.drivingSide=cw?1:0;
    m.roundaboutExit=s.roundaboutExit;
    m.exitAngle=(s.roundaboutAngle==Maneuver.UNKNOWN_ANGLE || s.roundaboutAngle<=0 || s.roundaboutAngle>360)
     ? Maneuver.UNKNOWN_ANGLE
     : (cw ? (s.roundaboutAngle+180)%360 : ((180-s.roundaboutAngle)%360+360)%360);
    break;
   }
   case 37:m.type=15;break;
   case 39:case 40:m.type=10;break;
   case 41:m.type=24;break;case 42:m.type=25;break;
   default:m.type=-1;
  }
 }
 private static String text(Reader r){String value=null;while(r.more()){int t=r.tag();if(t==10)value=r.string();else r.skip(t);}return value;}
 private static long distance(Reader r){
  long raw=-1;String display=null;int unit=0;
  while(r.more()){int t=r.tag();if(t==8)raw=r.integer();else if(t==18)display=r.string();else if(t==24)unit=r.integer();else r.skip(t);}
  if(raw>=0)return raw;
  if(display==null || !display.matches("[0-9]+(?:\\.[0-9]+)?"))return -1;
  double scale=unit==1?1:unit==2||unit==3?1000:unit==4||unit==5?1609.344:unit==6?0.3048:unit==7?0.9144:0;
  if(scale==0)return -1;
  try{double value=Double.parseDouble(display)*scale;return Double.isNaN(value)||Double.isInfinite(value)||value>Integer.MAX_VALUE?-1:Math.round(value);}catch(NumberFormatException e){return -1;}
 }
 private static final class Reader {
  final byte[] b;int p;final int end;
  Reader(byte[] b,int p,int end){this.b=b;this.p=p;this.end=end;}
  boolean more(){return p<end;}
  void need(int n){if(n<0 || n>end-p)throw new IllegalArgumentException("Truncated AA protobuf");}
  long varint(){long n=0;for(int i=0;i<10;i++){need(1);int v=b[p++]&255;if(i==9 && (v&254)!=0)throw new IllegalArgumentException("AA varint overflow");n|=(long)(v&127)<<(7*i);if((v&128)==0)return n;}throw new IllegalArgumentException("AA varint overflow");}
  int integer(){long v=varint();if(v>Integer.MAX_VALUE || v<Integer.MIN_VALUE)throw new IllegalArgumentException("AA int32 overflow");return (int)v;}
  int tag(){long t=varint();if(t<=0 || t>0xffffffffL || (t>>>3)==0)throw new IllegalArgumentException("AA tag");return (int)t;}
  Reader child(){long n=varint();if(n<0 || n>end-p)throw new IllegalArgumentException("AA length");Reader c=new Reader(b,p,p+(int)n);p+=(int)n;return c;}
  String string(){Reader c=child();if(c.end-c.p>4096)throw new IllegalArgumentException("AA string size");try{return Charset.forName("UTF-8").newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(b,c.p,c.end-c.p)).toString();}catch(CharacterCodingException e){throw new IllegalArgumentException("AA UTF-8");}}
  void skip(int t){switch(t&7){case 0:varint();return;case 1:need(8);p+=8;return;case 2:child();return;case 5:need(4);p+=4;return;default:throw new IllegalArgumentException("Unsupported AA wire type");}}
 }
}
