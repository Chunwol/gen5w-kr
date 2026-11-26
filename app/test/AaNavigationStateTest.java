import kr.gen5w.hud.*;
public class AaNavigationStateTest {
 static void ok(boolean b){if(!b)throw new AssertionError();}
 static AaNavigationParser.Event turn(int type, boolean lanes){
  byte[] step=AaNavigationParserTest.field(1,AaNavigationParserTest.b(8,type));
  if(lanes)step=AaNavigationParserTest.cat(step,AaNavigationParserTest.field(3,AaNavigationParserTest.field(1,AaNavigationParserTest.b(8,1,16,1))));
  return AaNavigationParser.parse(0x8006,AaNavigationParserTest.field(1,step));
 }
 static AaNavigationParser.Event distance(int n){return AaNavigationParser.parse(0x8007,AaNavigationParserTest.field(1,AaNavigationParserTest.field(1,AaNavigationParserTest.b(8,n))));}
 static AaNavigationParser.Event status(int n){return AaNavigationParser.parse(0x8003,AaNavigationParserTest.b(8,n));}
 public static void main(String[] args){
  AaNavigationState s=new AaNavigationState();
  ok(s.accept(distance(90))==null);
  AaNavigationState.Snapshot a=s.accept(turn(7,true));ok(a.icon==0x46 && a.distanceMeters==90 && a.lanes()[1]==1);
  byte[] mutable=a.lanes();mutable[1]=0;ok(a.lanes()[1]==1);
  a=s.accept(turn(7,false));ok(a.distanceMeters==90 && a.lanes()[1]==0);
  a=s.accept(turn(8,false));ok(a.clear);ok(s.accept(turn(8,false))==null);
  a=s.accept(distance(30));ok(a.icon==0x43 && a.distanceMeters==30);
  ok(s.accept(turn(99,false)).clear);ok(s.accept(distance(20))==null);
  ok(s.accept(status(1))==null);ok(s.accept(distance(19))==null);
  ok(s.accept(turn(7,false))==null);ok(s.accept(distance(15)).icon==0x46);
  ok(s.accept(status(3)).clear);ok(s.accept(status(1))==null);
  ok(s.accept(turn(7,false))==null);ok(s.accept(distance(10)).distanceMeters==10);
  ok(s.accept(status(2)).clear);ok(s.accept(distance(5))==null);ok(s.accept(turn(8,false))==null);
  ok(s.accept(status(1))==null);ok(s.accept(distance(4))==null);ok(s.accept(turn(8,false)).icon==0x43);
  ok(s.accept(status(3)).clear);
  ok(s.accept(distance(80))==null); // no pre-reroute maneuver may survive
  ok(s.accept(turn(8,false))==null); // reroute distance cannot precede the new step
  ok(s.accept(distance(8)).distanceMeters==8);
  ok(s.accept(status(3)).clear); // repeated reroute invalidates even pending distance
  ok(s.accept(turn(7,true))==null);
  ok(s.accept(distance(7)).lanes()[1]==1);
  ok(s.accept(status(0)).clear);s.reset();ok(s.accept(distance(3))==null);ok(s.accept(turn(7,false)).distanceMeters==3);
  ok(s.accept(AaNavigationParser.parse(0x8006,new byte[0])).clear);
  System.out.println("AaNavigationStateTest OK");
 }
}
