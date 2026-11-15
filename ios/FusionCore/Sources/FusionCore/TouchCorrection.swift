import Foundation
import CoreGraphics

/// Port of the original TrueTap TouchModel / SpatialModel used by TouchCorrector.
/// Models live only for the keyboard session, as in the Android touch handler.
public final class TouchCorrection {
    private struct Stats { var x=0.0,y=0.0,vx=0.42*0.42,vy=0.34*0.34,n=0 }
    private var global=Stats()
    private var perKey:[String:Stats]=[:]
    public init() {}
    private func params(_ code:String) -> (Double,Double,Double,Double) {
        let weight=Double(global.n)/(Double(global.n)+30)
        let x=global.x*weight,y=global.y*weight
        let vx=0.42*0.42+(global.vx-0.42*0.42)*weight,vy=0.34*0.34+(global.vy-0.34*0.34)*weight
        guard let key=perKey[code],key.n>0 else { return (x,y,sqrt(vx),sqrt(vy)) }
        let w=Double(key.n)/(Double(key.n)+25)
        return (x+(key.x-x)*w,y+(key.y-y)*w,sqrt(vx+(key.vx-vx)*w),sqrt(vy+(key.vy-vy)*w))
    }
    public func corrected(point:CGPoint,frames:[String:CGRect],codes:[String:String],learn:Bool) -> String? {
        guard let hit=frames.first(where:{$0.value.contains(point)}) else { return nil }
        guard codes[hit.key] != nil else { return hit.key }
        let eligible=frames.filter{codes[$0.key] != nil && $0.value.width>0}
        let winner=eligible.max { score(point,$0.value,codes[$0.key]!) < score(point,$1.value,codes[$1.key]!) }?.key ?? hit.key
        if learn && winner == hit.key,let code=codes[winner] {
            let rect=hit.value,dx=Double((point.x-rect.midX)/rect.width),dy=Double((point.y-rect.midY)/rect.width)
            if dx*dx+dy*dy<=1.2 {
                update(&global,dx,dy,rate:0.01)
                var stats=perKey[code] ?? Stats();update(&stats,dx,dy,rate:0.05);perKey[code]=stats
            }
        }
        return winner
    }
    private func score(_ point:CGPoint,_ rect:CGRect,_ code:String) -> Double {
        let (x,y,sx,sy)=params(code),w=Double(rect.width)
        let dx=(Double(point.x-rect.midX)/w-x)/sx,dy=(Double(point.y-rect.midY)/w-y)/sy
        return -0.5*(dx*dx+dy*dy)-log(sx*sy)
    }
    private func update(_ stats:inout Stats,_ dx:Double,_ dy:Double,rate:Double) {
        stats.n+=1;let a=max(1/Double(stats.n),rate),ex=dx-stats.x,ey=dy-stats.y
        stats.x=min(0.5,max(-0.5,stats.x+a*ex));stats.y=min(0.5,max(-0.5,stats.y+a*ey))
        stats.vx=min(0.49,max(0.04,(1-a)*stats.vx+a*ex*ex));stats.vy=min(0.49,max(0.04,(1-a)*stats.vy+a*ey*ey))
    }
}
