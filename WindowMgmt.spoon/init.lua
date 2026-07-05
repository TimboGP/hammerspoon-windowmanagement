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

  modal.start(self.config, {
    forceReset = function()
      tiling.forceExit()
      -- Later milestones hook overlay/canvas teardown in here too.
    end,
  })

  tiling.start(self.config, grid, modal.getInstance())

  return self
end

function obj:stop()
  tiling.stop()
  modal.stop()
  menubar.stop()
  return self
end

function obj:bindHotkeys(mapping)
  -- v1 uses the leader/escape-hatch combos from config.lua directly;
  -- per-action remapping will be layered on as milestones add real actions.
  return self
end

return obj
