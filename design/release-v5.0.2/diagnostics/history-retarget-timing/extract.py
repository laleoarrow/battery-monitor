#!/usr/bin/env python3
"""Keep the frozen History section and verdicts; add diagnostic timing only."""
import hashlib
import json
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:3])
original = source.read_text()
header = original[:original.index('// ---- 1.')]
setup = original[original.index('let item = NSStatusBar.system.statusItem'):original.index('func reducedMotionAnimationsAreSafe')]
loop = original[original.index('func runApplication(until'):original.index('final class StatusClickDispatchProbe')]
body = original[original.index('// ---- 14b. History:'):]
recording = Path(__file__).with_name('recording.swift').read_text()
header = header.replace('var pass = true', 'var pass = true\nvar diagnosticChecks: [[String: Any]] = []')
header = header.replace('    if !ok { pass = false }', '    diagnosticChecks.append(["name": n, "passed": ok])\n    if !ok { pass = false }')

def replace(old, new):
    global body
    assert body.count(old) == 1, (old, body.count(old))
    body = body.replace(old, new)

replace('        updateAxis(appending: 180)', '''        let axisTimeline = fixture.layer!
        diagnosticClock("before-initial-expansion", axisTimeline)
        let axisPausedAt = axisTimeline.convertTime(CACurrentMediaTime(), from: nil)
        if diagnosticFixedClock {
            PopoverStyle.setWithoutAnimation {
                axisTimeline.speed = 0
                axisTimeline.timeOffset = axisPausedAt
            }
            CATransaction.flush()
        }
        let diagnosticExpansionRequestedAt = CACurrentMediaTime()
        updateAxis(appending: 180)''')
replace('''        spin(0.1)
        let midExpansion''', '''        if diagnosticFixedClock {
            PopoverStyle.setWithoutAnimation { axisTimeline.timeOffset = axisPausedAt + 0.1 }
            CATransaction.flush()
        }
        let diagnosticSpinStart = CACurrentMediaTime()
        spin(0.1)
        let diagnosticSpinEnd = CACurrentMediaTime()
        let midExpansion''')
replace('''        let beforeStrokePath = strokeLayer?.presentation()?.path''', '''        let diagnosticDelayStart = CACurrentMediaTime()
        if diagnosticDelay > 0 { spin(diagnosticDelay) }
        let diagnosticDelayEnd = CACurrentMediaTime()
        let diagnosticReadStart = CACurrentMediaTime()
        let diagnosticReadStartLocal = axisTimeline.convertTime(diagnosticReadStart, from: nil)
        let beforeStrokePath = strokeLayer?.presentation()?.path
        let diagnosticReadEnd = CACurrentMediaTime()
        let diagnosticReadEndLocal = axisTimeline.convertTime(diagnosticReadEnd, from: nil)''')
replace('''        updateAxis(appending: 300)
        let retarget''', '''        let diagnosticUpdateStart = CACurrentMediaTime()
        updateAxis(appending: 300)
        let diagnosticUpdateEnd = CACurrentMediaTime()
        let retarget''')
replace('''            check("History 中断变轴直接接续实际描边中的保留采样点",
                  abs(oldAnchor.x - newAnchor.x) < 0.5 && abs(oldAnchor.y - newAnchor.y) < 0.5)''', '''            check("History 中断变轴直接接续实际描边中的保留采样点",
                  abs(oldAnchor.x - newAnchor.x) < 0.5 && abs(oldAnchor.y - newAnchor.y) < 0.5)
            diagnosticRetarget["oldAnchor"] = [oldAnchor.x, oldAnchor.y]
            diagnosticRetarget["newAnchor"] = [newAnchor.x, newAnchor.y]
            diagnosticRetarget["anchorDX"] = abs(oldAnchor.x - newAnchor.x)
            diagnosticRetarget["anchorDY"] = abs(oldAnchor.y - newAnchor.y)''')
verdict = '''            check("History 中断扩轴从可见坐标接续保留采样点",
                  fixture.chartCeilingForTest == 350
                      && abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5
                      && abs(retargetStart.m22 - 350.0 / 250) > 0.5)'''
replace(verdict, verdict + '''
            diagnosticRetarget.merge([
                "before": [before.x, before.y], "after": [after.x, after.y],
                "dx": abs(before.x - after.x), "dy": abs(before.y - after.y),
                "beforeRetargetM22": beforeRetarget.m22, "beforeRetargetM41": beforeRetarget.m41,
                "retargetStartM22": retargetStart.m22, "retargetStartM41": retargetStart.m41,
                "settledRatio": 350.0 / 250, "distanceFromSettledRatio": abs(retargetStart.m22 - 350.0 / 250),
                "newCeiling": fixture.chartCeilingForTest, "oldCeiling": oldCeiling,
                "ceilingPredicate": fixture.chartCeilingForTest == 350,
                "xPredicate": abs(before.x - after.x) < 0.5, "yPredicate": abs(before.y - after.y) < 0.5,
                "midTransitionPredicate": abs(retargetStart.m22 - 350.0 / 250) > 0.5,
                "retainedTimestamp": retainedTimestamp, "retainedWatts": axisValues[0],
                "oldReference": oldReference, "newReference": axisTimes.last!,
                "expansionAnimation": diagnosticAnimation(expansion?.1, owner: expansion?.0),
                "retargetAnimation": diagnosticAnimation(retarget?.1, owner: retarget?.0),
                "expansionRequestedAt": diagnosticExpansionRequestedAt,
                "spinRequestedSeconds": 0.1, "spinActualSeconds": diagnosticSpinEnd - diagnosticSpinStart,
                "extraDelayRequestedSeconds": diagnosticDelay,
                "extraDelayActualSeconds": diagnosticDelayEnd - diagnosticDelayStart,
                "sampleElapsedSinceExpansionRequest": diagnosticReadStart - diagnosticExpansionRequestedAt,
                "beforeStrokeReadStart": diagnosticReadStart, "beforeStrokeReadEnd": diagnosticReadEnd,
                "beforeStrokeLocalStart": diagnosticReadStartLocal, "beforeStrokeLocalEnd": diagnosticReadEndLocal,
                "update300Start": diagnosticUpdateStart, "update300End": diagnosticUpdateEnd,
                "windowVisible": fixtureWindow.isVisible,
                "windowNotOccluded": fixtureWindow.occlusionState.contains(.visible),
                "visibleRect": NSStringFromRect(fixture.visibleRect), "applicationActive": NSApp.isActive,
            ], uniquingKeysWith: { _, new in new })''')
replace('''        check("History 中断后的扩轴完成并自动静止", settleHistoryFixture("retargeted-axis"))''', '''        diagnosticClock("before-resume", axisTimeline)
        if diagnosticFixedClock {
            let axisResumeAt = axisTimeline.timeOffset
            PopoverStyle.setWithoutAnimation {
                axisTimeline.speed = 1
                axisTimeline.timeOffset = 0
                axisTimeline.beginTime = 0
                axisTimeline.beginTime = axisTimeline.convertTime(CACurrentMediaTime(), from: nil) - axisResumeAt
            }
            CATransaction.flush()
        }
        diagnosticClock("after-resume", axisTimeline)
        diagnosticRetarget["retargetAnimationAfterResume"] = diagnosticAnimation(retarget?.0.animation(forKey: "history.stroke"), owner: retarget?.0)
        check("History 中断后的扩轴完成并自动静止", settleHistoryFixture("retargeted-axis"))''')
replace('''if !pass {
    log("\\nSOME_CHECKS_FAILED")''', '''let diagnosticReport: [String: Any] = [
    "schema": 1, "fixedFixtureClock": diagnosticFixedClock, "controlledDelaySeconds": diagnosticDelay,
    "allExtractedAssertionsPassed": pass, "checks": diagnosticChecks,
    "retarget": diagnosticRetarget, "clocks": diagnosticClocks,
    "originalHalfPointTolerancePreserved": true, "originalOneSecondWaitPreserved": true,
    "allHistoryAssertionsRetained": true, "nonHistoryPrefixReplayed": false,
    "screenLocked": screenLocked, "limitations": "Layer-property snapshots are not display-frame or FPS evidence."
]
try JSONSerialization.data(withJSONObject: diagnosticReport, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
if !pass {
    log("\\nSOME_CHECKS_FAILED")''')
text = header + setup + recording + '\n' + loop + body
assert loop in text
destination.write_text(text)
print(json.dumps({'originalHarnessSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
                  'extractedHarnessSHA256': hashlib.sha256(destination.read_bytes()).hexdigest(),
                  'globalRunApplicationUnchanged': True, 'allHistoryAssertionsRetained': True,
                  'earlierNonHistorySuiteReplayed': False, 'originalTolerance': 0.5,
                  'candidatePhaseSeconds': 0.1, 'extraDelaySeconds': 0.2}, indent=2))
