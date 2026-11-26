package kr.gen5w.hud;

/** Joins independent AA turn and distance updates. Wire messages carry no turn
 * sequence identifier, so a changed first step always invalidates old distance.
 * A distance before the initial step is buffered once; inactive events are ignored.
 */
public final class AaNavigationState {
 public static final class Snapshot {
  public final int icon, secondIcon;
  public final long distanceMeters;
  public final String road;
  public final boolean tunnel;
  public final boolean clear;
  private final byte[] laneBytes;
  private Snapshot(int icon,int second,long meters,String road,boolean tunnel,byte[] lanes,boolean clear){
   this.icon=icon;secondIcon=second;distanceMeters=meters;this.road=road;this.tunnel=tunnel;
   laneBytes=lanes.clone();this.clear=clear;
  }
  public byte[] lanes(){return laneBytes.clone();}
 }
 private AaNavigationParser.Step first,second;
 private long distance=-1;
 private boolean inactive, allowInitialDistance=true;
 public synchronized void reset(){first=null;second=null;distance=-1;inactive=false;allowInitialDistance=true;}
 public synchronized Snapshot accept(AaNavigationParser.Event e){
  if(e==null)throw new IllegalArgumentException("AA event");
  if(e.messageId==0x8003){
   if(e.status==0 || e.status==2 || e.status==3){
    first=null;second=null;distance=-1;
    inactive=e.status!=3;allowInitialDistance=false;
    return clear();
   }
   if(e.status==1){if(inactive)allowInitialDistance=true;inactive=false;}
   return null;
  }
  if(inactive)return null;
  if(e.messageId==0x8007){
   if(e.distanceMeters<0)return null;
   if(first==null){if(allowInitialDistance)distance=e.distanceMeters;return null;}
   distance=e.distanceMeters;return snapshot();
  }
  if(e.messageId!=0x8006)return null;
  AaNavigationParser.Step next=e.steps.isEmpty()?null:e.steps.get(0);
  if(next==null || next.icon()<=0){
   first=null;second=null;distance=-1;allowInitialDistance=false;return clear();
  }
  // Android Auto guides a roundabout as ENTER_AND_EXIT (with the exit) and then a bare
  // ENTER/EXIT step inside it; keep the exit icon until the next real maneuver.
  if(next.roundaboutContinuation() && first!=null && first.roundaboutWithExit()){
   second=e.steps.size()>1?e.steps.get(1):null;allowInitialDistance=false;
   return distance>=0?snapshot():null;
  }
  boolean changed=first!=null && !same(first,next);
  boolean hadGuidance=first!=null && distance>=0;
  if(changed)distance=-1;
  first=next;second=e.steps.size()>1?e.steps.get(1):null;allowInitialDistance=false;
  if(distance>=0)return snapshot();
  return changed && hadGuidance?clear():null;
 }
 private Snapshot snapshot(){return new Snapshot(first.icon(),second==null?0:Math.max(0,second.icon()),distance,first.maneuver.afterRoad,ClusterIcon.isTunnelText(first.maneuver.afterRoad,first.maneuver.desc),first.laneFrame(),false);}
 private static Snapshot clear(){return new Snapshot(0,0,-1,null,false,LaneFrame.clear(),true);}
 private static boolean same(AaNavigationParser.Step a,AaNavigationParser.Step b){
  return a.aaType==b.aaType && a.roundaboutExit==b.roundaboutExit && a.roundaboutAngle==b.roundaboutAngle
   && equal(a.maneuver.afterRoad,b.maneuver.afterRoad) && equal(a.maneuver.desc,b.maneuver.desc);
 }
 private static boolean equal(String a,String b){return a==null?b==null:a.equals(b);}
}
