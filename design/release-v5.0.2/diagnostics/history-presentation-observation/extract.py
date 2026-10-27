"""Reuse the original extracted History prefix; alter only its settling wait."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import runpy
import sys

sys.dont_write_bytecode = True
source, destination = map(Path, sys.argv[1:3])
strategy = sys.argv[3]
assert strategy in ("baseline", "candidate")
original = source.read_text()
extractor = Path(__file__).parents[1] / "extract-contracted-axis.py"
arguments = sys.argv
with contextlib.redirect_stdout(io.StringIO()):
    sys.argv = [str(extractor), str(source), str(destination)]
    runpy.run_path(str(extractor), run_name="__main__")
sys.argv = arguments
text = destination.read_text()
# Restore the exact original global NSApplication runner, including no callback.
text = text.replace("            diagnosticOnLoopStop?(satisfied)\n", "")
original_loop = original[original.index("func runApplication(until"):original.index("final class StatusClickDispatchProbe")]
assert original_loop in text
before = '''            if context == "contracted-axis" {
                diagnosticOnLoopStop = { originalPassed in
                    recordContractedAxis("original-poll-terminal-before-stop", view: view,
                                         started: started, originalPassed: originalPassed)
                }
            }
'''
after = '''            if context == "contracted-axis" {
                diagnosticOnLoopStop = nil
                diagnosticOriginalPassed = settled
                recordContractedAxis("after-original-loop-return-before-flush", view: view,
                                     started: started, originalPassed: settled)
                CATransaction.flush()
                recordContractedAxis("after-diagnostic-flush", view: view,
                                     started: started, originalPassed: settled)
            }'''
assert text.count(before) == text.count(after) == 1
text = text.replace(before, "").replace(after, "")
wait = "            let settled = runApplication(until: { !view.hasChartAnimationForTest }, timeout: 1)"
candidate = '''            let settled = runApplication(until: {
                for layer in diagnosticLayers(view.layer) {
                    if let presented = layer.presentation() {
                        _ = presented.position
                        if let shape = presented as? CAShapeLayer { _ = shape.path }
                    }
                }
                CATransaction.flush()
                return !view.hasChartAnimationForTest
            }, timeout: 1)'''
assert text.count(wait) == 1
selected = candidate if strategy == "candidate" else wait
text = text.replace(wait, selected + '''
            if context == "contracted-axis" {
                diagnosticDecisionElapsed = CACurrentMediaTime() - started
                diagnosticOriginalPassed = settled
                recordContractedAxis("verdict-before-any-later-observation", view: view,
                                     started: started, originalPassed: settled)
            }
''')
start = '''        func settleHistoryFixture(_ context: String, view: HistoryView = fixture) -> Bool {
            let started = CACurrentMediaTime()'''
assert text.count(start) == 1
text = text.replace(start, start.replace("            let started", '''            if context == "contracted-axis" { installDiagnosticFault(view: view) }
            let started'''))
fixture_ready = "    fixture.setAnimationsEnabled(true)\n"
assert text.count(fixture_ready) == 1
text = text.replace(fixture_ready, fixture_ready + "    requireDiagnosticVisibility(fixtureWindow)\n")
recording = (Path(__file__).with_name("faults.swift")).read_text()
text = text.replace("var diagnosticOnLoopStop: ((Bool) -> Void)?", recording)
# Infinity is valid CAAnimation input but cannot be a JSON number.
text = text.replace('"repeatCount": animation.repeatCount', '"repeatCount": String(describing: animation.repeatCount)')
text = text.replace('"schema": 1, "method":', '''"schema": 1, "waitingStrategy": "''' + strategy + '''",
    "fault": diagnosticFault, "faultInjected": diagnosticFaultInjected,
    "visibilityBeforeHistoryInputs": diagnosticVisibility,
    "decisionElapsedSeconds": diagnosticDecisionElapsed as Any? ?? NSNull(),
    "globalRunApplicationUnchanged": true, "postDeadlineFlushAffectsVerdict": false,
    "method":''')
text = text.replace("Post-loop/flush observations do not change the original verdict.",
                    "Diagnostic geometry is collected only after the fixed verdict; no post-verdict flush is performed.")
assert original_loop in text
destination.write_text(text)
print(json.dumps({"strategy": strategy, "originalHarnessSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
                  "extractedHarnessSHA256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                  "globalRunApplicationUnchanged": True, "originalAssertionsRetained": True,
                  "originalDeadlineSeconds": 1, "productionSourcesUnchanged": True,
                  "sharedVisibilityPreconditionBeforeHistoryInputs": True}, indent=2))
