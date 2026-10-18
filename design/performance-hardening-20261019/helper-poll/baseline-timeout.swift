private func socketPollTimeoutMilliseconds(
    requestContinuousNow: UInt64,
    nextReadContinuousDeadline: UInt64?,
    idleUptimeNow: UInt64,
    idleUptimeDeadline: UInt64
) -> Int32 {
    let now: UInt64
    let deadline: UInt64
    if let nextReadContinuousDeadline {
        now = requestContinuousNow
        deadline = nextReadContinuousDeadline
    } else {
        now = idleUptimeNow
        deadline = idleUptimeDeadline
    }
    guard deadline > now else { return 0 }

    let remaining = deadline - now
    let wholeMilliseconds = remaining / 1_000_000
    let roundedMilliseconds = wholeMilliseconds + (remaining % 1_000_000 == 0 ? 0 : 1)
    return Int32(min(UInt64(Int32.max), roundedMilliseconds))
}

