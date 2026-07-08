# hammerspoon-window-mgmt wishlist

Features discussed and deliberately deferred rather than built. Preserved
here as concrete specs so they can be picked up without re-deriving the
design.

---

## Auto-load a default arrangement on start

Right now `spoon.WindowMgmt:start()` always comes up empty — no workspace
or arrangement is active until you explicitly load one via `s` `shift+L`
(or the menu bar). Discussed 2026-07-06 and parked: the save/load flow
(`persistence.lua`, `saveload.lua`) already does everything needed; this
would just be a config-driven auto-load at startup for a "boots straight
into my layout" experience.

Sketch:

```lua
-- config.lua: add a field, nil by default (opt-in)
autoLoadArrangement = nil, -- e.g. "WorkDay"
```

```lua
-- init.lua, at the end of obj:start(), after saveload.start(...):
if self.config.autoLoadArrangement then
  saveload.loadArrangementByName(self.config.autoLoadArrangement)
end
```

`saveload.promptLoadArrangement` is interactive (opens a chooser), so this
needs a non-interactive entry point — `loadArrangementByName` already
exists in `saveload.lua` but is a local function; just expose it as
`M.loadArrangementByName` alongside the other public prompt functions.

Also needs Hammerspoon itself set to launch at login (Hammerspoon's own
menu bar → Preferences → "Launch at login", or System Settings → General
→ Login Items) - not currently enabled, and out of scope for this Spoon
to configure.

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
