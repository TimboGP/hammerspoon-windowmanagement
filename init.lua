--- === WindowMgmt ===
---
--- Keyboard-driven workspace/tiling window manager for a single-monitor macOS setup.
--- See the repo README for setup and the full design doc for architecture.

local obj = {}
obj.__index = obj

obj.name = "WindowMgmt"
obj.version = "0.1.0"
obj.author = "tboehm"
obj.license = "MIT"
obj.homepage = "https://github.com/TimboGP/hammerspoon-windowmanagement"

obj.spoonPath = hs.spoons.scriptPath()

local config = dofile(obj.spoonPath .. "config.lua")
local menubar = dofile(obj.spoonPath .. "menubar.lua")
local modal = dofile(obj.spoonPath .. "modal.lua")
local grid = dofile(obj.spoonPath .. "grid.lua")
local tiling = dofile(obj.spoonPath .. "tiling.lua")
local overlay = dofile(obj.spoonPath .. "overlay.lua")
local Workspace = dofile(obj.spoonPath .. "workspace.lua")
local workspaces = dofile(obj.spoonPath .. "workspaces.lua")
local membership = dofile(obj.spoonPath .. "membership.lua")
local switching = dofile(obj.spoonPath .. "switching.lua")
local swap = dofile(obj.spoonPath .. "swap.lua")
local persistence = dofile(obj.spoonPath .. "persistence.lua")
local matcher = dofile(obj.spoonPath .. "matcher.lua")
local saveload = dofile(obj.spoonPath .. "saveload.lua")
local ignore = dofile(obj.spoonPath .. "ignore.lua")
local watcher = dofile(obj.spoonPath .. "watcher.lua")
local autotrack = dofile(obj.spoonPath .. "autotrack.lua")
local reveal = dofile(obj.spoonPath .. "reveal.lua")
local focus = dofile(obj.spoonPath .. "focus.lua")
local windowlist = dofile(obj.spoonPath .. "windowlist.lua")
local virtualdisplay = dofile(obj.spoonPath .. "virtualdisplay.lua")
local pause = dofile(obj.spoonPath .. "pause.lua")
local wiggle = dofile(obj.spoonPath .. "wiggle.lua")

-- Vendored as a git submodule (vendor/AnimFX.spoon) rather than a second
-- hs.loadSpoon in the user's own init.lua, to keep this Spoon's "one clone"
-- install story intact. pcall'd so a checkout that forgot
-- `git submodule update --init` degrades to "wiggle hotkey shows an alert"
-- (see wiggle.lua) instead of breaking the whole Spoon's reload.
local animFXOk, AnimFX = pcall(dofile, obj.spoonPath .. "vendor/AnimFX.spoon/init.lua")
if not animFXOk then
  print("WindowMgmt: AnimFX submodule not available (" .. tostring(AnimFX) .. "); wiggle will be disabled")
  AnimFX = nil
end

local function checkAccessibility()
  if not hs.accessibilityState(false) then
    hs.alert.show("WindowMgmt: Accessibility permission required", 3)
    hs.accessibilityState(true) -- triggers the system prompt
    return false
  end
  return true
end

function obj:init()
  self.config = config
end

function obj:start()
  checkAccessibility()

  menubar.start(self.config)
  overlay.start(self.config, grid)

  -- Started early so persisted UI preferences (badge visibility, virtual-
  -- display toggle) are available before anything below might otherwise act
  -- on the config.lua defaults instead. Kept as an upvalue so the toggle
  -- callbacks further down can update and re-save it in place.
  persistence.start(self.config)
  local savedSettings = persistence.loadSettings()
  if savedSettings.badgesEnabled ~= nil then
    overlay.setBadgesEnabled(savedSettings.badgesEnabled)
  end
  if savedSettings.virtualDisplayEnabled ~= nil then
    self.config.virtualDisplay.enabled = savedSettings.virtualDisplayEnabled
  end

  -- Shared by the escape hatch (recovering a stuck modal) and pause.lua
  -- (leaving everything in a clean, neutral state when disabled).
  local function resetAllSubmodals()
    tiling.forceExit()
    membership.forceExit()
    swap.forceExit()
    saveload.forceExit()
    focus.forceExit()
    windowlist.forceExit()
    wiggle.forceExit()
  end

  modal.start(self.config, {
    forceReset = resetAllSubmodals,
    isPaused = pause.isPaused,
  })

  tiling.start(self.config, grid, modal.getInstance(), workspaces)

  virtualdisplay.start(self.config)
  workspaces.start(self.config, Workspace, overlay, grid, menubar, virtualdisplay, pause)
  membership.start(self.config, modal.getInstance(), workspaces)
  switching.start(self.config, modal.getInstance(), workspaces)
  swap.start(overlay, modal.getInstance(), workspaces)

  -- Global on/off switch, independent of the leader modal (see pause.lua) -
  -- disabling force-resets any stuck sub-modal, stops auto-tracking new
  -- windows, and stops the current workspace's resettle watchers so it
  -- immediately stops fighting anyone moving windows around; re-enabling
  -- only restarts auto-tracking; watchers re-arm naturally the next time
  -- something actually re-tiles or switches workspace, rather than
  -- retroactively snapping everything back the instant it's re-enabled.
  pause.start(self.config, {
    onDisabled = function()
      modal.getInstance():exit()
      resetAllSubmodals()
      watcher.stop()
      local cur = workspaces.current()
      if cur then cur:stopAllWatches() end
    end,
    onEnabled = function()
      watcher.refresh()
    end,
  })

  matcher.start(self.config)
  saveload.start(self.config, grid, overlay, persistence, matcher, modal.getInstance(), workspaces, virtualdisplay)

  ignore.start(self.config)
  watcher.start(self.config, ignore, workspaces)
  autotrack.start(self.config, ignore, watcher, modal.getInstance())

  reveal.start(self.config, overlay, modal.getInstance(), workspaces)
  focus.start(self.config, grid, modal.getInstance(), workspaces)
  windowlist.start(self.config, modal.getInstance(), workspaces, focus)

  if AnimFX then
    AnimFX:init()
    AnimFX:start()
  end
  wiggle.start(self.config, AnimFX, modal.getInstance(), workspaces)

  -- Explicit recovery for the experimental virtualDisplay hide strategy:
  -- brings back any parked windows across every workspace (not just the
  -- current one), e.g. after the vdisplay-helper daemon was restarted or the
  -- display removed externally. A no-op when the strategy isn't enabled.
  modal.getInstance():bind({}, "r", nil, function()
    workspaces.restoreAllParked()
    hs.alert.show("WM: restored any parked windows", 1.5)
  end)

  if self.config.virtualDisplay.enabled then
    virtualdisplay.ensureDisplay(function(screen, err)
      if screen then
        print("WindowMgmt: virtual display ready (" .. tostring(screen:name()) .. ")")
      else
        print("WindowMgmt: virtual display unavailable (" .. tostring(err) .. "); hide/show will use minimize")
      end
    end)
  end

  -- Flips the virtualDisplay strategy on/off for the rest of this session.
  -- hideConfig is the same table reference every Workspace instance holds
  -- (see workspaces.lua), so mutating self.config.virtualDisplay.enabled
  -- here takes effect immediately for every workspace, current and future,
  -- with no restart needed. Persisted via savedSettings so it also survives
  -- a reload; if the daemon isn't reachable next time, ensureDisplay's
  -- callback below still falls back to minimize as usual.
  local function toggleVirtualDisplay()
    local vd = self.config.virtualDisplay
    vd.enabled = not vd.enabled
    savedSettings.virtualDisplayEnabled = vd.enabled
    persistence.saveSettings(savedSettings)
    if vd.enabled then
      hs.alert.show("WM: virtual-display hide/show enabled", 1.5)
      virtualdisplay.ensureDisplay(function(screen, err)
        if screen then
          print("WindowMgmt: virtual display ready (" .. tostring(screen:name()) .. ")")
        else
          hs.alert.show("WM: vdisplay-helper unavailable (" .. tostring(err) .. "); falling back to minimize", 3)
        end
      end)
    else
      -- Bring back anything currently parked before dropping the strategy,
      -- so disabling it never strands windows off-screen on the virtual
      -- display with no obvious way to recover them.
      workspaces.restoreAllParked()
      hs.alert.show("WM: virtual-display hide/show disabled (using minimize)", 1.5)
    end
  end

  -- Section headers are plain disabled items (no native "menu section" concept
  -- in hs.menubar); grouped items are indented one level under their header
  -- so the grouping reads visually, not just by proximity. Shortcuts shown
  -- are informational text baked into the title - hs.menubar's `shortcut`
  -- field sets a real NSMenuItem key equivalent (single char + implied cmd),
  -- which would be actively wrong here since every action below is actually
  -- a multi-key leader sequence, not a standalone hotkey.
  local function header(title)
    return { title = title, disabled = true }
  end
  local function sep()
    return { title = "-" }
  end
  local function item(title, shortcut, opts)
    opts = opts or {}
    opts.title = shortcut and (title .. "   (" .. shortcut .. ")") or title
    if opts.indent == nil then
      opts.indent = 1
    end
    return opts
  end

  local function buildMenu()
    local cur = workspaces.current()
    local items = {
      { title = "Workspace: " .. (cur and cur.name or "none"), disabled = true },
      item("WindowMgmt Enabled", "\u{2318}\u{2303}\u{2325}\u{21e7}Space", {
        checked = pause.isEnabled(),
        fn = function() pause.setEnabled(not pause.isEnabled()) end,
        indent = 0,
      }),
      sep(),
      header("Workspaces  (1-9, leader p/n)"),
    }

    local names = workspaces.names()
    if #names > 0 then
      local switchItems = {}
      for _, name in ipairs(names) do
        table.insert(switchItems, {
          title = name,
          checked = cur and cur.name == name,
          fn = function() workspaces.switchTo(name) end,
        })
      end
      table.insert(items, item("Switch to", nil, { menu = switchItems }))
    end
    table.insert(items, item("New Workspace…", "n", { fn = switching.promptNewWorkspace }))

    table.insert(items, sep())
    table.insert(items, header("Save / Load  (leader s)"))
    table.insert(items, item("Save Workspace…", "w", { fn = saveload.promptSaveWorkspace }))
    table.insert(items, item("Save Workspace As New…", "\u{21e7}w", { fn = saveload.promptSaveAsNewWorkspace }))
    table.insert(items, item("Load Workspace…", "l", { fn = saveload.promptLoadWorkspace }))
    table.insert(items, item("Delete Workspace…", "d", { fn = saveload.promptDeleteWorkspace }))
    table.insert(items, item("Save Arrangement…", "a", { fn = saveload.promptSaveArrangement }))
    table.insert(items, item("Load Arrangement…", "\u{21e7}l", { fn = saveload.promptLoadArrangement }))
    table.insert(items, item("Delete Arrangement…", "\u{21e7}d", { fn = saveload.promptDeleteArrangement }))

    table.insert(items, sep())
    table.insert(items, header("Settings"))
    table.insert(items, item("Toggle Auto-track (focused app)", "leader i", { fn = autotrack.toggleFocusedApp }))
    table.insert(items, item("Show Workspace Badges", nil, {
      checked = overlay.badgesEnabled(),
      fn = function()
        local enabled = not overlay.badgesEnabled()
        overlay.setBadgesEnabled(enabled)
        savedSettings.badgesEnabled = enabled
        persistence.saveSettings(savedSettings)
      end,
    }))
    table.insert(items, item("Use Virtual Display for Hide/Show", nil, {
      checked = self.config.virtualDisplay.enabled,
      fn = toggleVirtualDisplay,
    }))
    if self.config.virtualDisplay.enabled then
      table.insert(items, item("Bring Back Parked Windows", "leader r", { fn = workspaces.restoreAllParked }))
    end

    table.insert(items, sep())
    table.insert(items, { title = "Reload Config", fn = function() hs.reload() end })

    return items
  end

  menubar.setMenu(buildMenu)

  return self
end

function obj:stop()
  if AnimFX then AnimFX:stop() end
  watcher.stop()
  workspaces.stop()
  saveload.stop()
  swap.stop()
  membership.stop()
  windowlist.stop()
  tiling.stop()
  modal.stop()
  menubar.stop()
  overlay.stop()

  -- The vdisplay-helper daemon and its virtual display are never destroyed
  -- automatically (they persist via launchd independently of this Spoon) -
  -- but leaving one attached without the user's knowledge would be
  -- surprising, so check for it here and ask. This check (and any resulting
  -- cleanup) is asynchronous and may complete after this function returns;
  -- nothing else in stop() depends on its result.
  if self.config.virtualDisplay.enabled then
    virtualdisplay.hasActiveDisplay(function(active)
      if active then
        workspaces.restoreAllParked()
        local choice = hs.dialog.blockAlert(
          "WindowMgmt: virtual display still attached",
          "A parked virtual display (vdisplay-helper) is still running. Remove it now, or leave it attached? The daemon keeps running via launchd either way.",
          "Remove", "Leave attached")
        if choice == "Remove" then
          virtualdisplay.removeDisplay(function() end)
        end
      end
      virtualdisplay.stop()
    end)
  else
    virtualdisplay.stop()
  end

  return self
end

function obj:bindHotkeys(mapping)
  -- v1 uses the leader/escape-hatch combos from config.lua directly;
  -- per-action remapping will be layered on as milestones add real actions.
  return self
end

return obj
