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
- [x] **M3** — Workspace switching (minimize-based show/hide), via number
      keys `1`-`9`, a name picker on `p`, and `n` to create a named
      workspace
- [x] **M4** — Window swap (directional + hint-label overlay), via an `x`
      swap sub-mode
- [x] **M5** — Persistence (save/load a workspace, app+title matching), via
      an `s` save/load sub-mode
- [x] **M6** — Arrangements (bundles of workspaces, bulk switch), via `a`
      (save arrangement) and `shift+l` (load arrangement) in the `s`
      sub-mode
- [x] **M7** — Auto-track opt-in watcher + per-app ignore list, via `i` to
      toggle the focused window's app
- [x] **M8** — Polish: menu bar dropdown mirrors every leader-modal action,
      plus three extras beyond the original plan — workspace-ID badges,
      a `v` reveal flash, and `f`/`c` focus mode

## Install

This repo's root *is* the Spoon (no `WindowMgmt.spoon/` subfolder) — clone
it directly into your Spoons directory, naming the local checkout
`WindowMgmt.spoon` (Hammerspoon matches on the local folder name, not the
git remote's name):

```sh
git clone https://github.com/TimboGP/hammerspoon-windowmanagement.git ~/.hammerspoon/Spoons/WindowMgmt.spoon
```

Or, if you keep a separate working copy elsewhere, symlink it in instead:

```sh
ln -s /path/to/your/clone ~/.hammerspoon/Spoons/WindowMgmt.spoon
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
- Workspace switching (from the leader modal): `1`-`9` switch to that slot,
  creating an empty "Workspace N" the first time a slot is used. `p` opens
  a picker (fuzzy-searchable) listing every workspace created so far. `n`
  prompts for a name and switches to (creating if needed) a named
  workspace. Switching hides the outgoing workspace's windows (minimize)
  and shows the incoming one's (unminimize + re-snap to its saved zones),
  restoring focus to whichever window was last focused in it. The menu bar
  shows the active workspace's name.
- Window swap (`x` from the leader modal): a big letter appears over every
  other window in the current workspace — press it to swap the focused
  window with that one. Or press an arrow key to swap with the nearest
  neighbor in that direction (must actually be on that side and overlap on
  the perpendicular axis, not just be geometrically closest). Both re-snap
  both windows into each other's exact zone.
- Save/load (`s` from the leader modal): `w` prompts for a name (defaulting
  to the current workspace's name) and saves it to
  `~/.hammerspoon/window-mgmt/workspaces/<name>.json` — one entry per slot,
  recording its zone, app bundle ID, and current window title (used later
  as a best-effort match hint, not a hard requirement). `l` opens a picker
  of saved workspace names; picking one hides the current workspace,
  launches each saved app (`hs.application.launchOrFocusByBundleID`), and
  polls for a window whose title contains the saved title, falling back to
  the first available window of that app (with an alert) if no title
  matches within ~8s. Slots with no saved app become empty placeholders.
- Arrangements (also under `s`): `a` prompts for a name and saves every
  currently-known workspace as a bundle — re-saving each member workspace's
  on-disk copy first, then writing
  `~/.hammerspoon/window-mgmt/arrangements/<name>.json` with the member
  list and which workspace was active. `shift+l` opens a picker of saved
  arrangements; loading one hides whatever's currently showing, then loads
  every member workspace (same app-launch + title-match flow as a single
  workspace load) — the arrangement's designated active workspace ends up
  visible, the rest are loaded and then immediately hidden. Workspaces
  within the loaded arrangement can still be switched between freely with
  the normal `1`-`9`/`p` switching.
- Auto-track (`i` from the leader modal): toggles whether the focused
  window's app is auto-tracked. While enabled for an app, any *new* window
  it opens is automatically added to whichever workspace is currently
  active (same logic as `g` `a`, just triggered by window creation instead
  of a keypress) via a `hs.window.filter` scoped to only auto-tracked apps
  (not a global filter watching every app, which is known to add
  noticeable lag). Apps on the default ignore list (Hammerspoon itself,
  Spotlight, system dialogs, etc. — see `config.lua`) can't be
  auto-tracked. The list persists to
  `~/.hammerspoon/window-mgmt/autotrack.json`. Manual `g` `a`/`g` `r`
  remains the default for everything else.
- Reveal (`v` from the leader modal): briefly flashes a bright border
  around every window in the current workspace, to see at a glance what's
  in it without needing to hunt for overlapping windows.
- Focus mode (`f`/`c` from the leader modal): pulls the focused window out
  of its workspace slot — leaving a labeled placeholder behind, just like
  `g` `r` — and resizes it to either fullscreen (`f`) or a centered
  rectangle (`c`). Press the same key again to restore it to its exact
  original slot (not just any empty slot). Only one window can be in focus
  mode at a time; entering focus mode on a different window first restores
  whatever was already focused.
- Menu bar: click the menu bar item for a dropdown mirroring the leader
  actions — switch workspace (with a checkmark on the active one), create
  a new workspace, save/load a workspace or arrangement, toggle auto-track
  for the focused app, and reload config.

## Troubleshooting

If the leader key alert appears but subsequent keys (`t`, `h`, etc.) don't
seem to register and instead leak through to whatever app is focused, check
for other global keyboard/automation tools that might be capturing the same
keys first — Karabiner-Elements, Raycast, Alfred, Rectangle, Magnet, or
similar. These don't necessarily conflict, but if something seems stuck,
try quitting them one at a time to isolate the culprit, or reassign this
Spoon's `leader`/tiling keys in `config.lua` and `tiling.lua` to combos
they don't use.

If the leader combo itself works (its alert shows) but *every* sub-action
key (`t`, `1`-`9`, `g`, etc.) silently fails or leaks through, check
**System Settings → Privacy & Security → Input Monitoring** and make sure
Hammerspoon is listed there and enabled (this is separate from
Accessibility). If you just added it, **fully restart macOS** — a simple
relaunch of Hammerspoon.app is not enough for this permission to take
effect; we hit exactly this failure mode during development and only a
full restart resolved it.

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
- Loading a saved workspace launches each app via
  `hs.application.launchOrFocusByBundleID`, which just starts the app
  normally — if that app has its own "show an Open panel / resume session
  picker on launch" preference (e.g. some TextEdit configurations), that
  dialog will appear and may need to be dismissed manually; this Spoon
  can't suppress another app's own launch behavior.
- A window in focus mode is unregistered from its origin workspace for as
  long as it's focused, so switching away from that workspace won't
  minimize it — it stays on screen, floating outside any workspace, until
  focus mode is exited (which restores it to its exact slot regardless of
  which workspace is currently active).

## Keybinding cheat-sheet

All actions below start with the leader key (`cmd+ctrl+alt+space` by
default), then the listed key(s):

| Key(s) | Action |
|---|---|
| `t` → preset/`g` | Tile focused window (halves/thirds/quarters/full/custom) |
| `g` → `a`/`r` | Add/remove focused window to/from the active workspace |
| `1`-`9` | Switch to workspace slot (creating an empty one if unused) |
| `p` | Picker: switch to any known workspace by name |
| `n` | Create a new named workspace |
| `x` → letter/arrow | Swap focused window with another (hint labels or directional) |
| `s` → `w`/`a`/`l`/`shift+l` | Save workspace / save arrangement / load workspace / load arrangement |
| `i` | Toggle auto-track for the focused window's app |
| `v` | Reveal: flash borders of every window in the active workspace |
| `f`/`c` | Toggle fullscreen/centered focus mode for the focused window |
| `esc` (in any sub-mode) | Cancel back out |
| `cmd+ctrl+alt+shift+esc` | Escape hatch: force-reset a stuck modal, always live |
