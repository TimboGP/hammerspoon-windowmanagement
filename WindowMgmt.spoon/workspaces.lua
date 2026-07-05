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

function M.current()
  return currentName and all[currentName]
end

-- Hides the current workspace (if any) and shows the target, creating it
-- empty if this is the first time it's been switched to.
function M.switchTo(name)
  if name == currentName then
    return M.current()
  end
  local target = all[name] or create(name)
  local cur = M.current()
  if cur then
    cur:hide()
  end
  currentName = name
  target:show()
  if menubar then
    menubar.setStatus(name)
  end
  return target
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
