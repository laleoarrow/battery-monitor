import Foundation

@main private enum InverseRegression {
    static func main() {
        let previous = HistoryChartGeometry(samples: [20,60,90],
            timing: .init(sampledAt:[0,2,4],referenceTime:4),ceiling:150)
        let target = HistoryChartGeometry(samples:[20,60,90,140],
            timing:.init(sampledAt:[0,2,4,6],referenceTime:6),ceiling:200)
        let visible = previous.segments.map { c in
            let width=c.end.x-c.start.x
            return HistoryChartGeometry.Cubic(start:c.start,
                control1:.init(x:c.start.x+width*0.17,y:c.control1.y),
                control2:.init(x:c.start.x+width*0.58,y:c.control2.y),end:c.end)
        }
        guard let start=target.alignedStart(from:previous,presentedSegments:visible,
            fraction:2/120,oldCeiling:150,newCeiling:200) else { exit(2) }
        var maximum=0.0, failures=0, checks=0
        for q in [0.0,0.13,0.37,0.69,1.0] {
            for (a,b) in zip(start.segments,target.segments) {
                let p=zip([a.start,a.control1,a.control2,a.end],[b.start,b.control1,b.control2,b.end]).map { x,y in
                    HistoryChartGeometry.Point(x:x.x*(1-q)+y.x*q,y:x.y*(1-q)+y.y*q)
                }
                for t in [0.07,0.23,0.51,0.82,0.97] {
                    let u=1-t
                    let x=u*u*u*p[0].x+3*u*u*t*p[1].x+3*u*t*t*p[2].x+t*t*t*p[3].x
                    let y=u*u*u*p[0].y+3*u*u*t*p[1].y+3*u*t*t*p[2].y+t*t*t*p[3].y
                    guard let actual=target.value(at:x,blendingFrom:start,progress:q) else { exit(3) }
                    let error=abs(actual-y)*64;maximum=max(maximum,error);checks+=1
                    if error>0.000001 { failures+=1 }
                }
            }
        }
        let result:[String:Any]=["checks":checks,"failures":failures,"maximumErrorPoints":maximum]
        let bytes=try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        print(String(data:bytes,encoding:.utf8)!)
    }
}
