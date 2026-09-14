import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "tests" / "visual" / "glass_preview.swift"


class GlassPreviewContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = PREVIEW.read_text(encoding="utf-8")

    def test_native_popup_exposes_three_full_names_and_starts_clear(self):
        self.assertIn("private let theme = NSPopUpButton()", self.source)
        mapping = self.source.split("private enum PreviewPresentation", 1)[1].split(
            "private final class PreviewDefaults", 1
        )[0]
        for title in ("Classic", "Standard Glass", "Clear Glass"):
            self.assertIn(f'return "{title}"', mapping)
        self.assertIn("theme.addItems(withTitles: PreviewPresentation.allCases.map(\\.title))",
                      self.source)
        launch = self.source.split("func applicationDidFinishLaunching", 1)[1].split(
            "func applicationShouldTerminateAfterLastWindowClosed", 1
        )[0]
        self.assertIn("PreviewPresentation.clearGlass.apply()", launch)
        self.assertIn("theme.selectItem(at: PreviewPresentation.current.rawValue)", launch)

    def test_user_choice_is_captured_before_notifying_settings_writes(self):
        action = self.source.split("@objc private func changePresentation()", 1)[1].split(
            "@objc private func changeHostAppearance()", 1
        )[0]
        capture = "let selection = PreviewPresentation(rawValue: theme.indexOfSelectedItem)"
        self.assertIn(capture, action)
        self.assertLess(action.index(capture), action.index("selection.apply()"))
        self.assertNotIn("NSApp.appearance", action)
        self.assertNotIn("diagnosticBackdrop", action)
        self.assertNotIn("theme.selectedSegment", self.source)

    def test_host_appearance_and_diagnostic_backdrop_remain_independent(self):
        appearance = self.source.split("@objc private func changeHostAppearance()", 1)[1].split(
            "@objc private func changeFixture()", 1
        )[0]
        backdrop = self.source.split("@objc private func changeBackdrop()", 1)[1].split(
            "@objc private func showPopover()", 1
        )[0]
        self.assertIn("appearance.action = #selector(changeHostAppearance)", self.source)
        self.assertIn("NSApp.appearance =", appearance)
        self.assertIn("backdrop.diagnostic = diagnosticBackdrop.state == .on", backdrop)
        for action in (appearance, backdrop):
            self.assertNotIn("Settings.liquidGlass", action)
            self.assertNotIn("PreviewPresentation", action)
            self.assertNotIn("theme.", action)
        self.assertNotIn("NSApp.appearance", backdrop)
        self.assertNotIn("diagnosticBackdrop", appearance)

    def test_no_window_self_test_covers_mapping_and_reverse_synchronization(self):
        main = self.source.split("static func main()", 1)[1].split(
            "private static func verifyDefaults()", 1
        )[0]
        self.assertLess(main.index("verifyDefaults()"), main.index("NSApplication.shared"))
        verifier = self.source.split("private static func verifyDefaults()", 1)[1].split(
            "private enum PreviewPresentation", 1
        )[0]
        self.assertIn("capturedSelection.apply()", verifier)
        self.assertIn("precondition(PreviewPresentation.current == selection)", verifier)
        self.assertIn("precondition(synchronizedIndex == selection.rawValue)", verifier)
        for choice in ("classic", "standardGlass", "clearGlass"):
            self.assertIn(f".{choice}", verifier)
        self.assertIn("Settings.liquidGlassStyle = .clear", verifier)
        self.assertIn("Settings.liquidGlassEnabled = false", verifier)
        self.assertIn("Settings.liquidGlassEnabled = true", verifier)
        self.assertIn("NotificationCenter.default.removeObserver(observer)", verifier)
        self.assertNotIn("NSApplication.shared", verifier)
        self.assertNotIn("NSWindow(", verifier)

    def test_opt_in_gui_cycles_use_actual_actions_and_check_installed_content(self):
        launch = self.source.split("func applicationDidFinishLaunching", 1)[1].split(
            "func applicationShouldTerminateAfterLastWindowClosed", 1
        )[0]
        self.assertIn('CommandLine.arguments.contains("--verify-presentation-cycles")', launch)
        cycles = self.source.split("private func verifyPresentationCycles()", 1)[1].split(
            "private func mockDependencies()", 1
        )[0]
        for action in ("changeHostAppearance()", "changeBackdrop()",
                       "changePresentation()", "changeFixture()"):
            self.assertIn(action, cycles)
        for proof in ("originalRoot.window === activeWindow", "installed.contains",
                      "originalRoot.superview === panel?.contentView", "material?.style",
                      "footerVisible", "fields.contains", "popover.cachedPercentForTest",
                      "visibleGlassPanels.count", "visibleGlassPanels.allSatisfy",
                      "after native close delay", "withTimeInterval: 0.75",
                      "PREVIEW_PRESENTATION_CYCLES_PASSED", "PREVIEW_PRESENTATION_CYCLES_FAILED",
                      'fail("60-second GUI watchdog expired")'):
            self.assertIn(proof, cycles)
        self.assertNotIn("Settings.liquidGlassEnabled =", cycles)
        self.assertNotIn("Settings.liquidGlassStyle =", cycles)
        self.assertNotIn("CGEvent", cycles)
        self.assertNotIn("postEvent", cycles)


if __name__ == "__main__":
    unittest.main()
