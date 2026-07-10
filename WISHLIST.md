# hammerspoon-window-mgmt wishlist

Features discussed and deliberately deferred rather than built. Preserved
here as concrete specs so they can be picked up without re-deriving the
design.

---

## ✅ Auto-load on start — IMPLEMENTED (as auto-load-*last-used*)

Implemented 2026-07-10. Rather than the originally-sketched fixed
config-name (`autoLoadArrangement = "WorkDay"`), it auto-loads whatever
workspace/arrangement you were last *in* — no per-machine name to hardcode,
it just resumes where you left off. Details:

- `config.autoLoadLast = true` (default on; set false to always boot empty).
- A `settings.lastLoaded = { kind, name }` pointer, updated whenever you
  load a workspace/arrangement, or save one *in place* (`s w` / `s a`) —
  deliberately not on "save as new" (`s shift+w`), which writes a duplicate
  you don't switch to.
- `saveload.lua` exposes non-interactive `M.loadWorkspaceByName` /
  `M.loadArrangementByName` / `M.loadLast(last)`; `init.lua` calls
  `saveload.loadLast(savedSettings.lastLoaded)` at the end of `start()`.
  The pointer is written through `savedSettings` in `init.lua` (single
  source of truth) so it can't be clobbered by the other settings toggles.

Still needs Hammerspoon itself set to launch at login (its own Preferences →
"Launch at login", or System Settings → General → Login Items) — out of
scope for this Spoon to configure.

Possible follow-ups if the "last used" default ever chafes:
- A menu-bar checkbox to toggle `autoLoadLast` live (like the wiggle/anim
  toggles), persisted in `settings.json`.
- A `config.autoLoadArrangement = "<name>"` override that pins a fixed
  arrangement regardless of last-used, for a deterministic boot layout.
- Track the *active workspace within* a loaded arrangement, so resuming an
  arrangement returns to the sub-workspace you last had focused rather than
  the arrangement's saved `activeWorkspace`.

---

## Public, externally-triggerable wiggle entry point

Discussed 2026-07-08, right after building the `j` wiggle hook
(`wiggle.lua`, backed by the vendored `vendor/AnimFX.spoon`): the sibling
Neovim plugin `animfx.nvim` should eventually be able to trigger a wiggle
on the current window from outside Hammerspoon entirely — e.g. shaking the
terminal window on a failed build. See `animfx.nvim`'s own `WISHLIST.md`
for the Neovim-side half of this.

Today `wiggle.lua`'s actual animate/pause/restore logic (`startWiggle`) is
a local function, reachable only via the `j` hotkey closure bound in
`M.start` — `workspaces` and the default `opts` are captured there as
closure locals, not stored as module state, so nothing outside that
closure can call it. To make it externally triggerable (e.g. via `hs -c`
from a Neovim job, see the other repo's wishlist entry) without losing the
tiling-aware pause/resume behavior that's the whole point of this module,
promote `workspaces`/`opts` to the same kind of module-level local `AnimFX`
already is, and extract the hotkey body into a public function both the
hotkey and external callers can use:

```lua
-- wiggle.lua: promote to module-level locals (alongside the existing `AnimFX`)
local workspacesRef, defaultOpts

function M.wiggleWindow(win, opts)
  if not AnimFX then return false, "AnimFX not installed" end
  if not win then return false, "no window" end
  startWiggle(workspacesRef, win, opts or defaultOpts)
  return true
end

function M.start(config, AnimFX_, leaderModal, workspaces)
  AnimFX = AnimFX_
  workspacesRef = workspaces
  defaultOpts = config.wiggle or {}

  leaderModal:bind({}, "j", nil, function()
    leaderModal:exit()
    local ok, err = M.wiggleWindow(hs.window.focusedWindow())
    if not ok then hs.alert.show("WM: " .. err, err == "no window" and 1 or 2) end
  end)
end
```

```lua
-- init.lua: expose it on the Spoon object itself, not just the internal module
function obj:wiggleFocusedWindow(opts)
  return wiggle.wiggleWindow(hs.window.focusedWindow(), opts)
end
```

That lets an external caller do `hs -c "spoon.WindowMgmt:wiggleFocusedWindow()"`
(no arguments needed for the common case: whatever window currently has OS
focus) and get the exact same tiling-safe behavior as pressing `j` by hand.

---

# Roadmap (planned, in priority order)

Specs below were laid out 2026-07-10 as the intended next sequence. The
first five are "next up"; the two under **Deferred** are lower priority and
gated behind the ones above them.

---

## 1. Named layouts

Today tiling is one-window-at-a-time: `t` + a preset key snaps *the focused
window* into a zone (`tiling.lua` → `snap()` → `ws:retile(win, zone)` for a
member, else `grid.snapWindowToZone`). There's no "arrange everything in
this workspace at once." Named layouts add that: one command computes a zone
per member and re-snaps them all.

Everything needed already exists:

- Zones are `{x0,y0,x1,y1}` in grid-cell units (`grid.lua`), so a layout is
  just a function `(gridConfig, n) -> { zone, zone, ... }`.
- `Workspace.slots` is an *ordered* list of `{ window, zone, ... }`, so slot
  order is a natural, stable "which window is master / first."
- `ws:retile(window, newZone)` is the exact hook: it sets `slot.zone`, marks
  the workspace dirty, and re-points the resettle watcher at the new frame
  (so the watcher doesn't immediately fight the change). Applying a layout is
  just a loop of `retile` calls — no new placement plumbing.

New module `layouts.lua`:

```lua
-- Pure zone math: partition the grid into n zones. All return grid-cell
-- {x0,y0,x1,y1} tables, same shape as grid.presetZones, so they compose with
-- everything downstream (snap, save, resnapAll) unchanged.
local function columns(g, n) ... end        -- n equal vertical strips
local function rows(g, n) ... end            -- n equal horizontal strips
local function masterStack(g, n) ... end     -- slot 1 = left master, rest stacked right
local function gridNxM(g, n) ... end         -- ceil(sqrt(n)) cols x rows

local LAYOUTS = { columns=columns, rows=rows, master=masterStack, grid=gridNxM }

-- Applies a layout to the active workspace's OCCUPIED slots in slot order
-- (empty placeholder slots are skipped; optionally compact them first).
function M.apply(ws, name)
  local occupied = {}
  for _, slot in ipairs(ws.slots) do
    if slot.window then table.insert(occupied, slot) end
  end
  local zones = LAYOUTS[name](ws.gridConfig, #occupied)
  for i, slot in ipairs(occupied) do
    ws:retile(slot.window, zones[i])
  end
end
```

Binding: leader `l` is free at the top level (`l` is only used *inside* the
save sub-mode, a different modal), so add a layout sub-mode on leader `l` —
`c` columns, `r` rows, `m` master-stack, `g` grid — plus a menu-bar
"Layout" submenu mirroring it. A "make focused window the master" key
(re-orders it to slot 1, then re-applies) is a nice extra.

Edge cases / notes:

- Operate on **members only**; a non-member focused window is untouched
  (add it via `g a` first). Empty slots either skipped or compacted — pick
  compaction so the layout is gapless.
- `retile` already handles the resettle watcher and dirty flag, so save,
  `resnapAll`, hide/show, and the wiggle-pause dance all keep working.
- Don't apply a layout to a window mid-wiggle (same race noted in the README).
- **Bridge to later specs:** if a workspace remembers its chosen layout name,
  `addWindow`/auto-track could re-apply the layout on every new window
  (dynamic tiling), and the rule engine (#2) could name a layout as an action.

---

## 2. Rule engine for improved auto-tracking

Auto-track today is binary per app: `ignore.lua` holds a flat
`bundleID -> true` set (persisted as a plain list in `autotrack.json`), and
`watcher.lua`'s `windowCreated` handler always does
`workspaces.current():addWindow(win)` — i.e. *every* new window of a tracked
app lands in *whatever workspace is active*, in the first empty/new slot.
There's no way to say "Slack always goes to the Comms workspace, docked
right." A rule engine generalizes the flat list into match→action rules.

Rule shape:

```lua
{
  match  = { bundleID = "com.tinyspeck.slackmacgap", titlePattern = nil },
  action = {
    workspace = "Comms",     -- target workspace name; nil = current (today's behavior)
    zone      = "halfRight",  -- preset name or explicit {x0,y0,x1,y1}; nil = addWindow default
    layout    = nil,          -- optional: re-apply this named layout after adding (ties to #1)
  },
}
```

Storage & migration (`ignore.lua` → rules): keep reading the **old flat
list** for back-compat — a bare string entry becomes a rule with
`match.bundleID = <string>` and an empty action (= current workspace,
default placement = exactly today's behavior). New entries are full rule
tables. Duck-type on entry type (string vs table), or bump to a
`{ version = 2, rules = {...} }` envelope.

`watcher.lua` changes:

- `rebuildFilter` scopes the `hs.window.filter` to the **union of all rule
  bundle IDs** (keep the existing "never use the global filter — it lags"
  note). Read bundle IDs from the rules list instead of `ignore.enabledList()`.
- `windowCreated` handler: find the first rule matching the created window
  (bundleID, then optional `titlePattern` via `string.find`), resolve the
  target workspace (`workspaces.get(name)`, register if missing; `nil` →
  `current()`), `ws:addWindow(win)`, then if `action.zone` is set
  `ws:retile(win, resolveZone(action.zone))`, and if `action.layout` set
  `layouts.apply(ws, action.layout)`.

UI:

- `i` stays the quick path: "track focused app → current workspace, default
  placement" (creates the simplest possible rule), matching today's muscle
  memory.
- Add a richer capture — e.g. `shift+i` or a menu item "Auto-track focused
  app → *this* workspace, *here*" — that snapshots the focused window's
  current workspace name + current zone into a rule's action.

Key edge cases:

- **Target workspace isn't the active one.** `addWindow` snaps the window
  on-screen and arms its watcher, but a hidden workspace's windows should be
  hidden. So when `target ~= current()`, add then immediately hide that one
  window the same way the workspace hides its members (minimize, or park via
  `virtualDisplay` if enabled). Otherwise a Slack window pops onto the wrong
  workspace's screen.
- Keep refusing rules for `config.defaultIgnoreList` apps (as `ignore.toggle`
  does now).
- First-match-wins ordering; document it, and let the `shift+i` capture
  prepend (more specific rules first).

---

## 3. Undo

"No undo for tiling/swap actions" is a listed v1 limitation. Add a bounded,
per-workspace undo stack over **zone changes** (tile, swap, layout, focus-mode
pull/restore) — the actions that only move/resize members within a workspace.

Approach: **snapshot**, not command/inverse (simpler, and robust against the
async re-snap paths). Before any zone-mutating action, capture the active
workspace's occupied slots as `{ windowId = win:id(), zone = copyOf(slot.zone) }`.
Undo restores each captured zone via `ws:retile(win, zone)` (re-resolving
`windowId` to the live slot), which correctly re-arms the resettle watcher —
the same reason layouts (#1) use `retile`.

```lua
-- history.lua
local stacks = {}   -- workspaceName -> { undo = {...snapshots}, redo = {...} }
local LIMIT = 20

local function snapshot(ws)
  local s = {}
  for _, slot in ipairs(ws.slots) do
    if slot.window then
      s[#s+1] = { id = slot.window:id(), zone = { x0=slot.zone.x0, y0=slot.zone.y0,
                                                  x1=slot.zone.x1, y1=slot.zone.y1 } }
    end
  end
  return s
end

function M.push(ws) ... end   -- snapshot ws onto its undo stack (bounded), clear its redo
function M.undo(ws) ... end   -- pop undo -> push current onto redo -> restore via ws:retile
function M.redo(ws) ... end
```

Wire `history.push(workspaces.current())` in at each mutation chokepoint —
`tiling.snap`, `swap`'s apply, `layouts.apply`, `focus` enter/exit — *before*
they change zones. Bind leader `u` (free) = undo, `shift+u` = redo, operating
on `workspaces.current()`.

Scope decisions:

- **Per-workspace** stacks (undo affects the workspace you're in; switching
  workspaces switches which history is live). Keyed by workspace name;
  rename must move the key (`workspaces.rename` is the one place to hook).
- **Zone-only to start.** Membership add/remove (which minimizes windows) and
  cross-display moves are trickier to invert — note them as a follow-up, not
  v1 of undo.
- Don't snapshot/restore a window mid-wiggle (the README's race).
- Undo is in-memory only (not persisted across reloads) — that's fine; it
  mirrors editor-style session undo.

---

## 4. Status output interface

For external status bars (sketchybar, Übersicht, etc.), emit the workspace
state that today only reaches the menu bar. `workspaces.refreshStatus()` is
already the single chokepoint that recomputes "current name + dirty" on every
switch/activate/rename/dirty-flip and pushes it to `menubar.setStatus` — so it
just needs a second sink.

New module `status.lua`:

```lua
-- Atomically writes the current state to config.statusFile (reuse
-- persistence.lua's temp-file-then-rename trick), debounced so a burst of
-- switches doesn't thrash the disk. Optionally shells out a trigger command
-- (e.g. `sketchybar --trigger window_mgmt_update`) for push-based bars.
function M.publish(state) ... end
```

State payload:

```json
{
  "workspace": "Comms",
  "dirty": true,
  "workspaces": ["Comms", "Dev", "Mail"],
  "memberCount": 4,
  "enabled": true,
  "loaded": { "kind": "arrangement", "name": "WorkDay" }
}
```

Wiring: have `workspaces.refreshStatus()` also build this payload and call
`status.publish` (inject `status` as a dep, or an `onStatusChange` callback
like the existing `onDirtyChange`). Also publish on pause enable/disable
(`pause.lua`'s `onEnabled`/`onDisabled`) and on arrangement load. `enabled`
comes from `pause.isEnabled()`, `loaded` from `settings.lastLoaded` (now that
it's tracked, see the implemented auto-load entry above).

Config: `statusFile` path (default under `storageDir`), optional
`statusCommand` string. Note the debounce — switches can come in quick
succession.

This is the **read** half; the scripting interface (#5) is the **write** half.
Together they make the tool addressable by other tools.

---

## 5. General scripting interface

`obj:wiggleFocusedWindow()` (implemented above) is the template: a thin public
method on the Spoon object that an external process drives via
`hs -c "spoon.WindowMgmt:..."`, returning `(ok, err)` so a script can detect
failure without relying on the visual alert. Generalize that into a coherent
public API mirroring the leader/menu actions.

Target surface (all `(ok, err)` or a queried value):

```lua
obj:switchWorkspace(name)        -- workspaces.switchTo
obj:switchWorkspaceSlot(n)       -- workspaces.switchToSlot
obj:loadWorkspace(name)          -- saveload.loadWorkspaceByName   (already public)
obj:loadArrangement(name)        -- saveload.loadArrangementByName (already public)
obj:saveWorkspace(name)          -- needs a non-interactive save (see below)
obj:addFocusedWindow()           -- membership add
obj:removeFocusedWindow()        -- membership remove
obj:tileFocused(preset)          -- tiling snap by preset name
obj:applyLayout(name)            -- layouts.apply (ties to #1)
obj:currentWorkspace()           -- query: returns name (nil if none)
obj:listWorkspaces()             -- query: returns names
obj:setEnabled(bool)             -- pause.setEnabled
```

The refactor is the same one the wiggle entry required: several actions
currently live *inside modal-closure bodies* (membership's `a`/`r`,
tiling's `snap`) or behind `hs.dialog` prompts (`saveload.promptSave*`).
Promote the action core to a public module function, then bind the hotkey
*and* the `obj:` method to it. For the prompting saves, factor the core save
(`saveWorkspaceNamed` + `markClean` + `recordLastUsed`) out from the dialog so
a name can be passed programmatically.

Transport:

- `hs -c` (built-in, already used for wiggle) covers fire-and-forget commands
  and, via `hs.ipc`, can return values for the query methods.
- For structured / high-frequency callers (Neovim, Raycast, Stream Deck), add
  a single dispatcher `obj:command(jsonString)` that parses `{action, args}`
  and routes to the methods above — one entry point is far easier to call over
  a socket than a dozen. Pair it with the status output (#4) as the read side.

Contract: document that actions needing a focused window / GUI context return
`false, "<reason>"` (as wiggle does), and that dialog-driven flows aren't
scriptable until their non-interactive cores are extracted.

---

# Deferred (lower priority)

Gated behind the five above — do these after, in this order.

---

## 6. Turn the latest specs into meaningful tests

~4,000 lines of Lua, no test harness. Before (and while) the more complex
specs above land — especially the rule engine (#2), layouts (#1), and undo
(#3), which are the branch-heavy ones — stand up automated tests so they
don't become regression whack-a-mole. "Latest spec into meaningful tests":
as each new spec is built, its logic ships with tests.

Approach:

- Runner: **`busted`**. CI on GitHub Actions, Linux — no macOS needed for the
  pure/mocked layer.
- Every module is a plain `local M = {} ... return M` that references the
  global `hs`, so a test can set a **mock `hs` global** before loading the
  module under test and exercise it in isolation.
- **Start with the pure wins** (no `hs` needed at all): `grid.lua` zone math
  (`frameToZone ∘ zoneToFrame` ≈ identity on grid lines; `presetZones`
  correctness), `layouts.lua` partitioning (n zones, gapless, no overlap,
  covers the grid), rule matching (bundleID + `titlePattern` precedence,
  legacy flat-list migration), the undo stack (bounds, restore correctness),
  and rules/ignore persistence (against a temp dir / mock `hs.fs` + `hs.json`).
- **Then a fake-window layer**: `Workspace` only needs `gridLib.snapWindowToZone`
  (mockable to record calls), a no-op `overlay`, and fake window objects with
  `:id()/:frame()/:screen()/:setFrame()/:newWatcher()`. That makes
  `addWindow`/`removeWindow`/`retile`/`refillSlot`/swap logic unit-testable.
- Leave the genuinely-live behaviors (reload, real minimize/park, AX resettle,
  `hs.window.filter` timing) to a short **manual smoke checklist** — they
  can't be meaningfully unit-tested and shouldn't be faked into false
  confidence.

---

## 7. Multi-monitor

The declared #1 v1 limitation: a workspace's grid maps onto whichever single
screen its windows happen to be on; there's no concept of independent
per-display grids or of workspaces intentionally spanning/binding displays.
This is the "v2 tentpole" — do it **after the test harness (#6)** so the
data-model change rests on something solid.

What already helps: zones are grid-relative fractions (`grid.lua`), so they're
resolution-independent; `snapWindowToZone` snaps to *the window's current
screen*, so a window on monitor B already tiles within B; and the
`hs.screen.watcher` → `resnapAll` path already re-fits the current workspace on
connect/disconnect. What's missing is *intentional* cross-display placement
and per-display state.

Data-model change (the crux):

- A slot gains a **stable screen identity**: `slot.screenUUID`
  (`hs.screen:getUUID()`, stable across reconnects). `zone` stays
  grid-relative, now relative to *that* screen.
- On show / `resnapAll`, resolve `screenUUID` → live `hs.screen`, falling back
  to main if that display is absent (generalizes today's "re-fit to whatever
  screen it lands on" — the undock case).
- **Migration**: existing saved slots have no `screenUUID` → treat as
  main/current screen, so old workspaces and arrangements load unchanged
  (bump the saveload format, keep the reader back-compat, same way the rule
  engine keeps the flat auto-track list working).

New actions: "throw focused window to next/prev display" (re-assign
`slot.screenUUID`, re-snap into that screen's grid). Tiling presets already
operate within the window's current screen, so they need little change.

Scope decision to make up front: default to a workspace that **spans** all
connected displays (each member lives on whichever screen its slot names) —
the natural extension of today's model. A stricter "one workspace per display"
mode is a bigger philosophical shift; defer it within this defer.

Hardest parts to design carefully: hide/show and focus restoration across
displays (minimize is per-window so fine; `virtualDisplay` parking already
moves windows across screens), and the saveload format bump. The
per-window resettle watcher is already per-window, so it's unaffected.
