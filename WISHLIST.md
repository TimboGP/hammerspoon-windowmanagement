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
