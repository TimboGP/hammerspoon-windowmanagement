local M = {}

local Workspace = nil
local overlay = nil
local gridLib = nil
local gridConfig = nil
local menubar = nil

local all = {}       -- name -> Workspace instance
local slotNames = {} -- 1..9 -> name
local currentName = nil

function M.start(config, workspaceClass, overlayModule, grid, menubarModule)
  Workspace = workspaceClass
  overlay = overlayModule
  gridLib = grid
  gridConfig = config.grid
  menubar = menubarModule
end

local function create(name)
  local ws = Workspace.new(name, overlay, gridLib, gridConfig)
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

function M.names()
  local result = {}
  for name in pairs(all) do
    table.insert(result, name)
  end
  table.sort(result)
  return result
end

return M
