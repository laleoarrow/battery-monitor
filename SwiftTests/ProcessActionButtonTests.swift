import AppKit
import XCTest
@testable import Wattson

final class ProcessActionButtonTests: XCTestCase {
    private final class Target: NSObject {
        var presses = 0
        @objc func press(_ sender: NSButton) { presses += 1 }
    }

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testCapsuleKeepsItsAssignedFrameAndNativeAction() {
        let frame = NSRect(x: 300, y: 4, width: 28, height: 16)
        let button = ProcessActionButton(frame: frame)
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.performClick(nil)
        XCTAssertEqual(target.presses, 1)
        XCTAssertEqual(button.frame, frame)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        XCTAssertEqual(button.controlSize, .mini)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.keyEquivalent, "")
        if #available(macOS 26.0, *) {
            XCTAssertEqual(button.bezelStyle, .glass)
            XCTAssertEqual(button.borderShape, .capsule)
        }
    }

    func testDisabledCapsuleDoesNotDispatchAndCanBeReenabled() {
        let button = ProcessActionButton(frame: NSRect(x: 0, y: 0, width: 28, height: 16))
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.isEnabled = false
        button.performClick(nil)
        XCTAssertEqual(target.presses, 0)
        button.isEnabled = true
        button.performClick(nil)
        XCTAssertEqual(target.presses, 1)
    }

    func testAppearanceRefreshPreservesCallerControlConfiguration() {
        let button = ProcessActionButton(frame: NSRect(x: 300, y: 4, width: 28, height: 16))
        let target = Target()
        button.target = target
        button.action = #selector(Target.press(_:))
        button.toolTip = "Force Quit"
        button.setAccessibilityLabel("Force Quit Safari")
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua,
                               .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            button.appearance = NSAppearance(named: appearanceName)
            button.refreshAppearance()
            XCTAssertTrue(button.target === target)
            XCTAssertEqual(button.action, #selector(Target.press(_:)))
            XCTAssertEqual(button.toolTip, "Force Quit")
            XCTAssertEqual(button.accessibilityLabel(), "Force Quit Safari")
            XCTAssertEqual(button.frame, NSRect(x: 300, y: 4, width: 28, height: 16))
            XCTAssertNotNil(button.image)
        }
    }
}
