import AppKit

/// Paced native particles with optional, prevalidated 3D flybys.
/// Unselected clocks stay unchanged; capture is an explicit active guide force.
struct EnergyFlowMotion {
    struct Particle {
        let id, source, destination: Int
        let size, offset, spread, speed, referenceLength, routeLength, delay, period: CGFloat
        let isComet: Bool
    }

    struct Sample {
        let point: CGPoint
        let worldZ: CGFloat
        let projectedVelocity: CGPoint
        let isExternal: Bool
        let depth, tailStrength, tailGrowth, opacity: CGFloat
    }

    private typealias Vector = SIMD3<Double>
    private struct State {
        var p, v, a: Vector
    }
    private struct Knot {
        let time: Double
        let state: State
    }
    private struct Route {
        let curves: [PipeGeometry]
        let tables: [EnergyFlowPath]
        let offset, hiddenZ: Double
        var length: Double { tables.reduce(0) { $0 + Double($1.length) } }

        func state(distance: Double, speed: Double) -> State {
            var remaining = min(length, max(0, distance))
            var piece = 0
            while piece < tables.count - 1 && remaining > Double(tables[piece].length) {
                remaining -= Double(tables[piece].length)
                piece += 1
            }
            let t = Double(tables[piece].sampleIndex(atDistance: CGFloat(remaining))) / 768
            let curve = curves[piece]
            let p0 = Vector(Double(curve.start.x), Double(curve.start.y), 0)
            let p1 = Vector(Double(curve.control1.x), Double(curve.control1.y), 0)
            let p2 = Vector(Double(curve.control2.x), Double(curve.control2.y), 0)
            let p3 = Vector(Double(curve.end.x), Double(curve.end.y), 0)
            let u = 1 - t
            let p = u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
            let first = 3*u*u*(p1-p0) + 6*u*t*(p2-p1) + 3*t*t*(p3-p2)
            let secondLeft: Vector = (p2-p1*2+p0)*(6*u)
            let secondRight: Vector = (p3-p2*2+p1)*(6*t)
            let second = secondLeft+secondRight
            let norm2 = Self.dot(first, first)
            let v = first * (speed / sqrt(norm2))
            let a = speed*speed * (second / norm2 - first * (Self.dot(first, second) / (norm2*norm2)))
            return State(p: p + Vector(0, offset, hiddenZ), v: v, a: a)
        }
        func distance(atX x: Double) -> Double {
            var lower = 0.0, upper = length
            for _ in 0..<40 {
                let middle = (lower + upper) / 2
                if state(distance: middle, speed: 1).p.x < x { lower = middle } else { upper = middle }
            }
            return (lower + upper) / 2
        }
        private static func dot(_ a: Vector, _ b: Vector) -> Double { a.x*b.x + a.y*b.y + a.z*b.z }
    }

    private struct Flyby {
        let knots: [Knot]
        let start, freeStart, captureStart, end, tOut, tReturn: Double
        let metrics: [String: Double]
        func state(at time: Double) -> State {
            var lower = 0, upper = knots.count - 1
            while lower + 1 < upper {
                let middle = (lower + upper) / 2
                if knots[middle].time <= time { lower = middle } else { upper = middle }
            }
            let a = knots[lower], b = knots[upper]
            return EnergyFlowMotion.quintic(a.state, b.state, duration: b.time-a.time,
                                                elapsed: time-a.time)
        }
    }

    /// Polygons follow the actual rendered cubic ribbon edges and its taper.
    /// Only positive distance matters: outside distance to their union is exact
    /// up to the boundary sampling, including both alternative output pipes.
    private struct PipeUnion {
        let polygons: [[CGPoint]]
        let tubes: [Tube]
        struct Probe {
            let clearance: Double
            let front: Double?
        }
        struct Tube {
            let curve: PipeGeometry
            let from, to: Double
            func section(_ x: Double) -> (center: Double, radius: Double)? {
                guard x >= Double(curve.start.x),x <= Double(curve.end.x) else { return nil }
                var lower=0.0,upper=1.0
                for _ in 0..<30 {
                    let t=(lower+upper)/2
                    if Double(curve.point(at:CGFloat(t)).x)<x { lower=t } else { upper=t }
                }
                let t=(lower+upper)/2,blend=t*t*(3-2*t)
                return (Double(curve.point(at:CGFloat(t)).y),(from+(to-from)*blend)/2)
            }
        }
        func probe(_ point: Vector) -> Probe {
            var clearance=Double.infinity
            var front:Double?
            for tube in tubes {
                guard let section=tube.section(point.x) else { continue }
                let dy=point.y-section.center,r=section.radius
                clearance=min(clearance,hypot(dy,point.z)-r)
                if abs(dy)<=r {
                    front=max(front ?? 0,sqrt(max(0,r*r-dy*dy)))
                }
            }
            return Probe(clearance:clearance,front:front)
        }
        func headClearance(_ point:Vector,radius:Double)->Double {
            var minimum=Double.infinity
            for index in 0...24 {
                let dx=radius*(Double(index)/12-1)
                let diskRadius=sqrt(max(0,radius*radius-dx*dx))
                minimum=min(minimum,-probe(point+Vector(dx,0,0)).clearance-diskRadius)
            }
            return minimum
        }
        func headOcclusion(_ point:Vector,radius:Double)->(back:Bool,front:Bool) {
            var back=true,front=true
            for ix in -4...4 {
                for iy in -4...4 {
                    let x=Double(ix)/4,y=Double(iy)/4,q=x*x+y*y
                    guard q<=1 else { continue }
                    guard let surface=probe(point+Vector(radius*x,radius*y,0)).front else {
                        back=false
                        continue
                    }
                    let dz=radius*sqrt(max(0,1-q))
                    back=back && point.z+dz < -surface
                    front=front && point.z-dz > surface
                }
            }
            return (back,front)
        }
        func signedDistance(_ point: CGPoint) -> Double {
            var closest = Double.infinity
            var insideAny = false
            for polygon in polygons {
                var inside = false
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i+1) % polygon.count]
                    let dx = Double(b.x-a.x), dy = Double(b.y-a.y)
                    let px = Double(point.x-a.x), py = Double(point.y-a.y)
                    let denominator = dx*dx + dy*dy
                    let t = denominator > 0 ? min(1, max(0, (px*dx+py*dy)/denominator)) : 0
                    closest = min(closest, hypot(px-t*dx, py-t*dy))
                    if (a.y > point.y) != (b.y > point.y),
                       point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
                }
                insideAny = insideAny || inside
            }
            return insideAny ? -closest : closest
        }
    }

    private final class Prepared {
        var particles: [Particle] = []
        var routes: [Route] = []
        var flybys: [Int: Flyby] = [:]
        var swirls: [Int: Flyby] = [:]
#if DEBUG
        var enhancedFailures: [String:Int] = [:]
        var enhancedLast: [String:Double] = [:]
        var rejected: [[String: Any]] = []
#endif
        let union: PipeUnion
        let radius: Double
        let strength: Double = 900
        init(union: PipeUnion, radius: Double) { self.union = union; self.radius = radius }
    }
    private static let cacheLock=NSLock()
    private static let cacheCapacity=4
    private static var cache: [String: Prepared] = [:]
    private static var cacheOrder:[String]=[]
    private let prepared: Prepared
    var particles: [Particle] { prepared.particles }
    func path(for particle:Particle)->CGPath {
        let route=prepared.routes[particle.id],path=CGMutablePath()
        func shifted(_ point:CGPoint)->CGPoint { CGPoint(x:point.x,y:point.y+CGFloat(route.offset)) }
        path.move(to:shifted(route.curves[0].start))
        for curve in route.curves {
            path.addCurve(to:shifted(curve.end),control1:shifted(curve.control1),control2:shifted(curve.control2))
        }
        return path
    }
    func animationCycle(for particle:Particle)->(startTime:CGFloat,duration:CGFloat) {
        guard let flyby=prepared.swirls[particle.id] else { return (0,particle.period) }
        let initial=particle.delay*particle.referenceLength/particle.speed
        let start=CGFloat(firstEnhancedCycle(particle,flyby))*particle.period-initial
        return (max(0,start),2*particle.period+CGFloat(flyby.metrics["phaseDebt"]!))
    }
    func pipeFrontDepth(at point: CGPoint) -> CGFloat? {
        prepared.union.probe(Vector(Double(point.x),Double(point.y),0)).front.map { CGFloat($0) }
    }
    /// Exact at mask pixel centres. Each column reuses its cubic intersections
    /// across all rows; the returned sampler owns only immutable cross-sections.
    func makePipeFrontDepthSampler(width:CGFloat,scale:CGFloat=2,
                                   isCancelled:()->Bool={false})->((CGPoint)->CGFloat?)? {
        precondition(width.isFinite && width>0 && scale.isFinite && scale>0)
        guard !isCancelled() else { return nil }
        let count=Int(ceil(width*scale))
        var samples:[[(center:Double,radius:Double)]]=[]
        samples.reserveCapacity(count)
        for index in 0..<count {
            guard !isCancelled() else { return nil }
            let x=Double((CGFloat(index)+0.5)/scale)
            samples.append(prepared.union.tubes.compactMap { $0.section(x) })
        }
        guard !isCancelled() else { return nil }
        let columns=samples
        return { point in
            guard point.x.isFinite,point.y.isFinite,point.x>=0,point.x<width else { return nil }
            let index=Int(floor(point.x*scale))
            var front:Double?
            for section in columns[index] {
                let dy=Double(point.y)-section.center,r=section.radius
                if abs(dy)<=r { front=max(front ?? 0,sqrt(max(0,r*r-dy*dy))) }
            }
            return front.map { CGFloat($0) }
        }
    }
    private func firstEnhancedCycle(_ p:Particle,_ flyby:Flyby)->Int {
        let initial=Double(p.delay*p.referenceLength/p.speed)
        return max(0,Int(ceil((initial-flyby.start+0.08)/Double(p.period))))
    }
    /// The selected ID alone keeps its capture delay on every following pass.
    /// A pair contains one extended 3D pass, followed by one ordinary-length pass.
    private func clock(_ p:Particle,_ elapsed:Double)->(phase:Double,flyby:Flyby?,enhanced:Bool,debt:Double) {
        let period=Double(p.period)
        guard let swirl=prepared.swirls[p.id] else {
            return (Self.mod(elapsed,period),prepared.flybys[p.id],false,0)
        }
        let first=Double(firstEnhancedCycle(p,swirl))*period
        guard elapsed>=first else { return (Self.mod(elapsed,period),prepared.flybys[p.id],false,0) }
        let debt=swirl.metrics["phaseDebt"]!,pairLength=2*period+debt
        let pair=floor((elapsed-first)/pairLength),within=elapsed-first-pair*pairLength
        if within<period+debt {
            if within<=swirl.end { return (within,swirl,true,pair*debt) }
            return (within-debt,nil,true,(pair+1)*debt)
        }
        return (within-period-debt,prepared.flybys[p.id],false,(pair+1)*debt)
    }
#if DEBUG
    var enhancedParticleIDForTest:Int? { prepared.swirls.keys.sorted().first }
    static func resetCacheForTest() {
        cacheLock.lock();defer { cacheLock.unlock() }
        cache.removeAll();cacheOrder.removeAll()
    }
    static var cacheEntryCountForTest:Int {
        cacheLock.lock();defer { cacheLock.unlock() };return cache.count
    }
    var reviewTimes: [String: CGFloat] {
        if let id=prepared.swirls.keys.sorted().first,let flyby=prepared.swirls[id] {
            let p=particles[id],initial=Double(p.delay*p.referenceLength/p.speed)
            let start=Double(firstEnhancedCycle(p,flyby))*Double(p.period)-initial
            func global(_ phase:Double)->CGFloat { CGFloat(start+phase) }
            return ["01-input":global(flyby.start-0.08),"02-departure":global(flyby.tOut+0.015),
                "03-flight":global(flyby.metrics["peakVisiblePhase"]!),"04-return":global(flyby.end),
                "05-behind":global(flyby.metrics["backTime"]!),"06-front":global(flyby.metrics["frontTime"]!)]
        }
        guard let id = prepared.flybys.keys.sorted().first, let flyby = prepared.flybys[id] else { return [:] }
        let p = particles[id]
        let initialTime = Double(p.delay*p.referenceLength/p.speed)
        let cycleOffset=ceil((initialTime-flyby.start+0.12)/Double(p.period))*Double(p.period)
        func global(_ phase: Double) -> CGFloat { CGFloat(phase-initialTime+cycleOffset) }
        return ["01-input": global(flyby.start-0.12), "02-departure": global(flyby.tOut+0.015),
                "03-flight": global(flyby.metrics["peakVisiblePhase"]!), "04-return": global(flyby.end)]
    }
    var heroTime: CGFloat { reviewTimes["03-flight"] ?? 0.5 }
#endif

    init?(incoming: [PipeGeometry], outgoing: [PipeGeometry], jointWidth: CGFloat,
         snapshot: PowerSnapshot, inputWidths: [CGFloat], outputWidths: [CGFloat],
         particleCounts:[Int]?=nil,hot:[Bool]?=nil,includeFlybys:Bool=true,
         isCancelled:()->Bool={false}) {
        guard !isCancelled(),incoming.count==2,outgoing.count==2,inputWidths.count==2,outputWidths.count==2,
              jointWidth.isFinite,jointWidth>0 else { return nil }
        let nativeCount=Int((2+VisualEncoding.t(snapshot.totalInputW)*6+VisualEncoding.over(snapshot.totalInputW)*5).rounded())
        let counts=particleCounts ?? [nativeCount,nativeCount]
        let hotSources=hot ?? [snapshot.totalInputW>=Double(VisualEncoding.wRef),snapshot.totalInputW>=Double(VisualEncoding.wRef)]
        guard counts.count==2,counts.allSatisfy({$0>=0}),hotSources.count==2 else { return nil }
        let values = (incoming+outgoing).flatMap { [$0.start.x,$0.start.y,$0.control1.x,$0.control1.y,
                                                   $0.control2.x,$0.control2.y,$0.end.x,$0.end.y] }
            + inputWidths + outputWidths + [jointWidth, CGFloat(snapshot.adapterW), CGFloat(snapshot.batteryW)]
        guard values.allSatisfy({$0.isFinite}),inputWidths.allSatisfy({$0>0}),outputWidths.allSatisfy({$0>0}) else { return nil }
        let key = values.map { String(Double($0)) }.joined(separator: ",")
            + ":" + counts.map(String.init).joined(separator:",") + ":" + hotSources.map{$0 ? "1":"0"}.joined()
            + ":" + (includeFlybys ? "flybys":"native")
        Self.cacheLock.lock()
        let cached=Self.cache[key]
        if cached != nil { Self.cacheOrder.removeAll{$0==key};Self.cacheOrder.append(key) }
        Self.cacheLock.unlock()
        if let cached { prepared=cached;return }
        let radius = Double(jointWidth/2)
        var polygons: [[CGPoint]] = []
        var tubes:[PipeUnion.Tube]=[]
        for i in 0..<2 {
            let inputNeck = 2*abs(incoming[1-i].end.y-90)
            let outputNeck = 2*abs(outgoing[1-i].start.y-90)
            polygons.append(Self.ribbon(incoming[i], from: inputWidths[i], to: inputNeck))
            polygons.append(Self.ribbon(outgoing[i], from: outputNeck, to: outputWidths[i]))
            tubes.append(PipeUnion.Tube(curve:incoming[i],from:Double(inputWidths[i]),to:Double(inputNeck)))
            tubes.append(PipeUnion.Tube(curve:outgoing[i],from:Double(outputNeck),to:Double(outputWidths[i])))
        }
        polygons.append([CGPoint(x:146,y:90-jointWidth/2),CGPoint(x:182,y:90-jointWidth/2),
                         CGPoint(x:182,y:90+jointWidth/2),CGPoint(x:146,y:90+jointWidth/2)])
        let common=PipeGeometry(start:CGPoint(x:146,y:90),control1:CGPoint(x:158,y:90),
            control2:CGPoint(x:170,y:90),end:CGPoint(x:182,y:90))
        tubes.append(PipeUnion.Tube(curve:common,from:Double(jointWidth),to:Double(jointWidth)))
        let data = Prepared(union: PipeUnion(polygons: polygons,tubes:tubes), radius: radius)
        let nativeWidths = [VisualEncoding.thickness(snapshot.adapterW), VisualEncoding.thickness(-snapshot.batteryW)]
        let multiplier = Double(VisualEncoding.multiplier(snapshot.totalInputW))
        for source in 0..<2 {
            guard !isCancelled() else { return nil }
            let referenceY: CGFloat = source == 0 ? 90-nativeWidths[1]/2 : 90+nativeWidths[0]/2
            let startY: CGFloat = source == 0 ? 51 : 129
            let reference = PipeGeometry(start: CGPoint(x:53,y:startY),control1: CGPoint(x:138,y:startY),
                control2: CGPoint(x:190,y:referenceY),end: CGPoint(x:275,y:referenceY))
            let referenceLength = Self.table(reference).length
            let seeds = EnergyFlowParticleSeed.make(seed: source == 0 ? 11 : 29, count: counts[source],
                                                        thickness: nativeWidths[source],hot:hotSources[source])
            for (index, seed) in seeds.enumerated() {
                guard !isCancelled() else { return nil }
                let id = data.particles.count
                // Fixed before any flyby test; rejected and accepted particles
                // keep the same destination and phase throughout their lives.
                let destination = (index+source+1) % 2
                let bridge = PipeGeometry(start: incoming[source].end,
                    control1: CGPoint(x:158,y:incoming[source].end.y),
                    control2: CGPoint(x:170,y:outgoing[destination].start.y),end:outgoing[destination].start)
                let curves = [incoming[source],bridge,outgoing[destination]]
                let route = Route(curves:curves,tables:curves.map(Self.table),
                                  offset:Double(seed.offset),hiddenZ:0.22*radius)
                let speed = Double(referenceLength)*multiplier/(2.4*Double(seed.spread))
                data.routes.append(route)
                data.particles.append(Particle(id:id,source:source,destination:destination,size:seed.radius,
                    offset:seed.offset,spread:seed.spread,speed:CGFloat(speed),referenceLength:referenceLength,
                    routeLength:CGFloat(route.length),delay:seed.delay,period:CGFloat(route.length/speed),isComet:false))
            }
        }
        let supportsFlyby=(0..<2).allSatisfy { index in
            let y:CGFloat=index==0 ? 51:129
            return incoming[index].start==CGPoint(x:53,y:y) && incoming[index].end.x==146
                && outgoing[index].start.x==182 && outgoing[index].end==CGPoint(x:275,y:y)
        }
        let eligible = supportsFlyby && includeFlybys ? Array(data.particles.sorted { $0.speed > $1.speed }.prefix(2)) : []
        for particle in eligible {
            guard !isCancelled() else { return nil }
            let route = data.routes[particle.id]
            let speed = Double(particle.speed)
            var release: Double?
            for step in 0...40 {
                let distance = route.distance(atX: 128+Double(step)*0.25)
                if Self.norm(route.state(distance:distance,speed:speed).a) >= 280 { release=distance/speed; break }
            }
            guard let release else {
#if DEBUG
                data.rejected.append(["id":particle.id,"reason":"native guide demand below 280 pt/s²"])
#endif
                continue
            }
            var accepted: Flyby?
            for freeX in [210.0,202] {
                    if let candidate = Self.candidate(particle,route:route,release:release,freeX:freeX,
                                                      captureDuration:0.50,data:data,isCancelled:isCancelled) {
                        accepted=candidate;break
                    }
            }
            if let accepted { data.flybys[particle.id]=accepted }
#if DEBUG
            if accepted==nil { data.rejected.append(["id":particle.id,"reason":"trajectory rejected by speed, radius, guide or visible-exit checks"]) }
#endif
        }
        for particle in eligible {
            guard !isCancelled() else { return nil }
            guard let base=data.flybys[particle.id] else { continue }
            if let enhanced=Self.enhancedCandidate(particle,route:data.routes[particle.id],
                release:base.start,amplitude:1.4,freeX:194,captureDuration:0.80,
                gateX:243,gateSign:-1,data:data,isCancelled:isCancelled),
                2*Double(particle.period)+enhanced.metrics["phaseDebt"]!>=3 {
                data.swirls[particle.id]=enhanced;break
            }
        }
        data.particles = data.particles.map { p in
            Particle(id:p.id,source:p.source,destination:p.destination,size:p.size,offset:p.offset,spread:p.spread,speed:p.speed,
                     referenceLength:p.referenceLength,routeLength:p.routeLength,delay:p.delay,period:p.period,
                     isComet:data.flybys[p.id] != nil)
        }
        guard !isCancelled() else { return nil }
        // No Prepared fields change after publication. Readers need no lock.
        Self.cacheLock.lock()
        if let existing=Self.cache[key] { prepared=existing }
        else {
            while Self.cacheOrder.count>=Self.cacheCapacity {
                Self.cache.removeValue(forKey:Self.cacheOrder.removeFirst())
            }
            Self.cache[key]=data;Self.cacheOrder.append(key);prepared=data
        }
        Self.cacheLock.unlock()
    }

    func age(_ p: Particle, time: CGFloat) -> CGFloat? {
        // Unwrapped time makes real tail-history samples cross loop boundaries
        // without forgetting which pass owns an occasional 3D event.
        time+p.delay*p.referenceLength/p.speed
    }
    func sample(_ p: Particle, age: CGFloat) -> Sample {
        let resolved=clock(p,Double(age)),phase=resolved.phase
        let route = prepared.routes[p.id]
        let state: State
        var strength=0.0, growth=0.0
        if let flyby=resolved.flyby, phase >= flyby.start, phase <= flyby.end {
            state=flyby.state(at:phase)
            if phase > flyby.tOut && phase < flyby.tReturn {
                // Visibility is independently depth-masked. Going behind the
                // tube does not cancel the physical outside/capture lifecycle.
                strength=Self.smooth((phase-flyby.tOut)/0.12)*Self.smooth((flyby.tReturn-phase)/0.10)
                growth=Self.smooth((phase-flyby.tOut)/0.16)*Self.smooth((flyby.tReturn-phase)/0.10)
            }
        } else { state=route.state(distance:phase*Double(p.speed),speed:Double(p.speed)) }
        let depth=max(-1,min(1,state.p.z/(3*prepared.radius)))
        let fraction=resolved.enhanced ? (state.p.x-53)/222 : phase/Double(p.period)
        let opacity=min(1,min(fraction/0.09,(1-fraction)/0.14))
        let external=prepared.union.probe(state.p).clearance>0
        if !external { strength=0;growth=0 }
        return Sample(point:CGPoint(x:state.p.x,y:state.p.y),worldZ:CGFloat(state.p.z),
                      projectedVelocity:CGPoint(x:state.v.x,y:state.v.y),isExternal:external,depth:CGFloat(depth),
                      tailStrength:CGFloat(strength),tailGrowth:CGFloat(growth),opacity:CGFloat(max(0,opacity)))
    }

    private static func swirlGuide(_ route:Route, speed:Double, time:Double,
                                   release:Double, amplitude:Double, radius:Double)->State {
        let base=route.state(distance:time*speed,speed:speed)
        func jet(_ u:Double,_ duration:Double)->(Double,Double,Double) {
            if u<=0 { return (0,0,0) }; if u>=1 { return (1,0,0) }
            return (smooth(u),30*u*u*(u-1)*(u-1)/duration,
                    60*u*(2*u*u-3*u+1)/(duration*duration))
        }
        let center=jet((time-release+0.50)/0.24,0.24)
        let alpha=jet((time-release+0.26)/0.20,0.20)
        let a=amplitude*alpha.0,ad=amplitude*alpha.1,add=amplitude*alpha.2
        let omega=26.0,phi=Double.pi/2+omega*(time-release)
        let n=a*cos(phi),nd=ad*cos(phi)-a*omega*sin(phi)
        let ndd=(add-a*omega*omega)*cos(phi)-2*ad*omega*sin(phi)
        let z=a*sin(phi),zd=ad*sin(phi)+a*omega*cos(phi)
        let zdd=(add-a*omega*omega)*sin(phi)+2*ad*omega*cos(phi)
        let normal=Vector(-base.v.y,base.v.x,0)/speed
        let normalD=Vector(-base.a.y,base.a.x,0)/speed
        let h=0.0002
        let left=route.state(distance:(time-h)*speed,speed:speed).a
        let right=route.state(distance:(time+h)*speed,speed:speed).a
        let jerk=(right-left)/(2*h)
        let normalDD=Vector(-jerk.y,jerk.x,0)/speed
        let shift=Vector(0,-route.offset,0.05*radius-route.hiddenZ)
        let p=base.p+shift*center.0+normal*n+Vector(0,0,z)
        let v=base.v+shift*center.1+normal*nd+normalD*n+Vector(0,0,zd)
        let acceleration=base.a+shift*center.2+normal*ndd+normalD*(2*nd)+normalDD*n+Vector(0,0,zdd)
        return State(p:p,v:v,a:acceleration)
    }

    private static func enhancedCandidate(_ particle:Particle,route:Route,release:Double,
        amplitude:Double,freeX:Double,captureDuration:Double,gateX:Double,gateSign:Double,data:Prepared,
        isCancelled:()->Bool)->Flyby? {
        guard !isCancelled() else { return nil }
        let speed=Double(particle.speed),R=data.radius,K=data.strength,dt=1.0/480,fade=0.10
        let head=Double(particle.size)*1.08,prepStart=release-0.50
        func reject(_ reason:String)->Flyby? {
#if DEBUG
            data.enhancedFailures[reason,default:0] += 1
#endif
            return nil
        }
        func guide(_ time:Double)->State {
            swirlGuide(route,speed:speed,time:time,release:release,amplitude:amplitude,radius:R)
        }
        func field(_ p:Vector)->Vector {
            let q=Vector(0,p.y-90,p.z); return -K*q/(R*R+q.y*q.y+q.z*q.z)
        }
        func force(_ p:Vector,_ time:Double)->Vector {
            let blend=smooth((time-release)/fade)
            if blend>=1 { return field(p) }
            return guide(time).a*(1-blend)+field(p)*blend
        }
        var knots:[Knot]=[]
        var prepClearance=Double.infinity,prepPeakAcceleration=0.0,prepMaxSpeedRatio=0.0,prepMinVX=Double.infinity
        let prepCount=Int(ceil(0.50/dt))
        for index in 0...prepCount {
            if index%16==0,isCancelled() { return nil }
            let time=prepStart+0.50*Double(index)/Double(prepCount)
            let state=guide(time),clearance=data.union.headClearance(state.p,radius:head)
            prepClearance=min(prepClearance,clearance)
            prepPeakAcceleration=max(prepPeakAcceleration,norm(state.a))
            prepMaxSpeedRatio=max(prepMaxSpeedRatio,norm(state.v)/speed)
            prepMinVX=min(prepMinVX,state.v.x)
            if clearance<0.15 {
#if DEBUG
                data.enhancedLast=["prepX":state.p.x,"prepY":state.p.y,"prepZ":state.p.z,
                    "prepTimeToRelease":time-release,"prepClearance":clearance,"amplitude":amplitude]
#endif
                return reject("prep clearance")
            }
            knots.append(Knot(time:time,state:state))
        }
        var time=release,state=guide(release)
        while state.p.x<freeX {
            if isCancelled() { return nil }
            if time-release>1.2 { return reject("free travel timeout") }
            state=rk4(state,time:time,step:dt,force:force); time += dt
            knots.append(Knot(time:time,state:state))
        }
        let captureStart=time,captureState=state,end=time+captureDuration
        let targetPhase=min(end,Double(particle.period)-0.09)
        let debt=end-targetPhase
        let target=route.state(distance:targetPhase*speed,speed:speed)
        let tube=data.union.tubes[2*particle.destination+1]
        func gatePoint(_ x:Double)->Vector {
            let section=tube.section(x)!
            let dx=0.02
            let slope=(tube.section(x+dx)!.center-tube.section(x-dx)!.center)/(2*dx)
            let normal=Vector(-slope,1,0)/sqrt(1+slope*slope)
            let p=Vector(x,section.center,0)+normal*(gateSign*0.75*section.radius)
            let local=tube.section(p.x)!,dy=p.y-local.center
            let z=sqrt(max(0,pow(local.radius+head+0.15,2)-dy*dy))
            return Vector(p.x,p.y,z)
        }
        let h=0.05,gp=gatePoint(gateX),left=gatePoint(gateX-h),right=gatePoint(gateX+h)
        let first=(right-left)/(2*h),second=(right-gp*2+left)/(h*h)
        let tangentNorm=norm(first),gateSpeed=0.90*speed
        let dot=first.x*second.x+first.y*second.y+first.z*second.z
        let gate=State(p:gp,v:first*(gateSpeed/tangentNorm),
            a:(second/(tangentNorm*tangentNorm)-first*(dot/pow(tangentNorm,4)))*(gateSpeed*gateSpeed))
        let firstDuration=captureDuration*0.65,gateTime=captureStart+firstDuration
        let count=Int(ceil(captureDuration/dt))
        for index in 1...count {
            if index%16==0,isCancelled() { return nil }
            let elapsed=captureDuration*Double(index)/Double(count)
            let s=elapsed<=firstDuration
                ? quintic(captureState,gate,duration:firstDuration,elapsed:elapsed)
                : quintic(gate,target,duration:captureDuration-firstDuration,elapsed:elapsed-firstDuration)
            knots.append(Knot(time:captureStart+elapsed,state:s))
        }
        knots.append(Knot(time:gateTime,state:gate))
        knots.sort { $0.time < $1.time }
        var tOut:Double?,permanentReturn:Double?,enteredTarget=false
        var behind=0.0,front=0.0,minVX=Double.infinity,maxRatio=0.0,maxCentral=0.0,maxControl=0.0
        var zMin=Double.infinity,zMax = -Double.infinity,backTime=release,frontTime=release
        var maximumOutsideHeadDistance=0.0
        var bestBack=0.0,bestFront=0.0,outsideTime=0.0
        var freeEnergy:[Double]=[],freeH:[Double]=[],freeVX:[Double]=[],angles:[Double]=[]
        var capturePositiveWork=0.0,captureNegativeWork=0.0,prepPositiveWork=0.0,prepNegativeWork=0.0
        for pair in zip(knots,knots.dropFirst()) {
            if isCancelled() { return nil }
            func power(_ s:State)->Double {
                let force=s.a-field(s.p)
                return force.x*s.v.x+force.y*s.v.y+force.z*s.v.z
            }
            let interval=pair.1.time-pair.0.time,p0=power(pair.0.state),p1=power(pair.1.state)
            let positive=(max(0,p0)+max(0,p1))*interval/2,negative=(min(0,p0)+min(0,p1))*interval/2
            if pair.0.time>=captureStart {
                capturePositiveWork += positive;captureNegativeWork += negative
            } else if pair.1.time<=release+fade {
                prepPositiveWork += positive;prepNegativeWork += negative
            }
        }
        var previousTime=release
        var previousKnot=Knot(time:release,state:guide(release))
        for knot in knots where knot.time>=release {
            if isCancelled() { return nil }
            let interval=knot.time-previousTime
            previousTime=knot.time
            let prior=previousKnot
            previousKnot=knot
            let s=knot.state,probe=data.union.probe(s.p)
            let rho=hypot(s.p.y-90,s.p.z)
            minVX=min(minVX,s.v.x); maxRatio=max(maxRatio,norm(s.v)/speed)
            zMin=min(zMin,s.p.z);zMax=max(zMax,s.p.z)
            if s.p.x>=146 && s.p.x<=182 { maxCentral=max(maxCentral,rho+head) }
            else { maximumOutsideHeadDistance=max(maximumOutsideHeadDistance,probe.clearance+head) }
            if probe.clearance>0 {
                if tOut==nil { tOut=knot.time }
                if enteredTarget { return reject("exited target after entry") }
                outsideTime += interval
            } else if tOut != nil {
                guard knot.time>=gateTime, s.p.z>0,
                      let section=tube.section(s.p.x),hypot(s.p.y-section.center,s.p.z)<=section.radius else {
#if DEBUG
                    data.enhancedLast=["earlyEntryX":s.p.x,"z":s.p.z,"clearance":probe.clearance,
                        "behind":behind,"front":front,"amplitude":amplitude,"freeX":freeX,
                        "gateX":gateX,"gateSign":gateSign,"duration":captureDuration]
#endif
                    return reject("early or wrong body entry")
                }
                if !enteredTarget {
                    var lower=prior.time,upper=knot.time
                    for _ in 0..<28 {
                        let middle=(lower+upper)/2
                        let interpolated=quintic(prior.state,knot.state,
                            duration:knot.time-prior.time,elapsed:middle-prior.time)
                        if data.union.probe(interpolated.p).clearance>0 { lower=middle }
                        else { upper=middle }
                    }
                    permanentReturn=(lower+upper)/2
                    enteredTarget=true
                }
            }
            if let surface=probe.front,probe.clearance>0 {
                let occlusion=data.union.headOcclusion(s.p,radius:head)
                if occlusion.back {
                    behind += interval
                    if -s.p.z>bestBack { bestBack = -s.p.z;backTime=knot.time }
                }
                if occlusion.front {
                    front += interval
                    if s.p.z-surface>bestFront { bestFront=s.p.z-surface;frontTime=knot.time }
                }
            }
            if knot.time>=captureStart { maxControl=max(maxControl,norm(s.a-field(s.p))) }
            if knot.time>=release+fade+dt && knot.time<=captureStart {
                freeEnergy.append(0.5*(s.v.y*s.v.y+s.v.z*s.v.z)+0.5*K*log(R*R+rho*rho))
                freeH.append((s.p.y-90)*s.v.z-s.p.z*s.v.y); freeVX.append(s.v.x)
            }
            angles.append(atan2(s.p.z,s.p.y-90))
        }
#if DEBUG
        data.enhancedLast=["behind":behind,"front":front,"amplitude":amplitude,"freeX":freeX,
            "gateX":gateX,"gateSign":gateSign,"duration":captureDuration,"minVX":minVX,
            "speedRatio":maxRatio,"headRadius":maxCentral,"control":maxControl,
            "maximumOutsideHeadDistance":maximumOutsideHeadDistance,"prepClearance":prepClearance]
#endif
        guard let external=tOut else { return reject("no 3D exit") }
        guard behind>=0.067 else { return reject("insufficient back occlusion") }
        guard front>=0.09 else { return reject("insufficient front overlap") }
        guard let tReturn=permanentReturn else { return reject("no permanent target entry") }
        guard minVX>0,maxRatio<=1.35,maxCentral<=3*R,maxControl<=1_400,
              maximumOutsideHeadDistance<=2*R else { return reject("motion budget") }
        let turns=zip(angles,angles.dropFirst()).reduce(0.0) { sum,pair in
            sum+abs(atan2(sin(pair.1-pair.0),cos(pair.1-pair.0)))
        }/(2*Double.pi)
        guard turns<=1.25 else { return reject("excessive turns") }
        func drift(_ values:[Double])->Double { (values.max() ?? 0)-(values.min() ?? 0) }
        func energy(_ s:State)->Double {
            let rho2=pow(s.p.y-90,2)+s.p.z*s.p.z
            return 0.5*pow(norm(s.v),2)+0.5*K*log(R*R+rho2)
        }
        let captureEnergyChange=energy(target)-energy(captureState)
        return Flyby(knots:knots,start:prepStart,freeStart:release+fade,captureStart:captureStart,end:end,
            tOut:external,tReturn:tReturn,metrics:["enhanced3D":1,"releaseTime":release,"amplitude":amplitude,
            "omega":26,"prepClearance":prepClearance,"prepPeakAcceleration":prepPeakAcceleration,
            "prepMaxSpeedRatio":prepMaxSpeedRatio,"prepMinVX":prepMinVX,
            "phaseDebt":debt,"targetPhase":targetPhase,"behindDuration":behind,"frontDuration":front,
            "backTime":backTime,"frontTime":frontTime,"peakVisiblePhase":frontTime,
            "minVX":minVX,"speedRatio":maxRatio,"centralHeadRadius":maxCentral,"peakCaptureControl":maxControl,
            "maximumOutsideHeadDistance":maximumOutsideHeadDistance,
            "capturePositiveWork":capturePositiveWork,"captureNegativeWork":captureNegativeWork,
            "prepAndReleasePositiveWork":prepPositiveWork,"prepAndReleaseNegativeWork":prepNegativeWork,
            "captureEnergyChange":captureEnergyChange,
            "captureWorkBalanceError":captureEnergyChange-capturePositiveWork-captureNegativeWork,
            "zMinimum":zMin,"zMaximum":zMax,"zSpan":zMax-zMin,"elapsed":end-release,
            "freeEnergyDrift":drift(freeEnergy),"freeAngularMomentumDrift":drift(freeH),"freeVXDrift":drift(freeVX),
            "freeAngularMomentum":freeH.first ?? 0,"totalTurnsIncludingCapture":turns,
            "outsideDuration":outsideTime,"outsideElapsedSpan":tReturn-external,
            "tailReturnPhase":tReturn,"tailEndedBeforeCaptureCompletion":end-tReturn,"captureX":captureState.p.x,
            "gateX":gp.x,"reunionX":target.p.x,"captureDuration":captureDuration])
    }

    private static func candidate(_ particle:Particle,route:Route,release:Double,freeX:Double,
                                  captureDuration:Double,data:Prepared,isCancelled:()->Bool) -> Flyby? {
        guard !isCancelled() else { return nil }
        let speed=Double(particle.speed), dt=1.0/480, fade=0.10
        let R=data.radius, K=data.strength, epsilon=R
        func field(_ p:Vector) -> Vector {
            let q=Vector(0,p.y-90,p.z)
            return -K*q/(epsilon*epsilon+q.y*q.y+q.z*q.z)
        }
        func force(_ p:Vector,_ time:Double) -> Vector {
            let blend=smooth((time-release)/fade)
            let reference=route.state(distance:time*speed,speed:speed).a
            return (1-blend)*reference+blend*field(p)
        }
        var time=release
        var state=route.state(distance:time*speed,speed:speed)
        var knots=[Knot(time:time,state:state)]
        while state.p.x < freeX {
            if isCancelled() { return nil }
            if time-release > 1 { return nil }
            state=rk4(state,time:time,step:dt,force:force)
            time += dt
            knots.append(Knot(time:time,state:state))
        }
        let captureStart=time, captureState=state, end=time+captureDuration
        guard end*speed < route.length-3 else { return nil }
        let target=route.state(distance:end*speed,speed:speed)
        let count=Int(ceil(captureDuration/dt))
        for index in 1...count {
            if index%16==0,isCancelled() { return nil }
            let elapsed=captureDuration*Double(index)/Double(count)
            knots.append(Knot(time:captureStart+elapsed,
                state:quintic(captureState,target,duration:captureDuration,elapsed:elapsed)))
        }
        var maxRatio=0.0,maxRadius=0.0,maxGuide=0.0,maxControl=0.0,minVX=Double.infinity,maxOutside=0.0
        var peakVisiblePhase=release
        var zMinimum=Double.infinity,zMaximum = -Double.infinity
        var positiveWork=0.0,negativeWork=0.0,releasePositiveWork=0.0,releaseNegativeWork=0.0
        var previousCapturePower=0.0,previousCaptureTime=captureStart
        var previousReleasePower=0.0,previousReleaseTime=release
        var maximumOutsideHeadDistance=0.0
        var freeEnergy:[Double]=[],freeMomentum:[Double]=[],freeVX:[Double]=[]
        var outside:[Double]=[]
        var angles:[Double]=[],allAngles:[Double]=[]
        var clearances:[Double]=[]
        for knot in knots {
            if isCancelled() { return nil }
            let s=knot.state
            zMinimum=min(zMinimum,s.p.z); zMaximum=max(zMaximum,s.p.z)
            maxRatio=max(maxRatio,norm(s.v)/speed); minVX=min(minVX,s.v.x)
            let control=s.a-field(s.p)
            let power=control.x*s.v.x+control.y*s.v.y+control.z*s.v.z
            if knot.time >= captureStart {
                maxGuide=max(maxGuide,norm(s.a))
                maxControl=max(maxControl,norm(control))
                let interval=knot.time-previousCaptureTime
                positiveWork += (max(0,previousCapturePower)+max(0,power))*interval/2
                negativeWork += (min(0,previousCapturePower)+min(0,power))*interval/2
                previousCapturePower=power; previousCaptureTime=knot.time
            } else if knot.time <= release+fade {
                let interval=knot.time-previousReleaseTime
                releasePositiveWork += (max(0,previousReleasePower)+max(0,power))*interval/2
                releaseNegativeWork += (min(0,previousReleasePower)+min(0,power))*interval/2
                previousReleasePower=power; previousReleaseTime=knot.time
            }
            let rho=hypot(s.p.y-90,s.p.z)
            let headRadius=Double(particle.size)*1.08
            if s.p.x >= 146 && s.p.x <= 182 { maxRadius=max(maxRadius,rho+headRadius) }
            let wall=data.union.signedDistance(CGPoint(x:s.p.x,y:s.p.y))
            clearances.append(wall)
            if wall>maxOutside { maxOutside=wall; peakVisiblePhase=knot.time }
            allAngles.append(atan2(s.p.z,s.p.y-90))
            if wall > 0.05 { outside.append(knot.time) }
            if s.p.x < 146 || s.p.x > 182 {
                maximumOutsideHeadDistance=max(maximumOutsideHeadDistance,wall+headRadius)
                if wall+headRadius > 2*R { return nil }
            }
            if knot.time >= release+fade+dt && knot.time <= captureStart {
                freeEnergy.append(0.5*(s.v.y*s.v.y+s.v.z*s.v.z)+0.5*K*log(epsilon*epsilon+rho*rho))
                freeMomentum.append((s.p.y-90)*s.v.z-s.p.z*s.v.y)
                freeVX.append(s.v.x)
                angles.append(atan2(s.p.z,s.p.y-90))
            }
        }
        guard maxRatio <= 1.25, minVX > 0, maxRadius <= 3*R,
              maxGuide <= 700, maxControl <= 700, let tOut=outside.first, let lastOutside=outside.last,
              lastOutside-tOut >= 0.12, lastOutside < end-0.02 else { return nil }
        guard let firstOut=clearances.firstIndex(where:{$0>0}),
              let lastOut=clearances.lastIndex(where:{$0>0}),firstOut>0,lastOut<knots.count-1 else { return nil }
        func crossing(_ lowerIndex:Int,_ upperIndex:Int)->Double {
            let a=knots[lowerIndex],b=knots[upperIndex]
            let lowerIsOutside=clearances[lowerIndex]>0
            var lower=a.time,upper=b.time
            for _ in 0..<24 {
                let middle=(lower+upper)/2
                let s=quintic(a.state,b.state,duration:b.time-a.time,elapsed:middle-a.time)
                let outside=data.union.signedDistance(CGPoint(x:s.p.x,y:s.p.y))>0
                if outside==lowerIsOutside { lower=middle } else { upper=middle }
            }
            return (lower+upper)/2
        }
        let exactOut=crossing(firstOut-1,firstOut),tReturn=crossing(lastOut,lastOut+1)
        var outsideIntervals=0,visibleDuration=0.0
        for index in 1..<clearances.count {
            if clearances[index]>0 {
                if clearances[index-1]<=0 { outsideIntervals += 1 }
                visibleDuration += knots[index].time-knots[index-1].time
            }
        }
        let sweep=zip(angles,angles.dropFirst()).reduce(0.0) { sum,pair in
            sum+abs(atan2(sin(pair.1-pair.0),cos(pair.1-pair.0)))
        }/(2*Double.pi)
        let totalSweep=zip(allAngles,allAngles.dropFirst()).reduce(0.0) { sum,pair in
            sum+abs(atan2(sin(pair.1-pair.0),cos(pair.1-pair.0)))
        }/(2*Double.pi)
        guard sweep < 0.60, totalSweep < 0.60 else { return nil }
        func drift(_ values:[Double]) -> Double { (values.max() ?? 0)-(values.min() ?? 0) }
        func energy(_ s:State)->Double {
            let rho2=(s.p.y-90)*(s.p.y-90)+s.p.z*s.p.z
            return 0.5*norm(s.v)*norm(s.v)+0.5*K*log(epsilon*epsilon+rho2)
        }
        let captureEnergyChange=energy(target)-energy(captureState)
        let captureWorkError=captureEnergyChange-positiveWork-negativeWork
        return Flyby(knots:knots,start:release,freeStart:release+fade,captureStart:captureStart,end:end,
                     tOut:exactOut,tReturn:tReturn,metrics:["speedRatio":maxRatio,"minVX":minVX,
                     "centralHeadRadius":maxRadius,"peakCaptureTotalAcceleration":maxGuide,
                     "peakCaptureControl":maxControl,"capturePositiveWork":positiveWork,
                     "captureNegativeWork":negativeWork,"releasePositiveWork":releasePositiveWork,
                     "releaseNegativeWork":releaseNegativeWork,"freeEnergyDrift":drift(freeEnergy),
                     "captureEnergyChange":captureEnergyChange,"captureWorkBalanceError":captureWorkError,
                     "freeAngularMomentumDrift":drift(freeMomentum),"freeVXDrift":drift(freeVX),"freeTurns":sweep,
                     "totalTurnsIncludingCapture":totalSweep,"maximumVisibleOutsideDistance":maxOutside,
                     "peakVisiblePhase":peakVisiblePhase,
                     "initialZ":route.hiddenZ,"zMinimum":zMinimum,"zMaximum":zMaximum,
                     "zSpan":zMaximum-zMinimum,"elapsed":end-release,
                     "freeElapsed":captureStart-release-fade,"releaseBlendDuration":fade,
                     "captureDuration":captureDuration,
                     "maximumOutsideHeadDistance":maximumOutsideHeadDistance,
                     "visibleOutsideTime":visibleDuration,"outsideIntervals":Double(outsideIntervals),
                     "releaseX":knots[0].state.p.x,"captureX":captureState.p.x,"reunionX":target.p.x,
                     "outsideDuration":visibleDuration,"outsideElapsedSpan":tReturn-exactOut])
    }

    private static func rk4(_ s:State,time:Double,step h:Double,force:(Vector,Double)->Vector)->State {
        let k1p=s.v,k1v=force(s.p,time)
        let k2p=s.v+k1v*h/2,k2v=force(s.p+k1p*h/2,time+h/2)
        let k3p=s.v+k2v*h/2,k3v=force(s.p+k2p*h/2,time+h/2)
        let k4p=s.v+k3v*h,k4v=force(s.p+k3p*h,time+h)
        let pSum: Vector = (k1p+k4p)+(k2p+k3p)*2
        let vSum: Vector = (k1v+k4v)+(k2v+k3v)*2
        let p=s.p+pSum*(h/6)
        let v=s.v+vSum*(h/6)
        return State(p:p,v:v,a:force(p,time+h))
    }
    private static func quintic(_ start:State,_ end:State,duration T:Double,elapsed:Double)->State {
        let u=min(1,max(0,elapsed/T))
        var p=Vector.zero,v=Vector.zero,a=Vector.zero
        for axis in 0..<3 {
            let c0=start.p[axis],c1=start.v[axis]*T,c2=start.a[axis]*(T*T/2)
            let d=end.p[axis]-c0-c1-c2,dv=end.v[axis]*T-c1-2*c2,da=end.a[axis]*T*T-2*c2
            let c3=10*d-4*dv+da/2,c4 = -15*d+7*dv-da,c5=6*d-3*dv+da/2
            p[axis]=c0+u*(c1+u*(c2+u*(c3+u*(c4+u*c5))))
            v[axis]=(c1+u*(2*c2+u*(3*c3+u*(4*c4+u*5*c5))))/T
            a[axis]=(2*c2+u*(6*c3+u*(12*c4+u*20*c5)))/(T*T)
        }
        return State(p:p,v:v,a:a)
    }
    private static func table(_ curve:PipeGeometry)->EnergyFlowPath {
        EnergyFlowPath(points:(0...768).map { curve.point(at:CGFloat($0)/768) })
    }
    private static func ribbon(_ curve:PipeGeometry,from:CGFloat,to:CGFloat)->[CGPoint] {
        func edge(_ sign:CGFloat)->[CGPoint] {
            let boundary=PipeGeometry(start:CGPoint(x:curve.start.x,y:curve.start.y+sign*from/2),
                control1:CGPoint(x:curve.control1.x,y:curve.control1.y+sign*from/2),
                control2:CGPoint(x:curve.control2.x,y:curve.control2.y+sign*to/2),
                end:CGPoint(x:curve.end.x,y:curve.end.y+sign*to/2))
            return (0...96).map { boundary.point(at:CGFloat($0)/96) }
        }
        return edge(-1)+edge(1).reversed()
    }
    private static func smooth(_ value:Double)->Double {
        let u=min(1,max(0,value)); return u*u*u*(10+u*(-15+6*u))
    }
    private static func mod(_ value:Double,_ period:Double)->Double { value-floor(value/period)*period }
    private static func norm(_ v:Vector)->Double { sqrt(v.x*v.x+v.y*v.y+v.z*v.z) }

#if DEBUG
    func audit()->[String:Any] {
        let steps=2_880,window=12.0
        var maximumVisible=0,emptySteps=0,maxNormalSpeedError=0.0,maxPhaseError=0.0
        var maxReunionVelocity=0.0,maxReunionAcceleration=0.0,maxMeasuredSpeedRelativeError=0.0
        var maxDeparturePosition=0.0,maxDepartureVelocity=0.0,maxDepartureAcceleration=0.0
        var maxNormalCenterOutside=0.0
        var records:[[String:Any]]=[]
        for step in 0..<steps {
            let time=window*Double(step)/Double(steps)
            var visible=0
            for p in particles {
                let elapsed=Double(age(p,time:CGFloat(time))!),resolved=clock(p,elapsed),phase=resolved.phase
                let appearance=sample(p,age:CGFloat(elapsed))
                if let flyby=resolved.flyby,phase>flyby.tOut,phase<flyby.tReturn,
                   appearance.tailStrength>0,appearance.isExternal { visible += 1 }
                else {
                    let state=prepared.routes[p.id].state(distance:phase*Double(p.speed),speed:Double(p.speed))
                    maxNormalSpeedError=max(maxNormalSpeedError,abs(Self.norm(state.v)-Double(p.speed)))
                }
            }
            maximumVisible=max(maximumVisible,visible)
            if visible==0 { emptySteps += 1 }
        }
        for p in particles {
            let route=prepared.routes[p.id]
            for index in 1..<500 {
                let time=Double(p.period)*Double(index)/500
                let h=0.0001
                let before=route.state(distance:(time-h)*Double(p.speed),speed:Double(p.speed)).p
                let after=route.state(distance:(time+h)*Double(p.speed),speed:Double(p.speed)).p
                let measured=Self.norm(after-before)/(2*h)
                maxMeasuredSpeedRelativeError=max(maxMeasuredSpeedRelativeError,abs(measured/Double(p.speed)-1))
                let point=route.state(distance:time*Double(p.speed),speed:Double(p.speed)).p
                maxNormalCenterOutside=max(maxNormalCenterOutside,
                    prepared.union.signedDistance(CGPoint(x:point.x,y:point.y)))
            }
            var record:[String:Any]=["id":p.id,"source":p.source,"destination":p.destination,"speed":Double(p.speed),
                "nativeReferenceLength":Double(p.referenceLength),"newRouteLength":Double(p.routeLength),
                "seedDelay":Double(p.delay),"seedRawOffset":Double(p.offset),"seedRadius":Double(p.size),
                "seedSpread":Double(p.spread),"initialDistance":Double(p.delay*p.referenceLength),
                "originalTimeOffset":Double(p.delay*p.referenceLength/p.speed),"newPeriod":Double(p.period),"flyby":p.isComet]
            if let flyby=prepared.flybys[p.id] {
                let startGhost=prepared.routes[p.id].state(distance:flyby.start*Double(p.speed),speed:Double(p.speed))
                let start=flyby.state(at:flyby.start)
                maxDeparturePosition=max(maxDeparturePosition,Self.norm(start.p-startGhost.p))
                maxDepartureVelocity=max(maxDepartureVelocity,Self.norm(start.v-startGhost.v))
                maxDepartureAcceleration=max(maxDepartureAcceleration,Self.norm(start.a-startGhost.a))
                let ghost=prepared.routes[p.id].state(distance:flyby.end*Double(p.speed),speed:Double(p.speed))
                let actual=flyby.state(at:flyby.end)
                let phaseError=Self.norm(actual.p-ghost.p)
                maxPhaseError=max(maxPhaseError,phaseError)
                maxReunionVelocity=max(maxReunionVelocity,Self.norm(actual.v-ghost.v))
                maxReunionAcceleration=max(maxReunionAcceleration,Self.norm(actual.a-ghost.a))
                record["metrics"]=flyby.metrics
                record["reunionPositionError"]=phaseError
                record["reunionVelocityError"]=Self.norm(actual.v-ghost.v)
                record["reunionAccelerationError"]=Self.norm(actual.a-ghost.a)
            }
            records.append(record)
        }
        var enhancedReport:[String:Any]=[:],enhancedPassed=prepared.swirls.isEmpty
        if let id=prepared.swirls.keys.sorted().first,let flyby=prepared.swirls[id] {
            let p=particles[id],route=prepared.routes[id],m=flyby.metrics
            let first=Double(firstEnhancedCycle(p,flyby))*Double(p.period)-Double(p.delay*p.referenceLength/p.speed)
            let pairLength=2*Double(p.period)+m["phaseDebt"]!
            let source=route.state(distance:flyby.start*Double(p.speed),speed:Double(p.speed))
            let target=route.state(distance:m["targetPhase"]!*Double(p.speed),speed:Double(p.speed))
            let actualStart=flyby.state(at:flyby.start),actualEnd=flyby.state(at:flyby.end)
            let positionError=max(Self.norm(actualStart.p-source.p),Self.norm(actualEnd.p-target.p))
            let velocityError=max(Self.norm(actualStart.v-source.v),Self.norm(actualEnd.v-target.v))
            let accelerationError=max(Self.norm(actualStart.a-source.a),Self.norm(actualEnd.a-target.a))
            var nearJoinAcceleration=0.0
            for join in [m["releaseTime"]!,flyby.freeStart,flyby.captureStart,
                         flyby.captureStart+m["captureDuration"]!*0.65] {
                nearJoinAcceleration=max(nearJoinAcceleration,
                    Self.norm(flyby.state(at:join+0.000001).a-flyby.state(at:join-0.000001).a))
            }
            var frames:[[String:Any]]=[]
            var minimumBackFrames=Int.max,minimumFrontFrames=Int.max
            for fps in [30.0,60.0] {
                for offset in [0.0,0.25,0.5,0.75] {
                    var back=0,front=0
                    let startIndex=Int(ceil((first+flyby.start)*fps-offset))
                    let endIndex=Int(floor((first+flyby.end)*fps-offset))
                    for index in startIndex...endIndex {
                        let time=(Double(index)+offset)/fps-first
                        let state=flyby.state(at:time),probe=prepared.union.probe(state.p)
                        if probe.clearance>0,probe.front != nil {
                            let occlusion=prepared.union.headOcclusion(state.p,radius:Double(p.size)*1.08)
                            if occlusion.back { back += 1 };if occlusion.front { front += 1 }
                        }
                    }
                    minimumBackFrames=min(minimumBackFrames,back);minimumFrontFrames=min(minimumFrontFrames,front)
                    frames.append(["fps":Int(fps),"frameOffset":offset,"wholeHeadBehind":back,"frontOverlap":front])
                }
            }
            var ledger:[[String:Double]]=[],maxLedgerError=0.0
            for index in 0..<4 {
                let globalStart=first+Double(index)*pairLength
                let after=globalStart+flyby.end+0.001
                let resolved=clock(p,after+Double(p.delay*p.referenceLength/p.speed))
                let expectedDebt=Double(index+1)*m["phaseDebt"]!
                maxLedgerError=max(maxLedgerError,abs(resolved.debt-expectedDebt),
                    abs(resolved.phase-m["targetPhase"]!-0.001))
                ledger.append(["prepStart":globalStart+flyby.start,"return":globalStart+flyby.end,
                    "persistentDebtAfter":resolved.debt,"periodUntilNextEnhancedEvent":pairLength])
            }
            enhancedPassed=positionError<0.000001 && velocityError<0.000001 && accelerationError<0.00001
                && nearJoinAcceleration<0.1 && maxLedgerError<0.000001 && pairLength>=3
                && minimumBackFrames>=2 && minimumFrontFrames>=2
                && m["prepClearance"]!>=0.15 && m["prepMinVX"]!>0 && m["minVX"]!>0
                && m["centralHeadRadius"]!<=3*prepared.radius && m["maximumOutsideHeadDistance"]!<=2*prepared.radius
                && m["speedRatio"]!<=1.35 && m["peakCaptureControl"]!<=1_400
                && m["freeEnergyDrift"]!<0.02 && m["freeAngularMomentumDrift"]!<0.001
                && m["freeVXDrift"]!<0.00000001 && abs(m["captureWorkBalanceError"]!)<0.5
            enhancedReport=m.mapValues { $0 as Any }
            enhancedReport["passed"]=enhancedPassed
            enhancedReport["continuityPositionError"]=positionError
            enhancedReport["continuityVelocityError"]=velocityError
            enhancedReport["continuityAccelerationError"]=accelerationError
            enhancedReport["accelerationDifferenceAcrossTwoMicroseconds"]=nearJoinAcceleration
            enhancedReport["phaseLedgerError"]=maxLedgerError
            enhancedReport["phaseLedger"]=ledger
            enhancedReport["occlusionFrames"]=frames
            enhancedReport["noUnplannedHeadCenterEntry"]=true // Candidate rejects such entries before acceptance.
            enhancedReport["depthDefinition"]="absolute worldZ / (3R); 3D body masks determine occlusion"
        }
        let passed=enhancedPassed && particles.count==prepared.routes.count && maximumVisible<=3
            && maxNormalSpeedError<0.000001 && maxPhaseError<0.000001
            && maxReunionVelocity<0.000001 && maxReunionAcceleration<0.00001
            && maxDeparturePosition<0.000001 && maxDepartureVelocity<0.000001 && maxDepartureAcceleration<0.00001
            && maxMeasuredSpeedRelativeError<0.001
            && prepared.flybys.values.allSatisfy { f in
                f.metrics["freeEnergyDrift"]!<0.02 && f.metrics["freeAngularMomentumDrift"]!<0.001
                    && f.metrics["freeVXDrift"]!<0.00000001 && f.metrics["minVX"]!>0
                    && f.metrics["speedRatio"]!<=1.25 && f.metrics["centralHeadRadius"]!<=3*prepared.radius
                    && f.metrics["maximumOutsideHeadDistance"]!<=2*prepared.radius
                    && abs(f.metrics["captureWorkBalanceError"]!)<0.5
                    && f.metrics["peakCaptureControl"]!<=700 && f.metrics["totalTurnsIncludingCapture"]!<0.60
            }
        return ["passed":passed,"particleCount":particles.count,"flybyIDs":prepared.flybys.keys.sorted(),
                "maximumSimultaneousVisibleFlybys":maximumVisible,"emptyFraction":Double(emptySteps)/Double(steps),
                "normalSpeedError":maxNormalSpeedError,"reunionPositionError":maxPhaseError,
                "normalMeasuredSpeedRelativeError":maxMeasuredSpeedRelativeError,
                "normalCenterOutsideDistance":maxNormalCenterOutside,
                "reunionVelocityError":maxReunionVelocity,"reunionAccelerationError":maxReunionAcceleration,
                "departurePositionError":maxDeparturePosition,"departureVelocityError":maxDepartureVelocity,
                "departureAccelerationError":maxDepartureAcceleration,
                "heroParticleID":prepared.flybys.keys.sorted().first ?? -1,
                "fieldK":prepared.strength,"fieldEpsilon":prepared.radius,"curvatureReleaseThreshold":280,
                "integrationHz":480,"radiusLimitCentral":3*prepared.radius,"particles":records,
                "rejected":prepared.rejected,"reviewTimes":reviewTimes.mapValues { Double($0) },
                "enhanced3D":enhancedReport,"enhancedFailures":prepared.enhancedFailures,
                "enhancedLast":prepared.enhancedLast]
    }
#endif
}
