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
git remote's name). The wiggle effect (see "Usage" below) is powered by
[hammerspoon-animfx](https://github.com/TimboGP/hammerspoon-animfx), vendored
here as a git submodule, so clone with `--recurse-submodules`:

```sh
git clone --recurse-submodules https://github.com/TimboGP/hammerspoon-windowmanagement.git ~/.hammerspoon/Spoons/WindowMgmt.spoon
```

For an existing checkout that didn't clone the submodule, or after pulling
a change that added/updated it:

```sh
git submodule update --init --recursive
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
  A window can belong to multiple workspaces at once — `a` never removes it
  from anywhere else it's already a member. Top-level `a` (no `g` first) is
  a shortcut for the same add action, and top-level `shift+p` adds the
  focused window to Playground and switches there in one step.
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
  the normal `1`-`9`/`p` switching. `d`/`shift+d` open a picker of saved
  workspaces/arrangements and, after a confirmation dialog, delete the
  picked one's on-disk JSON file. Deleting a workspace does not clean up
  any arrangement that still references it by name (loading that
  arrangement later will just alert that the member couldn't be found and
  continue with the rest); deleting an arrangement never touches its
  member workspaces.
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
- Window list (`w` from the leader modal): immediately shows every window in
  the active workspace in a chooser. Enter focuses the highlighted window;
  holding ⌘ or ⌥ while pressing Enter instead removes it from the workspace
  or pulls it out to focus mode (`c`), respectively — same underlying actions
  as focusing a window directly and pressing `f`/`c`/`g` `r`, just reachable
  without hunting for the window on screen first.
- Tab cycling (`tab` from the leader modal): cmd-tab-style cycling through
  every window in the active workspace, in the same stable slot order as the
  window list above. Each `tab` press immediately focuses the next window;
  `shift` `tab` goes to the previous one. Keep pressing `tab`/`shift` `tab`
  to keep cycling — `esc` (or the leader idle timeout) stops.
- Wiggle (`j` from the leader modal): shakes the focused window — a
  horizontal, decaying sinusoidal oscillation lasting under half a second —
  then returns it to exactly where it was. Works even on a tiled workspace
  member: the owning workspace's resettle watcher is paused for the
  animation's duration (so it doesn't fight it) and the window is re-snapped
  to its exact zone and the watcher re-armed afterward. Powered by the
  vendored [AnimFX](https://github.com/TimboGP/hammerspoon-animfx) Spoon; if
  that submodule isn't checked out, this alerts instead of erroring. Tunable
  via `config.wiggle` (axis/amplitude/frequency/duration), and can be
  switched off entirely via `config.wiggle.enabled` or the menu bar's
  "Enable Wiggle" checkbox — disabling only blocks new wiggles from
  starting, an in-flight one still finishes normally. Also triggerable from
  outside Hammerspoon via `hs -c "spoon.WindowMgmt:wiggleFocusedWindow()"` —
  same tiling-safe behavior as pressing `j` (returns `true`, or
  `false, "<reason>"` if disabled, no focused window, or AnimFX isn't
  installed).
- Window slide animation (workspace hide/show): when a workspace is hidden,
  its windows slide off a screen edge before being tucked away, and drop back
  in from the same edge when it's shown again. Powered by AnimFX's `slide`
  effect (same vendored Spoon as wiggle). **Only runs on the experimental
  virtual-display park path** (see below) — the default minimize path keeps its
  own Dock genie and is left un-animated, since double-animating a genie looks
  wrong. Tunable via `config.windowAnim` (`enabled`, `duration`, easing,
  `direction`) and the menu bar's "Window Animations" submenu. `direction` is
  the edge a window exits by (`"up"`/`"down"`/`"left"`/`"right"`, default
  `"up"`); it re-enters from the same edge. Set `followParkingDisplay = true`
  to instead derive the direction from where the parking display sits in the
  arrangement (and place that display directly above the main screen so
  "up/out" points at it).
- Menu bar: click the menu bar item for a dropdown mirroring the leader
  actions, grouped under headers (Workspaces / Save & Load / Settings) with
  the matching leader-key sequence shown next to each item — switch
  workspace (with a checkmark on the active one), create a new workspace,
  save/load/delete a workspace or arrangement, toggle auto-track for the
  focused app, toggle the wiggle hotkey on/off, and reload config. A "Window
  Animations" submenu toggles the hide/show slide, picks its exit direction,
  and switches on "Follow Parking Display Position". Also includes a
  "WindowMgmt Enabled" checkbox (see "Disabling the tool" below).

## Disabling the tool

`cmd+ctrl+alt+shift+space` (independent of the leader key, always live)
toggles the whole tool on/off, and the menu bar's "WindowMgmt Enabled"
checkbox does the same. Use this instead of quitting Hammerspoon when you
don't want tiling forced on someone — e.g. handing your laptop to someone
else, or screen-sharing — without losing your workspace layout or affecting
any other Hammerspoon config you run alongside this Spoon.

Disabling: force-resets any stuck sub-mode, stops auto-tracking new windows,
and stops the active workspace from re-snapping windows that drift out of
their zone (see "Known v1 limitations" below on why that exists at all).
Re-enabling only restarts auto-tracking — it deliberately does *not*
retroactively re-tile whatever's currently on screen, so nothing jumps the
moment you turn it back on; the next real tile/swap/workspace-switch
re-arms enforcement for whatever windows it touches.

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

- **Single monitor only** in the sense that a workspace's grid always maps
  onto whichever single screen its windows are actually on — there's no
  concept of tiling across two monitors at once with independent grids.
  Connecting/disconnecting a monitor (e.g. undocking a laptop) *is* handled:
  zones are stored as grid-relative fractions, not absolute pixels, so the
  active workspace's windows are automatically re-fit to whatever screen
  they land on after a display change (debounced ~1s after the last
  screen-configuration event, to avoid re-fitting mid-flicker while macOS is
  still settling the new arrangement).
- Some apps (observed: Slack, Outlook) asynchronously re-apply their own
  stale, self-remembered window bounds sometime after being unminimized or
  refocused — anywhere from a few seconds to over ten, especially after
  sitting minimized for a while. Rather than fight that with a fixed delay,
  the active workspace keeps an AX-level watcher on each window and
  re-snaps it whenever it drifts, for as long as the workspace stays shown.
  A side effect: while a window is a workspace member and its workspace is
  visible, manually dragging/resizing it will get snapped back too — pull
  it out via focus mode (`f`/`c`) first if you want to reposition it freely.
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
- Issuing a tiling/swap/retile command on a window while it's mid-wiggle
  races the two: both write to the window's frame until the wiggle's own
  completion re-snaps it to whatever zone it captured when it started,
  which may be stale if the other command changed the zone in the meantime.
  Wait for a wiggle to finish (well under half a second) before re-tiling
  the same window.
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

## Experimental: Virtual-Display Hide/Show

Off by default, opt-in via `config.virtualDisplay.enabled = true`. An
alternative to the minimize-based hide/show described above: instead of
minimizing a workspace's windows (which triggers the Dock genie/scale
animation on every switch — see "Known v1 limitations" above), this parks
them on a virtual display. A window inside any active display's bounds —
real or virtual — never loses occlusion, so revealing it on `show()` is
instant, with no animation.

**Requires a separate, sibling daemon: [`vdisplay-helper`](https://github.com/TimboGP/vdisplay-helper).**
This Spoon has no display-creation capability of its own — `hs.screen` can't
create a virtual display — so it talks to that daemon over a local Unix
socket (`~/.vdisplay-helper/vdisplay-helper.sock`) to create/find the display,
and does the actual window moves itself via `hs.window:moveToScreen`. Install
the daemon first (see that repo's README for `install.sh`, which builds it,
ad-hoc signs it, and loads it as a per-user `launchd` agent
`com.timbogp.vdisplay-helper`), then set the flag above and reload.

**Philosophical note:** this project deliberately avoids private/undocumented
macOS APIs elsewhere (that's why `hs.spaces` is rejected — see "Known v1
limitations"). This feature is a conscious, opt-in exception to that rule: the
daemon uses the private `CGVirtualDisplay` API, self-maintained rather than
depending on a paid third-party app, with the private-API surface isolated
entirely in the sibling repo rather than in this Spoon.

Known caveats:
- **Apple Silicon is the reliable target**; `CGVirtualDisplay`-based tools are
  known to be flaky on Intel Macs with some GPUs.
- **Private API risk**: could break on a future macOS update with no warning
  from Apple.
- The **first workspace switch** after enabling the feature (or after each
  Hammerspoon restart) still shows the old minimize animation once, before
  subsequent switches go silent — the virtual display's creation is
  kicked off in the background rather than blocking that first switch.
- If the `vdisplay-helper` daemon isn't installed/reachable, this Spoon
  degrades gracefully to the normal minimize-based behavior (with a one-time
  alert), never errors.
- The **window slide animation** (see "Usage" above) only plays on this park
  path — a window slides off a screen edge, *then* teleports to the parking
  display. The parking display is headless (rendered on no physical monitor),
  so the slide is a cosmetic motion on the real screen that ends in an instant
  teleport; you never literally watch a window arrive on the parking display,
  even with `followParkingDisplay` placing it directly above. Without the
  virtual display in use, hides fall back to minimize with no slide.
- Press `r` (leader modal) or use the menu bar's "Bring Back Parked Windows"
  to recover any parked windows across *every* workspace (not just the
  active one) — useful after the daemon restarts or the display is removed
  externally. This Spoon never destroys the virtual display automatically;
  on `:stop()`, if one is still attached, you'll be asked whether to remove
  it or leave it running (the daemon itself keeps running via `launchd`
  either way — only the display is in question).

## Keybinding cheat-sheet

All actions below start with the leader key (`cmd+ctrl+alt+space` by
default), then the listed key(s). Engaging the leader shows a condensed
version of this table as an on-screen alert, so you don't have to
memorize it up front.

| Key(s) | Action |
|---|---|
| `t` → preset/`g` | Tile focused window (halves/thirds/quarters/full/custom) |
| `g` → `a`/`r` | Add/remove focused window to/from the active workspace |
| `a` | Shortcut: add focused window to the active workspace (same as `g` → `a`) |
| `1`-`9` | Switch to workspace slot (creating an empty one if unused) |
| `p` | Picker: switch to any known workspace by name |
| `shift+p` | Add focused window to Playground and switch to it |
| `n` | Create a new named workspace |
| `x` → letter/arrow | Swap focused window with another (hint labels or directional) |
| `s` → `w`/`a`/`l`/`shift+l` | Save workspace / save arrangement / load workspace / load arrangement |
| `s` → `d`/`shift+d` | Delete a saved workspace / saved arrangement (with confirmation) |
| `i` | Toggle auto-track for the focused window's app |
| `v` | Reveal: flash borders of every window in the active workspace |
| `f`/`c` | Toggle fullscreen/centered focus mode for the focused window |
| `w` | List active workspace's windows; `enter`/`⌘enter`/`⌥enter` focuses/removes/pulls-out-center the picked one |
| `tab`/`shift+tab` | Cycle focus forward/backward through the active workspace's windows |
| `u` | Chooser: add an untracked/other-workspace window to the active workspace (keeps its other memberships) |
| `shift+u` | Park every untracked/other-workspace window (virtualDisplay park if enabled, else minimize) |
| `j` | Wiggle the focused window (works even while tiled) |
| `r` | Bring back any parked windows (experimental virtualDisplay strategy only) |
| `esc` (in any sub-mode) | Cancel back out |
| `cmd+ctrl+alt+shift+esc` | Escape hatch: force-reset a stuck modal, always live |
| `cmd+ctrl+alt+shift+space` | Toggle the whole tool on/off, always live (see "Disabling the tool") |
