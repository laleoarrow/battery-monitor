# Battery Power Monitor agent docs

Use these files when working on `电池功率`:

- `project.md` — architecture, important files, telemetry collection, and layouts.
- `debugging.md` — how to verify layout alignment, test charging/discharging states, and diagnose rendering bugs.
- `release.md` — how to rebuild the app bundle, generate custom icons, and run the install script.
- `cleanup.md` — project memory: mandatory automatic cleanup for every build/test.
- `../TODO.md` — user-requested features awaiting implementation.

Recommended reading order:

1. `cleanup.md` before any build or test
2. `project.md`
3. `debugging.md`
4. `release.md`

## Pro review browser

When the user requests Pro assistance, use the existing signed-in ChatGPT
session in SunBrowser (`com.adspower.SunBrowser`). This is the user's preferred
app; do not start a separate Edge login. If multiple installed SunBrowser
versions share that bundle identifier, bind the currently running app by its
full path. Verify the selected Pro mode in the UI before submitting a review.
