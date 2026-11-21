import CoreGraphics

/// Morphs the same graph in place. A battery changing columns retracts its old
/// directional leg, travels below the junction, then opens its new leg.
struct PowerFlowMorph {
    static let nodeDepartureEnd: CGFloat = 0.35
    static let batteryDepartureEnd: CGFloat = 0.20
    static let batteryTravelEnd: CGFloat = 0.60
    static let arrivalEnd: CGFloat = 0.85

    static func scene(from: PowerFlowScene, to: PowerFlowScene, progress: CGFloat) -> PowerFlowScene {
        guard progress.isFinite, progress > 0 else { return from }
        guard progress < 1 else { return to }
        let eased = ease(progress)
        let batteryMoves = abs(from.nodes[1].x - to.nodes[1].x) > 0.001
        let batteryMovesLeft = to.nodes[1].x < from.nodes[1].x
        let newAdapter = !from.nodeVisible[0] && to.nodeVisible[0]
        let newUSB = !from.nodeVisible[3] && to.nodeVisible[3]
        var result = to
        result.nodes = zip(from.nodes, to.nodes).map { blend($0, $1, eased) }
        result.nodeVisible = zip(from.nodeVisible, to.nodeVisible).map { $0 || $1 }
        result.jointStart = blend(from.jointStart, to.jointStart, eased)
        result.jointEnd = blend(from.jointEnd, to.jointEnd, eased)
        result.edges = zip(from.edges, to.edges).map { start, end in
            FlowEdgePose(geometry: blend(start.geometry, end.geometry, eased),
                startWidth: blend(start.startWidth, end.startWidth, eased),
                endWidth: blend(start.endWidth, end.endWidth, eased),
                verticalTaper: blend(start.verticalTaper, end.verticalTaper, eased))
        }

        if batteryMoves {
            let travel = ease((progress - batteryDepartureEnd) / (batteryTravelEnd - batteryDepartureEnd))
            var battery = blend(from.nodes[1], to.nodes[1], travel)
            // The 92pt labels must clear each column before the lower-lane
            // arc begins; otherwise the Battery label sweeps over USB.
            let entrance = batteryMovesLeft ? min(from.nodes[1].x, 194) : max(from.nodes[1].x, 134)
            let exit = batteryMovesLeft ? max(to.nodes[1].x, 134) : min(to.nodes[1].x, 194)
            if batteryMovesLeft ? entrance > exit : entrance < exit {
                let arc = min(1, max(0, (battery.x - entrance) / (exit - entrance)))
                battery.y = arc <= 0.5
                    ? blend(from.nodes[1].y, 151, ease(arc * 2))
                    : blend(151, to.nodes[1].y, ease((arc - 0.5) * 2))
            }
            result.nodes[1] = battery

            let rightProgress = batteryMovesLeft ? ease((progress - 0.5) / 0.35) : ease(progress / 0.3)
            for index in [2, 3] { result.nodes[index] = blend(from.nodes[index], to.nodes[index], rightProgress) }
            let adapterProgress = batteryMovesLeft ? ease(progress / 0.3) : ease((progress - 0.5) / 0.35)
            result.nodes[0] = blend(from.nodes[0], to.nodes[0], adapterProgress)
            let departing: FlowEdgeRole = batteryMovesLeft ? .batteryCharge : .batteryInput
            let arriving: FlowEdgeRole = batteryMovesLeft ? .batteryInput : .batteryCharge
            for role in [departing, arriving] {
                let index = role.rawValue
                let departure = 1 - ease(progress / batteryDepartureEnd)
                let arrival = role == arriving ? ease((progress - batteryTravelEnd) / (arrivalEnd - batteryTravelEnd)) : 0
                result.edges[index].startWidth = from.edges[index].startWidth * departure
                    + to.edges[index].startWidth * arrival
                result.edges[index].endWidth = from.edges[index].endWidth * departure
                    + to.edges[index].endWidth * arrival
            }
        }

        // Newly revealed nodes can take their empty destination immediately.
        // Their persistent neighbours finish moving before the reveal starts.
        if newUSB {
            result.nodes[3] = to.nodes[3]
            let rightProgress = batteryMoves && !batteryMovesLeft ? ease(progress / 0.3) : ease(progress / 0.6)
            result.nodes[2] = blend(from.nodes[2], to.nodes[2], rightProgress)
        }
        if !batteryMoves && (newUSB || newAdapter) {
            result.nodes[1] = blend(from.nodes[1], to.nodes[1], ease(progress / 0.6))
        }
        // A folded source sits on the joint. Letting its node lag vertically
        // creates a narrow upright pipe through the caption below the icon.
        let adapterSpan = max(0, result.jointStart.x - result.nodes[0].x - 13)
        result.nodes[0].y = result.jointStart.y
            + min(adapterSpan, max(-adapterSpan, result.nodes[0].y - result.jointStart.y))

        // Staging one branch changes the cross section of the shared junction.
        // Pack both sides against the same width so no overlapping ribbons or
        // gaps appear while the battery changes its direction of power flow.
        let inputs = [FlowEdgeRole.adapterInput, .batteryInput]
        let outputs = [FlowEdgeRole.systemOutput, .batteryCharge, .deviceOutput]
        let inputTotal = inputs.reduce(CGFloat(0)) { $0 + result.edges[$1.rawValue].endWidth }
        let outputTotal = outputs.reduce(CGFloat(0)) { $0 + result.edges[$1.rawValue].startWidth }
        let width = min(inputTotal, outputTotal)
        var boundary = result.jointStart.y - width / 2
        for (role, nodeIndex) in zip(inputs, [0, 1]) {
            let index = role.rawValue
            result.edges[index].endWidth *= inputTotal > 0 ? width / inputTotal : 0
            let halfWidth = result.edges[index].endWidth / 2
            let start = CGPoint(x: result.nodes[nodeIndex].x + 13, y: result.nodes[nodeIndex].y)
            let end = CGPoint(x: result.jointStart.x, y: boundary + halfWidth)
            result.edges[index].geometry = anchored(result.edges[index].geometry, start: start, end: end)
            boundary += result.edges[index].endWidth
        }
        boundary = result.jointEnd.y - width / 2
        for (role, nodeIndex) in zip(outputs, [2, 1, 3]) {
            let index = role.rawValue
            result.edges[index].startWidth *= outputTotal > 0 ? width / outputTotal : 0
            let halfWidth = result.edges[index].startWidth / 2
            let start = CGPoint(x: result.jointEnd.x, y: boundary + halfWidth)
            let end = CGPoint(x: result.nodes[nodeIndex].x - 13, y: result.nodes[nodeIndex].y)
            result.edges[index].geometry = anchored(result.edges[index].geometry, start: start, end: end)
            boundary += result.edges[index].startWidth
        }
        let common = FlowEdgeRole.common.rawValue
        result.edges[common].geometry = anchored(result.edges[common].geometry,
            start: result.jointStart, end: result.jointEnd)
        result.edges[common].startWidth = width
        result.edges[common].endWidth = width
        result.mixedCommonWidth = result.jointStart == result.jointEnd ? 0 : width
        let adapterDashStart = CGPoint(x: result.nodes[0].x + 18.5, y: result.nodes[0].y)
        result.idleBattery = idle(from.idleBattery, to.idleBattery, eased,
                                  start: adapterDashStart, node: result.nodes[1])
        if batteryMoves {
            if (to.idleBattery == nil && progress >= batteryDepartureEnd)
                || (from.idleBattery == nil && progress <= batteryTravelEnd) { result.idleBattery = nil }
        }
        if from.idleDevice != nil || to.idleDevice != nil {
            // The waiting hint follows the same packed outlet and staged
            // endpoint as the USB power branch throughout the transition.
            result.idleDevice = result.deviceConnectionGeometry()
        }
        return result
    }

    private static func ease(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }

    private static func blend(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private static func blend(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: blend(a.x, b.x, t), y: blend(a.y, b.y, t))
    }

    private static func blend(_ a: PipeGeometry, _ b: PipeGeometry, _ t: CGFloat) -> PipeGeometry {
        PipeGeometry(start: blend(a.start, b.start, t), control1: blend(a.control1, b.control1, t),
                     control2: blend(a.control2, b.control2, t), end: blend(a.end, b.end, t))
    }

    private static func anchored(_ geometry: PipeGeometry, start: CGPoint, end: CGPoint) -> PipeGeometry {
        let distance = end.x - start.x
        let direction: CGFloat = distance < 0 ? -1 : 1
        let limit = abs(distance) / 2
        let first = min(limit, abs(geometry.control1.x - geometry.start.x))
        let second = min(limit, abs(geometry.end.x - geometry.control2.x))
        return PipeGeometry(start: start,
            control1: CGPoint(x: start.x + direction * first, y: start.y),
            control2: CGPoint(x: end.x - direction * second, y: end.y), end: end)
    }

    private static func idle(_ from: PipeGeometry?, _ to: PipeGeometry?, _ t: CGFloat,
                             start: CGPoint, node: CGPoint) -> PipeGeometry? {
        guard let old = from ?? to, let target = to ?? from else { return nil }
        let geometry = blend(old, target, t)
        return anchored(geometry, start: start, end: CGPoint(x: node.x - 18.5, y: node.y))
    }
}
