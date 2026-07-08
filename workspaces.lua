local M = {}

local Workspace = nil
local overlay = nil
local gridLib = nil
local gridConfig = nil
local menubar = nil
local hideConfig = nil
local virtualDisplay = nil
local pause = nil

local all = {}       -- name -> Workspace instance
local slotNames = {} -- 1..9 -> name
local currentName = nil

local screenWatcher = nil
local rescreenTimer = nil
-- Debounced so a single physical connect/disconnect (which macOS reports as
-- a burst of several screen-change notifications while it settles) only
-- triggers one re-fit instead of several redundant ones.
local RESCREEN_DEBOUNCE = 1.0

function M.start(config, workspaceClass, overlayModule, grid, menubarModule, virtualDisplayModule, pauseModule)
  Workspace = workspaceClass
  overlay = overlayModule
  gridLib = grid
  gridConfig = config.grid
  menubar = menubarModule
  hideConfig = config.virtualDisplay
  virtualDisplay = virtualDisplayModule
  pause = pauseModule

  -- Zones are grid-relative fractions of a screen, not absolute pixels, so
  -- they're already resolution-independent - but nothing recomputes them
  -- against the *current* screen when a monitor is connected/disconnected
  -- mid-session (only the current, visible workspace needs this; a hidden
  -- one's windows are minimized and get fit fresh whenever it's next shown).
  -- Skipped while paused, matching the "hands off entirely" contract of
  -- pause.lua - reconnecting a monitor shouldn't retile someone else's
  -- windows on a laptop the user deliberately disabled tiling on.
  screenWatcher = hs.screen.watcher.new(function()
    if rescreenTimer then rescreenTimer:stop() end
    rescreenTimer = hs.timer.doAfter(RESCREEN_DEBOUNCE, function()
      rescreenTimer = nil
      if pause and not pause.isEnabled() then return end
      local cur = M.current()
      if cur then cur:resnapAll() end
    end)
  end)
  screenWatcher:start()
end

function M.stop()
  if screenWatcher then
    screenWatcher:stop()
    screenWatcher = nil
  end
  if rescreenTimer then
    rescreenTimer:stop()
    rescreenTimer = nil
  end
end

local function create(name)
  local ws = Workspace.new(name, overlay, gridLib, gridConfig, hideConfig, virtualDisplay)
  all[name] = ws
  return ws
end

-- Creates and registers an empty workspace without touching current/show,
-- for callers (e.g. async load) that need to populate slots incrementally
-- before it's actually shown.
M.register = create

function M.current()
  return currentName and all[currentName]
end

function M.get(name)
  return all[name]
end

-- Hides the current workspace, if any, without changing which one is
-- "current" - used to hide the outgoing workspace immediately when a load
-- starts, ahead of the (async) target workspace being ready to show.
function M.hideCurrent()
  local cur = M.current()
  if cur then
    cur:hide()
  end
end

-- Makes an already-registered workspace current and shows it, without
-- hiding anything first (the caller is expected to have already hidden
-- the outgoing workspace via hideCurrent, e.g. before an async load).
function M.activate(name)
  currentName = name
  local target = all[name]
  if target then
    target:show()
  end
  if menubar then
    menubar.setStatus(name)
  end
  return target
end

-- Hides the current workspace (if any) and shows the target, creating it
-- empty if this is the first time it's been switched to.
function M.switchTo(name)
  if name == currentName then
    return M.current()
  end
  if not all[name] then
    create(name)
  end
  M.hideCurrent()
  return M.activate(name)
end

function M.switchToSlot(slotNumber)
  local name = slotNames[slotNumber]
  if not name then
    name = "Workspace " .. slotNumber
    slotNames[slotNumber] = name
  end
  return M.switchTo(name)
end

-- Renames an already-registered workspace in place - keeps it the same
-- Workspace instance (same slots/windows) under a new key, updating
-- currentName/slotNames so nothing still points at the old name. Used by
-- "save workspace" when the user gives it a different name, so that saving
-- updates the workspace's identity instead of leaving a second, separately-
-- tracked workspace behind.
function M.rename(oldName, newName)
  if oldName == newName then
    return true
  end
  local ws = all[oldName]
  if not ws then
    return false, "no such workspace '" .. oldName .. "'"
  end
  if all[newName] then
    return false, "a workspace named '" .. newName .. "' already exists"
  end
  ws:rename(newName)
  all[newName] = ws
  all[oldName] = nil
  if currentName == oldName then
    currentName = newName
  end
  for slotNumber, name in pairs(slotNames) do
    if name == oldName then
      slotNames[slotNumber] = newName
    end
  end
  if menubar and currentName == newName then
    menubar.setStatus(newName)
  end
  return true
end

function M.names()
  local result = {}
  for name in pairs(all) do
    table.insert(result, name)
  end
  table.sort(result)
  return result
end

-- Restores any parked windows across every workspace, including hidden/
-- inactive ones - the explicit recovery path for the virtualDisplay hide
-- strategy, since a killed daemon or externally-removed display can leave
-- parked windows stranded without ever switching through their workspace.
function M.restoreAllParked()
  for _, name in ipairs(M.names()) do
    local ws = all[name]
    if ws then
      ws:restoreParkedWindows()
    end
  end
end

return M
