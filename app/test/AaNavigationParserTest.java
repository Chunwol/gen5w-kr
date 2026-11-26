import kr.gen5w.hud.*;
import java.io.ByteArrayOutputStream;
public class AaNavigationParserTest {
 static byte[] b(int... x){byte[] b=new byte[x.length];for(int i=0;i<x.length;i++)b[i]=(byte)x[i];return b;}
 static byte[] field(int n, byte[] body){ByteArrayOutputStream o=new ByteArrayOutputStream();o.write((n<<3)|2);o.write(body.length);o.write(body,0,body.length);return o.toByteArray();}
 static byte[] cat(byte[]... a){ByteArrayOutputStream o=new ByteArrayOutputStream();for(byte[] x:a)o.write(x,0,x.length);return o.toByteArray();}
 static void ok(boolean b){if(!b)throw new AssertionError();}
 static int icon(byte[] maneuver){return AaNavigationParser.parse(0x8006,field(1,field(1,maneuver))).steps.get(0).icon();}
 static int iconWithRoad(byte[] maneuver,String road){
  byte[] name;try{name=road.getBytes("UTF-8");}catch(java.io.UnsupportedEncodingException e){throw new AssertionError(e);}
  return AaNavigationParser.parse(0x8006,field(1,cat(field(1,maneuver),field(4,field(1,name))))).steps.get(0).icon();
 }
 static void bad(byte[] b){try{AaNavigationParser.parse(0x8006,b);throw new AssertionError("accepted malformed");}catch(IllegalArgumentException expected){}}
 public static void main(String[] args){
  byte[] turn=field(1,b(8,7));
  byte[] road=field(4,field(1,b(82,111,97,100)));
  byte[] lane=field(3,cat(field(1,b(8,1)),field(1,b(8,5,16,1))));
  AaNavigationParser.Event e=AaNavigationParser.parse(0x8006,cat(field(1,cat(turn,road,lane)),field(1,field(1,b(8,8)))));
  ok(e.steps.size()==2);ok(e.steps.get(0).icon()==0x46);ok(e.steps.get(1).icon()==0x43);
  ok("Road".equals(e.steps.get(0).maneuver.afterRoad));ok(e.steps.get(0).laneFrame()[1]==1);
  ok(e.steps.get(0).laneFrame()[3]==9); // straight allowed + right recommended
  ok(AaNavigationParser.parse(0x8006,field(1,field(1,b(8,99)))).steps.get(0).icon()==-1);
  ok(AaNavigationParser.parse(0x8006,field(1,field(1,b(8,13)))).steps.get(0).icon()==ClusterIcon.IC_ENTER_L);
  ok(AaNavigationParser.parse(0x8006,field(1,field(1,b(8,14)))).steps.get(0).icon()==ClusterIcon.IC_ENTER_R);
  // Stock HKMC_GPM equivalents: forks 0xae/0xad (not the destination flags), merge straight,
  // destination left/right 0x72/0x71, ferry 0xb0.
  ok(icon(b(8,25))==0xae);ok(icon(b(8,26))==0xad);
  ok(icon(b(8,27))==0x41);ok(icon(b(8,28))==0x41);ok(icon(b(8,29))==0x41);
  ok(icon(b(8,39))==0x70);ok(icon(b(8,40))==0x70);ok(icon(b(8,41))==0x72);ok(icon(b(8,42))==0x71);
  ok(icon(b(8,37))==0xb0);ok(icon(b(8,38))==-1);
  // Korean apps send underpass/overpass entries and side roads as forks.
  ok(iconWithRoad(b(8,25),"지하차도")==ClusterIcon.UNDERPASS_ENTRY_LC);
  ok(iconWithRoad(b(8,26),"지하차도")==ClusterIcon.UNDERPASS_ENTRY_R);
  ok(iconWithRoad(b(8,25),"고가차도 옆길")==ClusterIcon.OVERPASS_SIDE_L);
  ok(iconWithRoad(b(8,26),"강변북로")==0xad);
  // Roundabouts: travelled angle 180 straight, 90 right, 270 left, 360 U-turn (counterclockwise).
  ok(icon(cat(b(8,35),b(24,180,1)))==0x60);ok(icon(cat(b(8,35),b(24,90)))==0x63);
  ok(icon(cat(b(8,35),b(24,142,2)))==0x69);ok(icon(cat(b(8,35),b(24,232,2)))==0x66);
  ok(icon(cat(b(8,35),b(24,150,1)))==0x61);ok(icon(cat(b(8,35),b(24,210,1)))==0x6b);
  ok(icon(cat(b(8,35),b(24,30)))==0x64);ok(icon(cat(b(8,35),b(24,172,2)))==0x68);
  ok(icon(cat(b(8,33),b(24,142,2)))==0xc3); // clockwise: 270 travelled = right exit
  ok(icon(b(8,34))==0x41);ok(icon(b(8,30))==0x41);ok(icon(b(8,31))==0x41);
  for(int t=0;t<=42;t++)for(int a:new int[]{0,30,90,180,210,270,300,360}){int c=icon(cat(b(8,t),b(24,a&127|(a>127?128:0)),a>127?b(a>>7):b()));ok(c!=0x40 && c!=0x67 && c!=0x6a && c!=0xc7 && c!=0xca);}
  // Inside the roundabout AA sends a bare EXIT step: keep the exit icon until the next maneuver.
  AaNavigationState st=new AaNavigationState();
  st.accept(AaNavigationParser.parse(0x8006,field(1,field(1,cat(b(8,35),b(24,90))))));
  ok(st.accept(AaNavigationParser.parse(0x8007,b(10,4,10,2,8,100))).icon==0x63);
  AaNavigationState.Snapshot inside=st.accept(AaNavigationParser.parse(0x8006,field(1,field(1,b(8,31)))));
  ok(inside!=null && inside.icon==0x63 && inside.distanceMeters==100);
  AaNavigationState.Snapshot after=st.accept(AaNavigationParser.parse(0x8006,field(1,field(1,b(8,7)))));
  ok(after==null || after.clear || after.icon==0x46);
  ok(AaNavigationParser.parse(0x8003,b(8,3)).rerouting());
  ok(!AaNavigationParser.parse(0x8003,b(8,3)).clearsGuidance());
  ok(AaNavigationParser.parse(0x8003,b(8,2)).clearsGuidance());
  ok(AaNavigationParser.parse(0x8007,b(10,5,10,3,8,194,3)).distanceMeters==450);
  ok(AaNavigationParser.parse(0x8007,b(10,7,10,5,18,1,48,24,6)).distanceMeters==0);
  ok(AaNavigationParser.parse(0x8007,b(10,9,10,7,18,3,49,46,53,24,5)).distanceMeters==2414);
  ok(AaNavigationParser.parse(0x8007,b(10,9,10,7,18,3,78,97,78,24,5)).distanceMeters==-1);
  ok(AaNavigationParser.parse(0x8007,b(10,7,10,5,18,1,49,24,99)).distanceMeters==-1);
  ok(AaNavigationParser.parse(0x8006,cat(b(120,1),field(1,turn))).steps.size()==1);
  bad(field(1,field(1,b(8,128,128,128,128,8))));
  bad(b(10,9,1));bad(b(0));bad(b(10,128,128,128,128,128,128,128,128,128,2));
  bad(b(120,128,128,128,128,128,128,128,128,128,2));
  for(int i=1;i<turn.length;i++)bad(java.util.Arrays.copyOf(field(1,turn),i));
  // Roundabout AA maneuver geometry reaches StockTurn via AaNavigationState and AaRouteCache.
  AaNavigationParser.Event rbEv=AaNavigationParser.parse(0x8006,field(1,field(1,cat(b(8,35),b(16,2),b(24,90)))));
  AaNavigationState rbState=new AaNavigationState();
  rbState.accept(rbEv);
  AaNavigationState.Snapshot rbSnap=rbState.accept(AaNavigationParser.parse(0x8007,b(10,5,10,3,8,244,1)));
  ok(rbSnap!=null && rbSnap.maneuver!=null && rbSnap.maneuver.junctionType==1 && rbSnap.maneuver.roundaboutExit==2 && rbSnap.maneuver.exitAngle==90);
  AaRouteCache rbCache=new AaRouteCache(); rbCache.setOutputAllowed(true);
  ok(rbCache.update(rbSnap.icon,rbSnap.secondIcon,rbSnap.distanceMeters,rbSnap.road,rbSnap.tunnel,rbSnap.maneuver,1000L));
  StockTurn.Frame rbFrame=StockTurn.build(rbCache.maneuver(),rbCache.icon(),rbCache.distance(),false);
  ok(rbFrame.displayType==StockTurn.DISPLAY_ROTARY_CCW && rbFrame.directionType==12 && rbFrame.sideStreet==0x0011 && rbFrame.combiSideStreet==0);
  System.out.println("AaNavigationParserTest OK");
 }
}
