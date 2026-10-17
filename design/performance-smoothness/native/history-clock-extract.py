#!/usr/bin/env python3
import hashlib,json,pathlib,sys
source=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2]); text=source.read_text()
header=text[:text.index('// ---- 1.')]
setup=text[text.index('let item = NSStatusBar.system.statusItem'):text.index('func reducedMotionAnimationsAreSafe')]
loop=text[text.index('func runApplication(until'):text.index('final class StatusClickDispatchProbe')]
body=text[text.index('// ---- 14b. History:'):]
diagnostic='''
    func clockProbe(_ name: String) {
        let now = CACurrentMediaTime()
        func diagnosticLayers(_ layer: CALayer?) -> [CALayer] {
            guard let layer else { return [] }
            return [layer] + (layer.sublayers ?? []).flatMap { diagnosticLayers($0) }
                + (layer.mask.map { diagnosticLayers($0) } ?? [])
        }
        for (index, layer) in diagnosticLayers(fixture.layer).enumerated() {
            let keys = layer.animationKeys() ?? []
            guard !keys.isEmpty || layer === fixture.layer else { continue }
            let timing = keys.map { key in
                let a = layer.animation(forKey: key)!
                return "\\(key):begin=\\(a.beginTime),duration=\\(a.duration),removed=\\(a.isRemovedOnCompletion),repeat=\\(a.repeatCount),speed=\\(a.speed),offset=\\(a.timeOffset)"
            }
            let p = layer.presentation()
            log("CLOCK_PROBE \\(name) index=\\(index) name=\\(layer.name ?? "nil") now=\\(now) local=\\(layer.convertTime(now, from:nil)) speed=\\(layer.speed) begin=\\(layer.beginTime) offset=\\(layer.timeOffset) presentationSpeed=\\(p?.speed ?? -1) presentationLocal=\\(p?.convertTime(now, from:nil) ?? -1) presentationBegin=\\(p?.beginTime ?? -1) presentationOffset=\\(p?.timeOffset ?? -1) keys=\\(timing)")
        }
    }
'''
body=body.replace('    func updateFixture(appending: Bool = true) {',diagnostic+'\n    func updateFixture(appending: Bool = true) {',1)
body=body.replace('            return settled\n','''            if context == "matched-tail" && !settled {
                clockProbe("timeout-before-extra-flush")
                CATransaction.flush()
                clockProbe("timeout-after-extra-flush")
                let secondary = runApplication(until: { !fixture.hasChartAnimationForTest }, timeout: 1)
                clockProbe("diagnostic-secondary-wait")
                log("HISTORY_DIAGNOSTIC_POST_FLUSH_SETTLE originalPassed=\\(settled) secondaryKeysAbsent=\\(secondary)")
            }
            return settled
''',1)
needle='''            let tailWaitStarted = CACurrentMediaTime()
            let tailSettled = settleHistoryFixture("matched-tail")'''
replacement='''            clockProbe("resumed-before-explicit-commit")
            if ProcessInfo.processInfo.environment["WATTSON_HISTORY_PROBE_FLUSH_AFTER_RESUME"] == "1" {
                CATransaction.flush()
                clockProbe("resumed-after-explicit-commit")
            }
            let tailWaitStarted = CACurrentMediaTime()
            let tailSettled = settleHistoryFixture("matched-tail")
            clockProbe("after-original-one-second-settle")'''
assert needle in body
body=body.replace(needle,replacement,1)
output.write_text(header+setup+loop+body)
print(json.dumps({'originalSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'extractedHarnessSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'section':'14b','assertionCriteriaUnchanged':True,'timeoutUnchanged':True,'diagnosticExtraWaitCannotChangeOriginalPassFlag':True}))
