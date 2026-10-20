import Foundation

struct ProcessWhitelistRule: Codable, Equatable, Sendable {
    enum MatchMode: String, Codable, CaseIterable, Sendable {
        case exact, wildcard, regex
    }

    let pattern: String
    let mode: MatchMode

    init(pattern: String, mode: MatchMode) {
        self.pattern = pattern
        self.mode = mode
    }

    var validationMessage: String? {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter a process name or pattern."
        }
        if mode == .regex, (try? NSRegularExpression(pattern: pattern)) == nil {
            return "Invalid regular expression."
        }
        return nil
    }
}

/// Compile patterns when preferences change, rather than on each sampled name.
struct ProcessWhitelistMatcher {
    private enum Rule {
        case exact(String)
        case expression(NSRegularExpression)
    }

    private let rules: [Rule]

    init(rules: [ProcessWhitelistRule]) {
        self.rules = rules.compactMap { rule in
            guard rule.validationMessage == nil else { return nil }
            switch rule.mode {
            case .exact:
                return .exact(rule.pattern)
            case .wildcard:
                let body = rule.pattern.map { character -> String in
                    switch character {
                    case "*": return "[\\s\\S]*"
                    case "?": return "[\\s\\S]"
                    default: return NSRegularExpression.escapedPattern(for: String(character))
                    }
                }.joined()
                guard let expression = try? NSRegularExpression(pattern: "\\A" + body + "\\z") else {
                    return nil
                }
                return .expression(expression)
            case .regex:
                guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { return nil }
                return .expression(expression)
            }
        }
    }

    func matches(_ name: String) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.01
        return rules.contains { rule in
            switch rule {
            case .exact(let pattern):
                return name == pattern
            case .expression(let expression):
                // User patterns can backtrack heavily, even on short names. The
                // engine's progress callback stops work after a small per-name budget.
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                var matched = false
                expression.enumerateMatches(
                    in: name, options: .reportProgress, range: NSRange(name.startIndex..., in: name)
                ) { result, flags, stop in
                    if ProcessInfo.processInfo.systemUptime >= deadline || flags.contains(.internalError) {
                        stop.pointee = true
                    } else if result != nil {
                        matched = true
                        stop.pointee = true
                    }
                }
                return matched
            }
        }
    }
}
