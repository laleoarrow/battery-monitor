#!/usr/bin/env python3
"""Describe every original verdict; expected baseline failure remains failure."""
import json
from pathlib import Path
import sys

p = Path(sys.argv[1])
results = []
for name in ('baseline', 'baseline-delayed', 'fixed', 'fixed-delayed'):
    report = json.loads((p / f'{name}.json').read_text())
    retarget = report['retarget']
    results.append({'case': name, 'exitCode': int((p / f'{name}-exit-code.txt').read_text()),
                    'originalAssertionsPassed': report['allExtractedAssertionsPassed'],
                    'failedAssertions': [c['name'] for c in report['checks'] if not c['passed']],
                    'retarget': retarget, 'clocks': report['clocks']})
delayed = results[1]
same_geometry = delayed['retarget'].get('xPredicate') and delayed['retarget'].get('yPredicate')
guard_failed = delayed['retarget'].get('midTransitionPredicate') is False
expected_assertion = 'History 中断扩轴从可见坐标接续保留采样点'
contrast = (same_geometry and guard_failed
            and delayed['failedAssertions'] == [expected_assertion]
            and all(r['originalAssertionsPassed'] and r['exitCode'] == 0 for r in results[2:]))
print(json.dumps({'schema': 1, 'results': results,
                  'baselineDelayedPreservesOriginalFailure': delayed['exitCode'] == 1,
                  'delayedFailureIsOnlyMidTransitionGuard': bool(same_geometry and guard_failed),
                  'fixedClockBothTimingCasesPass': all(r['originalAssertionsPassed'] for r in results[2:]),
                  'comparisonDemonstrated': bool(contrast),
                  'scope': 'All History assertions retained; preceding non-History suite not replayed.',
                  'ownerZeroMeans': 'Expected contrast was recorded and owned collection completed; baseline failures remain failed.'},
                 ensure_ascii=False, indent=2))
raise SystemExit(0 if contrast else 1)
