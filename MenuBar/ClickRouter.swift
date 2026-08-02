import AppKit

/// What one half of a status item click should cause.
enum ClickIntent: Equatable {
    /// Show the pressed styling. A coloured icon must revert to template while
    /// the selection highlight is drawn behind it.
    case press
    case release
    /// Toggle the popover.
    case primary
    /// Toggle the energy mode.
    case secondary
}

/// The decision half of a status item click, separated from the event handler.
///
/// This logic used to live inside `handleClick`, reading `NSApp.currentEvent`
/// directly, which made it impossible to test and easy to get wrong. It was
/// wrong: the handler required a non-nil current event, and a trackpad tap is
/// short enough that the event is already gone by the time the action runs — so
/// taps did nothing while a held press worked. AppKit may also deliver only one
/// half of the pair for a tap.
///
/// The rules: act on whichever half arrives first, let the matching half pass
/// without acting, and treat a missing event as an ordinary primary click.
///
/// Pairing is tracked as state, not as a time window. A window looks equivalent
/// and is not: hold the button past the window and the release counts as a
/// second click, so a long press opened the popover and immediately closed it.
struct ClickRouter {
    private var pressAlreadyActed = false

    mutating func intents(for type: NSEvent.EventType?,
                          controlHeld: Bool = false) -> [ClickIntent] {
        let isPress = type == .leftMouseDown || type == .rightMouseDown
        let isRelease = type == .leftMouseUp || type == .rightMouseUp
        let isSecondary = type == .rightMouseDown || type == .rightMouseUp || controlHeld
        let action: ClickIntent = isSecondary ? .secondary : .primary

        if isPress {
            pressAlreadyActed = true
            return [.press, action]
        }
        if isRelease {
            // A tap can arrive as a release with no press of its own.
            guard pressAlreadyActed else { return [.release, action] }
            pressAlreadyActed = false
            return [.release]
        }
        // No event at all: the tap was over before the action ran.
        return [action]
    }
}
