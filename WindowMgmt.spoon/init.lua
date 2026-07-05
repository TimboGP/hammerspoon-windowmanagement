--- === WindowMgmt ===
---
--- Keyboard-driven workspace/tiling window manager for a single-monitor macOS setup.
--- See the repo README for setup and the full design doc for architecture.

local obj = {}
obj.__index = obj

obj.name = "WindowMgmt"
obj.version = "0.1"
obj.author = "tboehm"
obj.license = "MIT"
obj.homepage = "https://github.com/tboehm/hammerspoon-window-mgmt"

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

  modal.start(self.config, {
    forceReset = function()
      tiling.forceExit()
      membership.forceExit()
      swap.forceExit()
      saveload.forceExit()
    end,
  })

  tiling.start(self.config, grid, modal.getInstance())

  workspaces.start(self.config, Workspace, overlay, grid, menubar)
  membership.start(self.config, modal.getInstance(), workspaces)
  switching.start(self.config, modal.getInstance(), workspaces)
  swap.start(self.config, grid, overlay, modal.getInstance(), workspaces)

  persistence.start(self.config)
  matcher.start(self.config)
  saveload.start(self.config, grid, overlay, persistence, matcher, modal.getInstance(), workspaces)

  ignore.start(self.config)
  watcher.start(self.config, ignore, workspaces)
  autotrack.start(self.config, ignore, watcher, modal.getInstance())

  return self
end

function obj:stop()
  watcher.stop()
  saveload.stop()
  swap.stop()
  membership.stop()
  tiling.stop()
  modal.stop()
  menubar.stop()
  overlay.stop()
  return self
end

function obj:bindHotkeys(mapping)
  -- v1 uses the leader/escape-hatch combos from config.lua directly;
  -- per-action remapping will be layered on as milestones add real actions.
  return self
end

return obj
