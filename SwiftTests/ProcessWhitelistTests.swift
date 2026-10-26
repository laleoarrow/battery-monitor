import XCTest
@testable import Wattson

final class ProcessWhitelistTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = "popover.processWhitelist"

    override func setUp() {
        super.setUp()
        suite = testDefaultsSuite("ProcessWhitelist")
        defaults = UserDefaults(suiteName: suite)!
        Settings.configureForTest(defaults: defaults)
    }

    override func tearDown() {
        Settings.resetTestConfiguration()
        defaults.removePersistentTestDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testExactNamesAreLiteralWholeNamesAndCaseSensitive() {
        let matcher = ProcessWhitelistMatcher(rules: [
            .init(pattern: "python3.12", mode: .exact),
            .init(pattern: "Helper [1]+(.*)?", mode: .exact),
        ])
        XCTAssertTrue(matcher.matches("python3.12"))
        XCTAssertFalse(matcher.matches("python3X12"))
        XCTAssertFalse(matcher.matches("Python3.12"))
        XCTAssertFalse(matcher.matches("python3.12 worker"))
        XCTAssertTrue(matcher.matches("Helper [1]+(.*)?"))
        XCTAssertFalse(matcher.matches("Helper 111worker"))
        XCTAssertFalse(ProcessWhitelistMatcher(rules: []).matches("Mail"))
    }

    func testWildcardsMatchWholeNamesAndEscapeOtherMetacharacters() {
        let matcher = ProcessWhitelistMatcher(rules: [
            .init(pattern: "python3.*", mode: .wildcard),
            .init(pattern: "Worker?", mode: .wildcard),
            .init(pattern: "Helper[1]+(a).*", mode: .wildcard),
        ])
        for name in ["python3.", "python3.12", "Worker1", "Helper[1]+(a).child"] {
            XCTAssertTrue(matcher.matches(name), name)
        }
        for name in ["Python3.12", "prefix python3.12", "python3X12", "Worker", "Worker12", "Helper111a.child"] {
            XCTAssertFalse(matcher.matches(name), name)
        }
        let newline = ProcessWhitelistMatcher(rules: [.init(pattern: "name", mode: .wildcard)])
        XCTAssertFalse(newline.matches("name\n"))
        XCTAssertTrue(ProcessWhitelistMatcher(rules: [.init(pattern: "name*", mode: .wildcard)]).matches("name\nchild"))
    }

    func testRegexSearchAndExplicitAnchorsAreCaseSensitive() {
        let search = ProcessWhitelistMatcher(rules: [.init(pattern: "python[0-9]", mode: .regex)])
        XCTAssertTrue(search.matches("prefix-python3.12"))
        XCTAssertFalse(search.matches("Python3.12"))
        let anchored = ProcessWhitelistMatcher(rules: [.init(pattern: "^python[0-9]+\\.[0-9]+$", mode: .regex)])
        XCTAssertTrue(anchored.matches("python3.12"))
        XCTAssertFalse(anchored.matches("prefix-python3.12"))
        XCTAssertFalse(anchored.matches("python3X12"))
    }

    func testUnicodeNamesUseTheEntireUTF16Range() {
        XCTAssertTrue(ProcessWhitelistMatcher(rules: [.init(pattern: "电池🔋助手", mode: .exact)]).matches("电池🔋助手"))
        let wildcard = ProcessWhitelistMatcher(rules: [.init(pattern: "电池?助手*", mode: .wildcard)])
        XCTAssertTrue(wildcard.matches("电池🔋助手进程"))
        XCTAssertFalse(wildcard.matches("电池🔋🔋助手"))
        XCTAssertTrue(ProcessWhitelistMatcher(rules: [.init(pattern: "助手$", mode: .regex)]).matches("电池🔋助手"))
        XCTAssertTrue(ProcessWhitelistMatcher(rules: [.init(pattern: "^电池🔋助手$", mode: .regex)]).matches("电池🔋助手"))
    }

    func testPathologicalBacktrackingIsBoundedAndDoesNotHideTheProcess() {
        let matcher = ProcessWhitelistMatcher(rules: [.init(pattern: "(a+)+$", mode: .regex)])
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(matcher.matches(String(repeating: "a", count: 63) + "!"))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.5)
        XCTAssertTrue(matcher.matches(String(repeating: "a", count: 64)))
    }

    func testMultipleRegexRulesShareOneNameBudgetAndStillAllowExactMatches() {
        let name = String(repeating: "a", count: 63) + "!"
        let rules = (0..<64).map {
            ProcessWhitelistRule(pattern: "(a+)+$|never-match-\($0)", mode: .regex)
        }
        let failing = ProcessWhitelistMatcher(rules: rules)
        let matching = ProcessWhitelistMatcher(rules: rules + [.init(pattern: name, mode: .exact)])
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertFalse(failing.matches(name))
        XCTAssertTrue(matching.matches(name))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.5)
    }

    func testInvalidAndBlankRulesDoNotMatchOrHideValidRules() {
        let invalid = ProcessWhitelistRule(pattern: "[", mode: .regex)
        XCTAssertNotNil(invalid.validationMessage)
        for mode in ProcessWhitelistRule.MatchMode.allCases {
            for pattern in ["", " \t\n"] {
                let blank = ProcessWhitelistRule(pattern: pattern, mode: mode)
                XCTAssertNotNil(blank.validationMessage)
                XCTAssertFalse(ProcessWhitelistMatcher(rules: [blank]).matches("Mail"))
            }
        }
        let matcher = ProcessWhitelistMatcher(rules: [invalid, .init(pattern: "Mail", mode: .exact)])
        XCTAssertFalse(matcher.matches("["))
        XCTAssertTrue(matcher.matches("Mail"))
        XCTAssertNil(ProcessWhitelistRule(pattern: "[", mode: .exact).validationMessage)
        XCTAssertNil(ProcessWhitelistRule(pattern: "[", mode: .wildcard).validationMessage)
        XCTAssertNil(ProcessWhitelistRule(pattern: " Mail ", mode: .exact).validationMessage)
        XCTAssertTrue(ProcessWhitelistMatcher(rules: [.init(pattern: " Mail ", mode: .exact)]).matches(" Mail "))
    }

    func testDefaultsAreEmptyAndMalformedPreferencesDoNotRewrite() {
        XCTAssertEqual(Settings.processWhitelist, [])
        XCTAssertNil(defaults.object(forKey: key))
        for malformed: Any in [true, "Mail", Data("not json".utf8), Data("[{\"pattern\":\"Mail\",\"mode\":\"future\"}]".utf8)] {
            defaults.set(malformed, forKey: key)
            XCTAssertEqual(Settings.processWhitelist, [])
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, malformed as? NSObject)
        }
    }

    func testReadSanitizesInvalidAndDuplicateRulesWithoutWriting() throws {
        let mail = ProcessWhitelistRule(pattern: "Mail", mode: .exact)
        let wildcard = ProcessWhitelistRule(pattern: "python*", mode: .wildcard)
        let raw = try JSONEncoder().encode([
            mail, .init(pattern: "[", mode: .regex), mail,
            .init(pattern: " \n", mode: .exact), wildcard,
        ])
        defaults.set(raw, forKey: key)
        XCTAssertEqual(Settings.processWhitelist, [mail, wildcard])
        XCTAssertEqual(defaults.data(forKey: key), raw)
    }

    func testRulesPersistAcrossReopeningAndRetainOrderAfterRemoval() throws {
        let exact = ProcessWhitelistRule(pattern: "Mail", mode: .exact)
        let wildcard = ProcessWhitelistRule(pattern: "python*", mode: .wildcard)
        let regex = ProcessWhitelistRule(pattern: "^Worker[0-9]+$", mode: .regex)
        Settings.processWhitelist = [exact, wildcard, exact, .init(pattern: "[", mode: .regex), regex]
        let saved = try XCTUnwrap(defaults.data(forKey: key))
        XCTAssertEqual(try JSONDecoder().decode([ProcessWhitelistRule].self, from: saved), [exact, wildcard, regex])
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.processWhitelist, [exact, wildcard, regex])
        Settings.processWhitelist.removeAll { $0 == wildcard }
        XCTAssertEqual(Settings.processWhitelist, [exact, regex])
        Settings.processWhitelist = []
        Settings.configureForTest(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(Settings.processWhitelist, [])
        XCTAssertEqual(try JSONDecoder().decode([ProcessWhitelistRule].self, from: XCTUnwrap(defaults.data(forKey: key))), [])
    }

    func testOnlyEffectiveChangesNotifyAfterPersistence() {
        var changes: [Settings.Change] = []
        var values: [[ProcessWhitelistRule]] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { notification in
            changes.append(notification.userInfo?[Settings.changeUserInfoKey] as! Settings.Change)
            values.append(Settings.processWhitelist)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let exact = ProcessWhitelistRule(pattern: "Mail", mode: .exact)
        Settings.processWhitelist = []
        Settings.processWhitelist = [.init(pattern: "[", mode: .regex)]
        XCTAssertNil(defaults.object(forKey: key))
        Settings.processWhitelist = [exact, exact]
        Settings.processWhitelist = [exact, .init(pattern: "[", mode: .regex)]
        Settings.processWhitelist = []
        Settings.processWhitelist = []
        XCTAssertEqual(changes, [.processWhitelist, .processWhitelist])
        XCTAssertEqual(values, [[exact], []])
    }

    func testQuickAddPersistsAnExactLiteralRuleAndDeduplicates() {
        var changes: [Settings.Change] = []
        let observer = NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: nil
        ) { changes.append($0.userInfo?[Settings.changeUserInfoKey] as! Settings.Change) }
        defer { NotificationCenter.default.removeObserver(observer) }
        Settings.addProcessToWhitelist(named: "python3.12 [worker]+*")
        Settings.addProcessToWhitelist(named: "python3.12 [worker]+*")
        Settings.addProcessToWhitelist(named: " \n")
        Settings.addProcessToWhitelist(named: "电池🔋助手")
        XCTAssertEqual(Settings.processWhitelist, [
            .init(pattern: "python3.12 [worker]+*", mode: .exact),
            .init(pattern: "电池🔋助手", mode: .exact),
        ])
        XCTAssertEqual(changes, [.processWhitelist, .processWhitelist])
        let matcher = ProcessWhitelistMatcher(rules: Settings.processWhitelist)
        XCTAssertTrue(matcher.matches("python3.12 [worker]+*"))
        XCTAssertFalse(matcher.matches("python3X12 worker"))
    }
}
