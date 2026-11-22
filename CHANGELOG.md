# Changelog

## [1.1.0] - 2026-11-22

### Changed
- The key buttons in the setup are the game's own key binding buttons. Click one and it lights up, and a line at the bottom of the window says what it is waiting for. Escape or a second click cancels, and a right-click empties the key.
- Add a modifier key adds the line and no longer waits for a key right away: click the line's key button to set it.

### Added
- Labels over a modifier key's controls: Key, Hold or tap, What it does, Which bar.

### Fixed
- A long key name such as Mouse Button 4 no longer runs out of its button. A name too long to fit ends in dots, and hovering shows all of it.

## [1.0.1] - 2026-11-22

### Fixed
- With a Fallen's Flyouts flyout open, its keys are the flyout's even when one of them is a modifier key: 1 picks its first icon again, and is the modifier key once the flyout shuts. Needs Fallen's Flyouts 1.1.3 or later.

## [1.0.0] - 2026-11-21

### Added
- Any key or mouse button can be a modifier: hold it and the keys you press abilities with press another action bar. That bar lights up and its buttons show the keys that press them now. It works in combat.
- Tap in place of hold, chosen for each modifier key: tap the key, then press one key. A tapped modifier key is itself a key of its bar, so 1 then 1 is that bar's first button.
- Action bar pages on any bar: a modifier key can make a bar show another bar's abilities in place, and one key can switch several bars at once.
- A setup window, opened with `/fmk`, the minimap button or the addon's page in the game's options: twelve boxes for your action keys, and a line for each modifier key.
- Profiles for a character, a class or everyone.
- Works with Fallen's Flyouts: a key sent to a button with a flyout opens that flyout.
