#!/usr/bin/env python3
import hashlib
import gzip
import json
import pathlib
import statistics
import sys

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else pathlib.Path(__file__).resolve().parent
results = root / 'guest-results'
raw = ((results / 'benchmark.jsonl').read_bytes() if results.exists()
       else gzip.decompress((root / 'benchmark-raw.jsonl.gz').read_bytes()))
rows = [json.loads(line) for line in raw.decode().splitlines()]
names = ['process_identical_input', 'process_changed_input',
         'settings_11_icons_identical_appearance', 'settings_11_icons_changed_contrast']
assert len(rows) == 48, len(rows)
assert [row['revision'] for row in rows[::4]] == ['baseline', 'candidate', 'candidate', 'baseline'] * 3
measurements = {}
for name in names:
    paired = {}
    for label in ('baseline', 'candidate'):
        selected = [row for row in rows if row['case'] == name and row['revision'] == label]
        assert len(selected) == 6
        assert all(row['iterations'] == 1200 and len(row['samples_us']) == 1200 for row in selected)
        paired[label] = {
            'runs': len(selected), 'iterationsPerRun': 1200,
            'medianOfRunMediansMicroseconds': statistics.median(row['median_us'] for row in selected),
            'medianOfRunP95Microseconds': statistics.median(row['p95_us'] for row in selected),
            'rawRunMediansMicroseconds': [row['median_us'] for row in selected],
            'rawRunP95Microseconds': [row['p95_us'] for row in selected],
        }
    old = paired['baseline']['medianOfRunMediansMicroseconds']
    new = paired['candidate']['medianOfRunMediansMicroseconds']
    paired['reductionPercent'] = (old - new) / old * 100
    paired['candidateToBaselineRatio'] = new / old
    measurements[name] = paired
if results.exists():
    source_old = json.loads((root / 'source-baseline-manifest.json').read_text())
    source_new = json.loads((root / 'source-candidate-manifest.json').read_text())
    changed = sorted(name for name in set(source_old) | set(source_new) if source_old.get(name) != source_new.get(name))
    source = json.loads((root / 'freeze-ready.json').read_text())
    for label in ('baseline', 'candidate'):
        source[f'{label}ArchiveSHA256'] = (root / f'source-{label}.sha256').read_text().strip()
    system = (results / 'system.txt').read_text()
else:
    metadata = json.loads((root / 'source-and-harness-digests.json').read_text())
    changed, source, system = metadata['changedFilesFromBaseline'], metadata['freezeRecord'], metadata['system']
report = {
    'schema': 1,
    'method': 'Optimized actual AppKit production methods in one disposable logged-in ARM GUI VM. Three A-B-B-A blocks, 200 warmups and 1200 timed invocations per process/case. Samples include autoreleasepool. No per-invocation layer flush, no display-frame or sensor timing.',
    'scope': 'Synchronous TopProcessesView.update preparation and appearance invalidation for eleven retained General/Module NSImageViews.',
    'limitations': 'Does not measure end-to-end Settings opening, frame delivery, FPS, process sampling, whole-app CPU, memory, watts, or battery life. Changed controls intentionally invalidate cached inputs. General/Module artwork only; sidebar icon callbacks are covered by focused native XCTest, not timed here.',
    'source': source,
    'changedFilesFromBaseline': changed,
    'measurements': measurements,
    'rawDataSHA256': hashlib.sha256(raw).hexdigest(),
    'harnessSHA256': hashlib.sha256((root / 'benchmark.swift').read_bytes()).hexdigest(),
    'system': system,
}
(root / 'benchmark-summary.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
print(json.dumps({name: {'baseline_us': item['baseline']['medianOfRunMediansMicroseconds'],
                         'candidate_us': item['candidate']['medianOfRunMediansMicroseconds'],
                         'reductionPercent': item['reductionPercent']} for name, item in measurements.items()}, indent=2))
