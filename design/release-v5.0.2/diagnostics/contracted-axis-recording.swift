// Concatenated into an extracted test harness, never into the app target.
var diagnosticOnLoopStop: ((Bool) -> Void)?
var diagnosticRecords: [[String: Any]] = []
var diagnosticOriginalPassed: Bool?

func diagnosticLayers(_ layer: CALayer?) -> [CALayer] {
    guard let layer else { return [] }
    return [layer] + (layer.sublayers ?? []).flatMap { diagnosticLayers($0) }
        + (layer.mask.map { diagnosticLayers($0) } ?? [])
}

func diagnosticPath(_ path: CGPath?) -> (types: [Int], points: [CGPoint])? {
    guard let path else { return nil }
    var types: [Int] = [], points: [CGPoint] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        types.append(Int(element.type.rawValue))
        let count: Int
        switch element.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        default: count = 0
        }
        points += (0..<count).map { element.points[$0] }
    }
    return (types, points)
}

func recordContractedAxis(_ label: String, view: HistoryView, started: CFTimeInterval,
                          originalPassed: Bool) {
    let now = CACurrentMediaTime()
    let window = view.window
    let records: [[String: Any]] = diagnosticLayers(view.layer).enumerated().map { index, layer in
        let shown = layer.presentation()
        let keys = layer.animationKeys() ?? []
        let modelPath = diagnosticPath((layer as? CAShapeLayer)?.path)
        let shownPath = diagnosticPath((shown as? CAShapeLayer)?.path)
        let sameTopology = modelPath != nil && shownPath != nil
            && modelPath!.types == shownPath!.types && modelPath!.points.count == shownPath!.points.count
        let delta = sameTopology ? zip(modelPath!.points, shownPath!.points).map { model, presented in
            hypot(Double(model.x - presented.x), Double(model.y - presented.y))
        }.max() : nil
        let isHead = abs(layer.bounds.width - 5.2) < 0.000_001
            && abs(layer.bounds.height - 5.2) < 0.000_001 && layer.cornerRadius == 2.6
        return [
            "index": index, "name": layer.name ?? "unnamed", "hasPresentation": shown != nil,
            "isHead": isHead, "keys": keys,
            "modelPathTypes": modelPath?.types as Any? ?? NSNull(),
            "modelPathPoints": modelPath?.points.map { [$0.x, $0.y] } as Any? ?? NSNull(),
            "presentationPathPoints": shownPath?.points.map { [$0.x, $0.y] } as Any? ?? NSNull(),
            "samePathTopology": sameTopology,
            "maximumPathTargetErrorPoints": delta as Any? ?? NSNull(),
            "modelPosition": [layer.position.x, layer.position.y],
            "presentationPosition": shown.map { [$0.position.x, $0.position.y] } as Any? ?? NSNull(),
            "headTargetErrorPoints": (isHead ? shown.map {
                hypot(Double($0.position.x - layer.position.x), Double($0.position.y - layer.position.y))
            } : nil) as Any? ?? NSNull(),
            "localTime": layer.convertTime(now, from: nil), "speed": layer.speed,
            "beginTime": layer.beginTime, "timeOffset": layer.timeOffset,
            "animations": keys.compactMap { key -> [String: Any]? in
                guard let animation = layer.animation(forKey: key) else { return nil }
                return ["key": key, "beginTime": animation.beginTime, "duration": animation.duration,
                        "removedOnCompletion": animation.isRemovedOnCompletion,
                        "repeatCount": animation.repeatCount]
            },
        ]
    }
    diagnosticRecords.append([
        "observation": label, "elapsedSinceOriginalWaitStart": now - started,
        "originalDeadlineSeconds": 1, "originalAssertionPassed": originalPassed,
        "hasChartAnimation": view.hasChartAnimationForTest,
        "chartCeiling": view.chartCeilingForTest,
        "windowVisible": window?.isVisible ?? false,
        "windowOcclusionState": window?.occlusionState.rawValue ?? 0,
        "windowNotOccluded": window?.occlusionState.contains(.visible) ?? false,
        "windowOnActiveSpace": window?.isOnActiveSpace ?? false,
        "windowMiniaturized": window?.isMiniaturized ?? false,
        "visibleRect": NSStringFromRect(view.visibleRect),
        "hiddenOrHiddenAncestor": view.isHiddenOrHasHiddenAncestor,
        "screenLocked": (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Int == 1,
        "applicationActive": NSApp.isActive,
        "layers": records,
    ])
    let allKeys = records.flatMap { $0["keys"] as? [String] ?? [] }
    log("CONTRACTED_AXIS_OBSERVATION \(label) originalPassed=\(originalPassed) elapsed=\(now - started) keys=\(allKeys)")
}
