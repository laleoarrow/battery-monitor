#!/usr/bin/env python3
"""Create a diagnostic-only patch against source plus the exact frozen v1 harness.

Usage: create_ui_open_attribution.py [SOURCE_ROOT] [OUTPUT_PATCH] [FROZEN_HARNESS]
Never alter the measured checkout in place.
"""
from pathlib import Path
import difflib
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[4]
output = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(__file__).with_name('ui-open-attribution-v1.patch')
frozen_harness = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else Path(__file__).with_name('frozen-ui-latency-v1.swift')
changed = {}

def source(path):
    text = (frozen_harness if path == 'tests/performance/ui-latency.swift' else root / path).read_text()
    changed[path] = [text, text]

def replace(path, old, new):
    text = changed[path][1]
    if text.count(old) != 1:
        raise RuntimeError(f'{path}: expected one match, got {text.count(old)} for {old[:80]}')
    changed[path][1] = text.replace(old, new, 1)

p = 'Popover/PopoverController.swift'
source(p)
helper = '''
// Diagnostic-only checkpoints; this file is a temporary source copy.
// A trace stores numbers in memory and is emitted after open returns.
enum UIOpenAttribution {
    static var stages = [String: Double]()
    final class Scope {
        let prefix: String
        let start = DispatchTime.now().uptimeNanoseconds
        var last = DispatchTime.now().uptimeNanoseconds
        init(_ prefix: String) { self.prefix = prefix }
        func mark(_ name: String) {
            let now = DispatchTime.now().uptimeNanoseconds
            UIOpenAttribution.stages[prefix + "." + name] = Double(now - last) / 1_000_000
            last = now
        }
        func finish() {
            mark("tail")
            UIOpenAttribution.stages[prefix + ".total"] = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
    }
}
'''
replace(p, 'import AppKit\n', 'import AppKit\n' + helper)
replace(p, 'skipExternalRefreshes: Bool = false) {\n', 'skipExternalRefreshes: Bool = false) {\n        UIOpenAttribution.stages = [:]\n        let diagnostic = UIOpenAttribution.Scope("open")\n        defer { diagnostic.finish() }\n')
replace(p, 'setContentSize(placement.contentSize)\n        // Prime', 'setContentSize(placement.contentSize)\n        diagnostic.mark("initial_placement_and_size")\n        // Prime')
replace(p, 'applyLatestPresentation()\n        // A newly', 'applyLatestPresentation()\n        diagnostic.mark("prime_cached_content")\n        // A newly')
replace(p, 'setContentSize(placement.contentSize)\n        if #available', 'setContentSize(placement.contentSize)\n        diagnostic.mark("final_placement_and_size")\n        if #available')
replace(p, 'retireClassicHost()\n            let panel', 'retireClassicHost()\n            diagnostic.mark("retire_classic")\n            let panel')
replace(p, 'showsArrow: Settings.showPopoverArrow)\n            panel.point', 'showsArrow: Settings.showPopoverArrow)\n            diagnostic.mark("panel_init")\n            panel.point')
replace(p, 'glassPanel = panel\n            panel.makeKeyAndOrderFront(nil)', 'glassPanel = panel\n            diagnostic.mark("point_appearance_and_callbacks")\n            panel.makeKeyAndOrderFront(nil)\n            diagnostic.mark("make_key_and_order_front")')
replace(p, 'if let initialFocus = panel.initialFirstResponder { panel.makeFirstResponder(initialFocus) }', 'if let initialFocus = panel.initialFirstResponder { panel.makeFirstResponder(initialFocus) }\n            diagnostic.mark("initial_focus")')
replace(p, 'if popover.isShown { showsRequested += 1 }\n        }\n        guard hostIsShown', 'if popover.isShown { showsRequested += 1 }\n            diagnostic.mark("classic_show")\n        }\n        guard hostIsShown')
replace(p, 'presentationGeneration &+= 1\n        let generation = presentationGeneration\n        wantsOpen = true', 'diagnostic.mark("activate_content_and_entrance_animation")\n        presentationGeneration &+= 1\n        let generation = presentationGeneration\n        wantsOpen = true')
replace(p, 'visibilityHandler?(true)\n            return', 'visibilityHandler?(true)\n            diagnostic.mark("outside_monitors_and_visibility")\n            return')
p = 'Popover/GlassPopoverPanel.swift'
source(p)
replace(p, 'self.showsArrow = showsArrow\n        super.init', 'let diagnostic = UIOpenAttribution.Scope("panel")\n        defer { diagnostic.finish() }\n        self.showsArrow = showsArrow\n        super.init')
replace(p, 'backing: .buffered, defer: false)\n', 'backing: .buffered, defer: false)\n        diagnostic.mark("ns_panel_super_init")\n')
replace(p, 'let glass = GlassPopoverMaterialView', 'diagnostic.mark("configure_window")\n        let glass = GlassPopoverMaterialView')
replace(p, 'style: style, showsArrow: showsArrow)\n        glass.autoresizingMask', 'style: style, showsArrow: showsArrow)\n        diagnostic.mark("swiftui_material_init")\n        glass.autoresizingMask')
replace(p, 'material = glass\n        updateOutline()', 'material = glass\n        diagnostic.mark("create_background_and_attach_content")\n        updateOutline()\n        diagnostic.mark("update_outline")')
p = 'Popover/GlassPopoverMaterialView.swift'
source(p)
replace(p, 'self.style = style\n        self.showsArrow', 'let diagnostic = UIOpenAttribution.Scope("material")\n        defer { diagnostic.finish() }\n        self.style = style\n        self.showsArrow')
replace(p, 'super.init(rootView: Self.material(style: style, arrowX: arrowX, showsArrow: showsArrow))\n', 'super.init(rootView: Self.material(style: style, arrowX: arrowX, showsArrow: showsArrow))\n        diagnostic.mark("root_view_and_ns_hosting_super_init")\n')
replace(p, 'self.frame = frame\n        setAccessibilityElement(false)', 'self.frame = frame\n        setAccessibilityElement(false)\n        diagnostic.mark("frame_and_accessibility")')
p = 'tests/performance/ui-latency.swift'
source(p)
replace(p, 'let callMS = milliseconds(since: openStart)\n        guard let window', 'let callMS = milliseconds(since: openStart)\n        emit(["type": "open_attribution", "mode": mode, "cold": cold, "index": index,\n            "warmup": index < warmups, "call_ms": callMS, "stages_ms": UIOpenAttribution.stages])\n        guard let window')
replace(p, '["WATTSON_PERF_WARM_COUNT"] ?? "60"', '["WATTSON_PERF_WARM_COUNT"] ?? "20"')
replace(p, '"type": "environment", "schema": 1,', '"type": "environment", "schema": 1,\n            "diagnostic_only": true, "cases_executed": ["popup_reopen_warm"],\n            "diagnostic_limit": "checkpoint overhead included; traces serialized after call timing; cold/theme loops omitted; observer/animation milestones are perturbed by trace serialization",')
replace(p, '''            for index in 0..<(coldCount + warmups) {
                try await measureOpen(mode: mode, cold: true, index: index)
            }
''', '')
replace(p, '''            for surface in ["popup", "general", "menu-bar-icon", "modules"] {
                try await measureThemes(mode: mode, surface: surface)
            }
''', '')
patch = ''.join(''.join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True), fromfile='a/' + path, tofile='b/' + path)) for path, (original, modified) in changed.items())
output.write_text(patch)
print(json.dumps({'patch': str(output), 'sha256': hashlib.sha256(patch.encode()).hexdigest(), 'bytes': len(patch)}, sort_keys=True))
