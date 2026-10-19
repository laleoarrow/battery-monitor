# Wattson 4.3.23 release

This maintenance release preserves existing UI, features, settings, activity-score
formula and helper permissions. It reduces redundant action-image refreshes,
preserves process keyboard focus across ranking updates, bounds an overdue
worker idle-poll edge case, and makes an existing feedback capture explicit.
Test cleanup and universal architecture verification support the current tools.

Runtime source and macOS27 evidence are recorded in
[the performance review](../performance-hardening-20261019/README.md).
Versioned release acceptance requires exact-main Headless CI, one community
candidate artifact set, the hosted installation matrix, checksum-verified
publication, Homebrew/public installation and Pages gates, followed by canonical
Mac synchronization with the exact public PKG. No new UI or measured whole-app
speed/energy claim is made. Publication and cleanup evidence will be retained
under this directory after the frozen-source release gates complete.
