# v6 normal slow-drop fixture preparation

This preparation preserves the failed v5 edge-target evidence and changes only the passive fixture's drop-point calculation and geometry export. Production source, the native callback observer, evaluator and lifecycle runner remain unchanged.

The old release point was stack minY+3. NSBox's content border clips the bottom 6pt, and native headless hit testing rejects that point. The new point is stack.visibleRect intersected with stack.bounds, 12pt above the visible lower edge, strictly inside the last row's lower half. The guest must provide finite geometry and a native hit-test ancestry containing the exact stack identity before any input is sent.

`headless-target-result.json` reproduces old-point rejection and new-point acceptance using the actual NSBox content bounds as an explicit clipping proxy: local old y=3, new y=18, effective rect=(6,6,491,348), last-row center y=36. It typechecks the archived helper functions. It creates no application, window or input, and does not prove a guest window's visibleRect or native drag behavior. The root controller owns that separate acceptance.

The v3 overlay SHA-256 is `937b75bdf4fc9688ba34d62b2d4ffc19371bee0f52518a6b1844bdb67420b79a`. Stage invocation is in `provenance.json`. The stage derivation changes one overlay copy path and retains original lifecycle ownership and cleanup.
