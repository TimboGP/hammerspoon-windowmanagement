# hammerspoon-window-mgmt

A keyboard-driven workspace/tiling window manager for macOS, built as a
[Hammerspoon](https://www.hammerspoon.org/) Spoon. v1 targets a single
monitor. Full design doc: see the project's plan history for the original
architecture writeup covering the data model, module layout, and rationale
behind each decision (grid-based tiling, minimize-based virtual workspace
switching, JSON persistence, etc).

## Status

Work-in-progress, built milestone by milestone:

- [x] **M0** — Spoon scaffold, config, Accessibility permission check, menu
      bar stub, leader-key modal with idle-timeout and a hardcoded escape
      hatch
- [x] **M1** — Grid math + manual tiling snap (halves/thirds/quarters/mixes),
      via a `t` tiling sub-mode and a `g` free grid-select sub-mode
- [x] **M2** — Workspace membership (add/remove windows, placeholder canvas),
      via a `g` membership sub-mode
- [ ] **M3** — Workspace switching (minimize-based show/hide)
- [ ] **M4** — Window swap (directional + hint-label overlay)
- [ ] **M5** — Persistence (save/load a workspace, app+title matching)
- [ ] **M6** — Arrangements (bundles of workspaces, bulk switch)
- [ ] **M7** — Auto-track opt-in watcher + per-app ignore list
- [ ] **M8** — Polish (menu bar parity, README limitations, final pass)

## Install

```sh
ln -s "$(pwd)/WindowMgmt.spoon" ~/.hammerspoon/Spoons/WindowMgmt.spoon
```

In `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("WindowMgmt")
spoon.WindowMgmt:start()
```

Reload Hammerspoon's config after editing (menu bar icon → Reload Config).
Grant Hammerspoon Accessibility permission when prompted — nothing in this
Spoon works without it (System Settings → Privacy & Security →
Accessibility).

## Usage

- Leader key: `cmd+ctrl+alt+space` (default, see `config.lua`). Press it to
  enter the modal; an alert confirms entry. Press `esc`, or wait ~5s idle,
  to exit.
- Escape hatch: `cmd+ctrl+alt+shift+esc`, always live (works even outside
  the modal). Force-exits a stuck modal — useful if `hs.reload()` fires
  while the modal was active.
- Tiling (`t` from the leader modal): `h`/`l`/`k`/`j` for left/right/top/
  bottom half, `1`/`2`/`3` for left/center/right third, `4`/`5` for left/
  right two-thirds, `y`/`u`/`b`/`n` for TL/TR/BL/BR quarters, `f` for full
  screen, `g` for a free grid-select (hjkl grows the zone, shift+hjkl moves
  its start corner, Enter confirms, Esc cancels), `esc` to back out.
- Workspace membership (`g` from the leader modal): `a` adds the focused
  window to the workspace — filling the first empty (placeholder) slot if
  one exists, snapping the window into it, otherwise registering a new slot
  at the window's current position. `r` removes the focused window from the
  workspace, minimizes it, and leaves a labeled placeholder canvas in its
  zone. To restore a removed window: unminimize/focus it again (Dock click,
  Cmd+Tab, or Mission Control), then `g` `a` to re-add it to the same slot.

Remaining action keybindings (workspace switch, swap, save/load, etc.) land
as their milestones are implemented; see Status above.

## Troubleshooting

If the leader key alert appears but subsequent keys (`t`, `h`, etc.) don't
seem to register and instead leak through to whatever app is focused, check
for other global keyboard/automation tools that might be capturing the same
keys first — Karabiner-Elements, Raycast, Alfred, Rectangle, Magnet, or
similar. These don't necessarily conflict, but if something seems stuck,
try quitting them one at a time to isolate the culprit, or reassign this
Spoon's `leader`/tiling keys in `config.lua` and `tiling.lua` to combos
they don't use.

## Known v1 limitations

- **Single monitor only.**
- "Hide" is implemented as **minimize**, not a true instant per-window
  hide — macOS/Hammerspoon has no public API for hiding a single window
  independent of its app (hiding is either app-wide, or requires private
  undocumented APIs this project deliberately avoids, for the same reason
  it avoids `hs.spaces`). Every workspace switch triggers the Dock
  genie/scale animation per window. Enabling **System Settings →
  Accessibility → Reduce Motion** makes minimize/unminimize near-instant.
- Window re-matching on workspace load (by bundle ID + saved title
  pattern) is best-effort — volatile titles (e.g. browser tabs) can cause
  a mismatch. The matcher falls back to the first unclaimed window of that
  app and alerts you when it had to guess.
- Two windows of the same app with identical titles in one workspace can't
  be reliably told apart; slot order is the tiebreaker.
- No undo for tiling/swap actions.
