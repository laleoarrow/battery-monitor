#!/usr/bin/env python3
"""Preserve the original History fixture through its contracted-axis assertion."""
import hashlib
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[1:3])
text = source.read_text()
header = text[:text.index('// ---- 1.')]
setup = text[text.index('let item = NSStatusBar.system.statusItem'):text.index('func reducedMotionAnimationsAreSafe')]
loop = text[text.index('func runApplication(until'):text.index('final class StatusClickDispatchProbe')]
body = text[text.index('// ---- 14b. History:'):]
last = '        check("History 缩轴结束后原生图层自行静止", settleHistoryFixture("contracted-axis"))'
body = body[:body.index(last) + len(last)] + '\n    }\n}\n'
terminal = '            stopApplicationLoop()\n'
assert loop.count(terminal) == 1
loop = loop.replace(terminal, '            diagnosticOnLoopStop?(satisfied)\n' + terminal)
wait = '            let settled = runApplication(until: { !view.hasChartAnimationForTest }, timeout: 1)'
assert body.count(wait) == 1
body = body.replace(wait, '''            if context == "contracted-axis" {
                diagnosticOnLoopStop = { originalPassed in
                    recordContractedAxis("original-poll-terminal-before-stop", view: view,
                                         started: started, originalPassed: originalPassed)
                }
            }
''' + wait + '''
            if context == "contracted-axis" {
                diagnosticOnLoopStop = nil
                diagnosticOriginalPassed = settled
                recordContractedAxis("after-original-loop-return-before-flush", view: view,
                                     started: started, originalPassed: settled)
                CATransaction.flush()
                recordContractedAxis("after-diagnostic-flush", view: view,
                                     started: started, originalPassed: settled)
            }''')
footer = '''
NSStatusBar.system.removeStatusItem(item)
Settings.resetTestConfiguration()
settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
let report: [String: Any] = [
    "schema": 1, "method": "Extracted original History section through contracted-axis; preceding fixture lifecycle and all input updates retained.",
    "originalOneSecondDeadlineRetained": true, "originalContractedAxisPassed": diagnosticOriginalPassed as Any? ?? NSNull(),
    "allExtractedAssertionsPassed": pass, "animationKeysForciblyRemovedByDiagnostic": false,
    "fixtureClockPauseReached": false, "records": diagnosticRecords,
    "limitations": "Earlier non-History suite state is not replayed. Geometry observations are not display-frame or FPS measurements. Post-loop/flush observations do not change the original verdict."
]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
exit(diagnosticOriginalPassed == nil ? 2 : pass ? 0 : 1)
'''
recording = pathlib.Path(__file__).with_name('contracted-axis-recording.swift').read_text()
destination.write_text(header + setup + recording + '\n' + loop + body + footer)
print(json.dumps({
    'originalHarnessSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'extractedHarnessSHA256': hashlib.sha256(destination.read_bytes()).hexdigest(),
    'lastRetainedAssertion': last.strip(), 'originalDeadlineSeconds': 1,
    'diagnosticFlushOnlyAfterOriginalVerdict': True,
    'precedingHistoryLifecycleRetained': True, 'earlierNonHistorySuiteReplayed': False,
}, indent=2))
