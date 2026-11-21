import CoreGraphics

/// These identities do not change when a source becomes a sink or a branch is
/// folded into a node. Zero-length legs retain their joint widths, but are not
/// painted and do not host travelling particles.
enum FlowEdgeRole: Int, CaseIterable {
    case adapterInput, batteryInput, systemOutput, batteryCharge, deviceOutput, common
}

struct FlowEdgePose: Equatable {
    var geometry: PipeGeometry
    var startWidth: CGFloat
    var endWidth: CGFloat
    /// Ordinary pipes have normal-width strokes; the mixed neck uses vertical
    /// ribbon edges. Intermediate values allow the renderer to blend contours.
    var verticalTaper: CGFloat

    var isCollapsed: Bool {
        geometry.start == geometry.end && geometry.control1 == geometry.start
            && geometry.control2 == geometry.start
    }
}

/// A resting graph with stable adapter/battery/system/device node identities.
/// Folding the neck into the source or sink reproduces the existing full cubic
/// pipes without substituting a different node or changing the section height.
struct PowerFlowScene {
    var layout: FlowLayout
    var nodes: [CGPoint]
    var nodeVisible: [Bool]
    var nodeCompact: [Bool]
    var edges: [FlowEdgePose]
    var idleBattery: PipeGeometry?
    var idleDevice: PipeGeometry?
    var jointStart: CGPoint
    var jointEnd: CGPoint
    var mixedCommonWidth: CGFloat

    static func make(snapshot: PowerSnapshot) -> Self {
        let measuredOutput = snapshot.coherentDeviceOutputW.flatMap { $0 > 0 ? $0 : nil }
        let showsDevice = measuredOutput != nil || snapshot.hasConnectedUSBDevice
        let pendingUSB = showsDevice && measuredOutput == nil
        let layout: FlowLayout
        switch snapshot.state {
        case .onBattery: layout = showsDevice ? .batteryOutputSplit : .batteryLed
        case .mixedSupply: layout = showsDevice ? .mixedOutputSplit : .batteryLed
        case .charging, .pluggedIdle: layout = showsDevice ? .adapterOutputSplit : .adapterLed
        }

        let nodes: [CGPoint]
        switch layout {
        case .adapterLed:
            nodes = [point(40, 90), point(288, 129), point(288, 51), point(288, 129)]
        case .adapterOutputSplit:
            nodes = [point(40, 96), point(288, 96), point(288, 26), point(288, 166)]
        case .batteryLed:
            nodes = [point(40, 51), point(40, 129), point(288, 90), point(288, 129)]
        case .batteryOutputSplit:
            nodes = [point(40, 51), point(40, 90), point(288, 51), point(288, 129)]
        case .mixedOutputSplit:
            nodes = [point(40, 51), point(40, 129), point(288, 51), point(288, 129)]
        }
        let center: CGFloat = layout == .adapterOutputSplit ? 96 : 90
        let jointX: CGFloat = layout == .batteryLed ? 275 : layout == .mixedOutputSplit ? 146 : 53
        let jointStart = point(jointX, center)
        let jointEnd = point(layout == .mixedOutputSplit ? 182 : jointX, center)
        var scene = Self(layout: layout, nodes: nodes,
            nodeVisible: [layout != .batteryOutputSplit, true, true, showsDevice],
            nodeCompact: [false, layout == .adapterOutputSplit,
                          layout == .adapterOutputSplit, layout == .adapterOutputSplit],
            edges: Array(repeating: FlowEdgePose(geometry: collapsed(at: jointStart),
                startWidth: 0, endWidth: 0, verticalTaper: 0), count: FlowEdgeRole.allCases.count),
            idleBattery: nil, idleDevice: nil,
            jointStart: jointStart, jointEnd: jointEnd, mixedCommonWidth: 0)

        let inputWidths: [CGFloat]
        let outputWidths: [CGFloat]
        let inputJointWidths: [CGFloat]
        let outputJointWidths: [CGFloat]
        let jointWidth: CGFloat
        switch layout {
        case .adapterLed, .adapterOutputSplit:
            let charging = snapshot.batteryW > PowerSnapshot.epsilon
            let output = measuredOutput ?? 0
            outputWidths = scaledWidths([snapshot.systemW - output,
                charging ? snapshot.batteryW : 0, output], maximum: showsDevice ? 30 : 36)
            jointWidth = outputWidths.reduce(0, +)
            inputWidths = [jointWidth, 0]
            inputJointWidths = inputWidths
            outputJointWidths = outputWidths
            if !charging { scene.idleBattery = idle(from: center, to: nodes[1].y) }
        case .batteryOutputSplit:
            let output = measuredOutput ?? 0
            let loads = snapshot.batteryW < -PowerSnapshot.epsilon
                ? [snapshot.systemW - output, 0, output] : [0, 0, 0]
            outputWidths = scaledWidths(loads)
            jointWidth = outputWidths.reduce(0, +)
            inputWidths = [0, jointWidth]
            inputJointWidths = inputWidths
            outputJointWidths = outputWidths
        case .batteryLed:
            let adapterActive = snapshot.state != .onBattery && snapshot.adapterW > 0
            inputWidths = scaledWidths([adapterActive ? snapshot.adapterW : 0, abs(snapshot.batteryW)])
            jointWidth = inputWidths.reduce(0, +)
            outputWidths = [jointWidth, 0, 0]
            inputJointWidths = inputWidths
            outputJointWidths = outputWidths
        case .mixedOutputSplit:
            let output = measuredOutput ?? 0
            let inputs = [snapshot.adapterW, -snapshot.batteryW]
            let outputs = [snapshot.systemW - output, 0, output]
            let branchWidth = min(36, min(inputs.map(thickness).reduce(0, +),
                                          outputs.map(thickness).reduce(0, +)))
            let twoInTwoOut = inputs.allSatisfy { $0 > 0 }
                && outputs[0] > 0 && outputs[2] > 0
            jointWidth = branchWidth * (twoInTwoOut ? 0.68 : 1)
            inputWidths = scaledWidths(inputs, maximum: branchWidth)
            outputWidths = scaledWidths(outputs, maximum: branchWidth)
            inputJointWidths = scaledWidths(inputs, maximum: jointWidth)
            outputJointWidths = scaledWidths(outputs, maximum: jointWidth)
            scene.mixedCommonWidth = jointWidth
        }

        let inputCenters = packedCenters(inputJointWidths, center: center)
        let outputCenters = packedCenters(outputJointWidths, center: center)
        let verticalTaper: CGFloat = layout == .mixedOutputSplit ? 1 : 0
        for index in 0..<2 {
            let source = point(nodes[index].x + 13, nodes[index].y)
            let target = point(jointStart.x, inputCenters[index])
            let geometry: PipeGeometry
            if source == target {
                geometry = collapsed(at: source)
            } else if layout == .batteryLed {
                geometry = fullPipe(from: source.y, to: target.y)
            } else {
                geometry = leg(from: source, to: target)
            }
            scene.edges[index] = FlowEdgePose(geometry: geometry,
                startWidth: inputWidths[index], endWidth: inputJointWidths[index],
                verticalTaper: verticalTaper)
        }
        for (index, nodeIndex) in [2, 1, 3].enumerated() {
            let source = point(jointEnd.x, outputCenters[index])
            let target = point(nodes[nodeIndex].x - 13, nodes[nodeIndex].y)
            let geometry: PipeGeometry
            if source == target {
                geometry = collapsed(at: source)
            } else if jointEnd.x == 53 && target.x == 275 {
                geometry = fullPipe(from: source.y, to: target.y)
            } else {
                geometry = leg(from: source, to: target)
            }
            scene.edges[FlowEdgeRole.systemOutput.rawValue + index] = FlowEdgePose(
                geometry: geometry, startWidth: outputJointWidths[index],
                endWidth: outputWidths[index], verticalTaper: verticalTaper)
        }
        scene.edges[FlowEdgeRole.common.rawValue] = FlowEdgePose(
            geometry: jointStart == jointEnd ? collapsed(at: jointStart)
                : PipeGeometry(start: jointStart, control1: point(158, 90),
                               control2: point(170, 90), end: jointEnd),
            startWidth: jointWidth, endWidth: jointWidth, verticalTaper: verticalTaper)
        if pendingUSB {
            // Reserve the USB branch at its own packed outlet. It shares the
            // source with the powered bars, rather than leaving a bar midway.
            scene.idleDevice = scene.deviceConnectionGeometry()
        }
        return scene
    }

    func deviceConnectionGeometry() -> PipeGeometry {
        var connection = edges[FlowEdgeRole.deviceOutput.rawValue].geometry
        connection.start.x = max(58.5, connection.start.x)
        connection.end.x = nodes[3].x - 18.5
        return connection
    }

    private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func thickness(_ watts: Double) -> CGFloat {
        watts.isFinite && watts > 0 ? VisualEncoding.thickness(watts) : 0
    }

    private static func scaledWidths(_ watts: [Double], maximum: CGFloat = 36) -> [CGFloat] {
        let widths = watts.map(thickness)
        let total = widths.reduce(0, +)
        let scale = total > maximum ? maximum / total : 1
        return widths.map { $0 * scale }
    }

    private static func packedCenters(_ widths: [CGFloat], center: CGFloat) -> [CGFloat] {
        var edge = center - widths.reduce(0, +) / 2
        return widths.map { width in
            let result = edge + width / 2
            edge += width
            return result
        }
    }

    private static func collapsed(at point: CGPoint) -> PipeGeometry {
        PipeGeometry(start: point, control1: point, control2: point, end: point)
    }

    private static func fullPipe(from startY: CGFloat, to endY: CGFloat) -> PipeGeometry {
        PipeGeometry(start: point(53, startY), control1: point(138, startY),
                     control2: point(190, endY), end: point(275, endY))
    }

    private static func leg(from source: CGPoint, to target: CGPoint) -> PipeGeometry {
        let inset = (target.x - source.x) * (35.5 / 93)
        return PipeGeometry(start: source, control1: point(source.x + inset, source.y),
                            control2: point(target.x - inset, target.y), end: target)
    }

    private static func idle(from startY: CGFloat, to endY: CGFloat) -> PipeGeometry {
        var geometry = fullPipe(from: startY, to: endY)
        geometry.start.x = 58.5
        geometry.end.x = 269.5
        return geometry
    }
}
