#!/usr/bin/env python3
"""Create a diagnostic-only patch against source plus the exact frozen v3 harness.

Usage: create_ui_combined_attribution.py [GIT_REVISION] [OUTPUT_PATCH]
Never alter the measured checkout in place.
"""
from pathlib import Path
import difflib
import hashlib
import json
import sys
import subprocess

root = Path(__file__).resolve().parents[4]
revision = sys.argv[1] if len(sys.argv) > 1 else 'd6b40247'
output = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else Path(__file__).with_name('ui-combined-attribution.patch')
frozen_harness = Path(__file__).with_name('frozen-ui-latency-v3.swift')
changed = {}

def source(path):
    text = frozen_harness.read_text() if path == 'tests/performance/ui-latency.swift' else subprocess.check_output(['git', '-C', str(root), 'show', revision + ':' + path], text=True)
    changed[path] = [text, text]

def replace(path, old, new):
    text = changed[path][1]
    if text.count(old) != 1:
        raise RuntimeError(f'{path}: expected one match, got {text.count(old)} for {old[:80]}')
    changed[path][1] = text.replace(old, new, 1)

p = 'Popover/PopoverController.swift'
source(p)
helper = '''
// Diagnostic source copy only. No callback output or serialization occurs
// while open runs. Callback durations are inclusive and must not be added
// to containing open/panel stage durations or to each other when nested.
enum UIOpenAttribution {
    static var stages = [String: Double]()
    static var combined = false
    static var variant: String { combined ? "early_window_first" : "original" }
    static var callbackCounts = [String: Int]()
    static var callbackMS = [String: Double]()
    static var callbackEvents = [[String: Any]]()
    static var collecting = false
    static var origin: UInt64 = 0
    static func reset() {
        stages = [:]
        callbackCounts = [:]
        callbackMS = [:]
        callbackEvents = []
        origin = DispatchTime.now().uptimeNanoseconds
        collecting = true
    }
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
    final class Callback {
        let name: String
        let active = UIOpenAttribution.collecting
        let start = DispatchTime.now().uptimeNanoseconds
        init(_ label: String, attached: Bool) { name = label + (attached ? ".window" : ".nil") }
        func finish(view: NSView) {
            guard active else { return }
            let end = DispatchTime.now().uptimeNanoseconds
            let elapsed = Double(end - start) / 1_000_000
            UIOpenAttribution.callbackCounts[name, default: 0] += 1
            UIOpenAttribution.callbackMS[name, default: 0] += elapsed
            UIOpenAttribution.callbackEvents.append([
                "name": name, "start_relative_ns": start - UIOpenAttribution.origin,
                "end_relative_ns": end - UIOpenAttribution.origin, "inclusive_ms": elapsed,
                "window_attached_at_end": view.window != nil,
                "effective_appearance_at_end": view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "unknown",
            ])
        }
    }
}
'''
replace(p, 'import AppKit\n', 'import AppKit\n' + helper)
replace(p, 'skipExternalRefreshes: Bool = false) {\n', 'skipExternalRefreshes: Bool = false) {\n        UIOpenAttribution.reset()\n        let diagnostic = UIOpenAttribution.Scope("open")\n        defer { diagnostic.finish(); UIOpenAttribution.collecting = false }\n')
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
replace(p, 'let callMS = milliseconds(since: openStart)\n        guard let window', 'let callMS = milliseconds(since: openStart)\n        emit(["type": "open_attribution", "mode": mode, "cold": cold, "index": index,\n            "warmup": index < warmups, "call_ms": callMS, "stages_ms": UIOpenAttribution.stages, "callback_counts": UIOpenAttribution.callbackCounts,\n            "callback_inclusive_ms": UIOpenAttribution.callbackMS, "callback_events": UIOpenAttribution.callbackEvents,\n            "callback_capture": "synchronous_open_only; inclusive callbacks nest within stages"])\n        guard let window')
replace(p, '"type": "environment", "schema": 3, "submission": submission,', '"type": "environment", "schema": 3, "submission": submission,\n            "diagnostic_only": true, "cases_executed": ["popup_reopen_warm"],\n            "diagnostic_limit": "checkpoint overhead included; traces serialized after call timing; cold/theme counts must be zero and are verified by driver; observer/animation milestones are perturbed by trace serialization",')

# Split the previously combined point/appearance/checkpoint group.
p = 'Popover/PopoverController.swift'
replace(p, 'panel.point(to: placement.anchorFrame.midX)\n', 'panel.point(to: placement.anchorFrame.midX)\n            diagnostic.mark("point")\n')
if 'panel.appearance = Settings.colorScheme.appearance\n' in changed[p][1]:
    replace(p, 'panel.appearance = Settings.colorScheme.appearance\n', 'panel.appearance = Settings.colorScheme.appearance\n            diagnostic.mark("set_window_appearance")\n')
replace(p, 'diagnostic.mark("point_appearance_and_callbacks")', 'diagnostic.mark("store_panel_and_callbacks")')
p = 'Popover/GlassPopoverPanel.swift'
replace(p, 'foreground.addSubview(content)\n', 'foreground.addSubview(content)\n        diagnostic.mark("attach_content_to_foreground")\n')
replace(p, 'contentView!.addSubview(foreground)\n', 'contentView!.addSubview(foreground)\n        diagnostic.mark("attach_foreground_to_window")\n')
replace(p, 'diagnostic.mark("create_background_and_attach_content")', 'diagnostic.mark("store_host_references")')
p = 'Popover/PopoverContentView.swift'
source(p)
replace(p, '    override func viewDidMoveToWindow() {\n', '    override func viewDidMoveToWindow() {\n        let diagnostic = UIOpenAttribution.Callback("surface.move", attached: window != nil)\n        defer { diagnostic.finish(view: self) }\n')
# Only the surface override has this exact super/appearanceDidChange body.
replace(p, '    override func viewDidChangeEffectiveAppearance() {\n        super.viewDidChangeEffectiveAppearance()\n        appearanceDidChange?()\n', '    override func viewDidChangeEffectiveAppearance() {\n        let diagnostic = UIOpenAttribution.Callback("surface.effectiveAppearance", attached: window != nil)\n        defer { diagnostic.finish(view: self) }\n        super.viewDidChangeEffectiveAppearance()\n        appearanceDidChange?()\n')
replace(p, '    private func refreshAppearance() {\n        view.effectiveAppearance.performAsCurrentDrawingAppearance {', '    private func refreshAppearance() {\n        let diagnostic = UIOpenAttribution.Callback("content.refreshAppearance", attached: view.window != nil)\n        defer { diagnostic.finish(view: view) }\n        view.effectiveAppearance.performAsCurrentDrawingAppearance {')

# Paired source-copy experiment only; the product still has late appearance.
if "panel.appearance = Settings.colorScheme.appearance" not in changed["Popover/PopoverController.swift"][0]:
    raise RuntimeError("Paired experiment requires the original late-appearance source")
p = 'Popover/GlassPopoverPanel.swift'
replace(p, '        foreground.addSubview(content)\n        diagnostic.mark("attach_content_to_foreground")\n        contentView!.addSubview(foreground)\n        diagnostic.mark("attach_foreground_to_window")\n', '        if UIOpenAttribution.combined {\n            contentView!.addSubview(foreground)\n            diagnostic.mark("attach_foreground_to_window")\n            foreground.addSubview(content)\n            diagnostic.mark("attach_content_to_foreground")\n        } else {\n            foreground.addSubview(content)\n            diagnostic.mark("attach_content_to_foreground")\n            contentView!.addSubview(foreground)\n            diagnostic.mark("attach_foreground_to_window")\n        }\n')
p = 'tests/performance/ui-latency.swift'
replace(p, '    private func record(_ row: [String: Any]) {\n        samples.append(row)', '    private func record(_ row: [String: Any]) {\n        var row = row\n        row["variant"] = UIOpenAttribution.variant\n        samples.append(row)')
p = 'tests/performance/ui-latency.swift'
replace(p, '"callback_capture": "synchronous_open_only; inclusive callbacks nest within stages"', '"variant": UIOpenAttribution.variant, "callback_capture": "synchronous_open_only; inclusive callbacks nest within stages"')
p = 'tests/performance/ui-latency.swift'
replace(p, '"diagnostic_only": true, "cases_executed": ["popup_reopen_warm"],', '"diagnostic_only": true, "diagnostic_variants": ["original", "early_window_first"], "cases_executed": ["popup_reopen_warm"],')
p = 'tests/performance/ui-latency.swift'
replace(p, '            if warmCount > 0 {\n                for index in 0..<(warmCount + warmups) {\n                    try await measureOpen(mode: mode, cold: false, index: index)\n                }\n            }\n            popup = nil\n', '            for diagnosticCombined in [false, true] {\n                UIOpenAttribution.combined = diagnosticCombined\n                if warmCount > 0 {\n                    for index in 0..<(warmCount + warmups) {\n                        try await measureOpen(mode: mode, cold: false, index: index)\n                    }\n                }\n                popup = nil\n                emit(["type": "variant_complete", "mode": mode, "variant": UIOpenAttribution.variant])\n            }\n')
p = 'tests/performance/ui-latency.swift'
replace(p, '"\\($0["mode"]!)/\\($0["case"]!)" +', '"\\($0["mode"]!)/\\($0["case"]!)/\\($0["variant"]!)" +')

p = 'Popover/GlassPopoverPanel.swift'
replace(p, '        diagnostic.mark("ns_panel_super_init")\n', '        diagnostic.mark("ns_panel_super_init")\n        if UIOpenAttribution.combined { self.appearance = Settings.colorScheme.appearance }\n        diagnostic.mark("conditional_early_appearance")\n')

patch = ''.join(''.join(difflib.unified_diff(original.splitlines(True), modified.splitlines(True), fromfile='a/' + path, tofile='b/' + path)) for path, (original, modified) in changed.items())
output.write_text(patch)
print(json.dumps({'patch': str(output), 'sha256': hashlib.sha256(patch.encode()).hexdigest(), 'bytes': len(patch)}, sort_keys=True))
