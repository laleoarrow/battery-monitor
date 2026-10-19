# Display settings refinement

The requested direction is consistent with Wattson's native settings: simple,
clear, restrained surfaces and precise alignment. Existing battery artwork and
all four icon-style/percentage combinations remain available.

The page separates the two existing preferences. Two selectable style rows share
seven state headings and use the production BatteryIcon renderer at natural
size. A small Off/On popup controls percentage display in both rows. Selection
uses the existing theme colors, a light fill and a thin outline; high contrast
keeps a stronger outline. Changes retain controls, keyboard focus and the other
preference, with no helper requests or new saved settings.

Production changes are restricted to the Display section in
`MenuBar/SettingsWindowController.swift`. The canonical installed 4.3.23 app is
not used for testing. The owned VM workflow in [qa](qa/README.md) compares the
old and new production Settings hierarchy at the same window size, captures
Classic/Glass and Light/Dark, and runs the native settings contract. Validation
results and real rendering evidence are added after that workflow completes.
