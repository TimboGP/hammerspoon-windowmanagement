-- Wiggles the focused window via the vendored AnimFX Spoon, working even for
-- a window that's actively tiled/watched: pauses the owning workspace's
-- resettle watcher for the duration of the animation (so it doesn't fight
-- every intermediate frame), then restores the window to its exact slot.zone
-- and re-arms the watcher on completion - the same "pause, move, re-arm"
-- shape workspace.lua already uses for retile()/hide().
local M = {}

local AnimFX = nil
-- { win = hs.window, cancel = fn } for the in-flight wiggle, or nil. Only one
-- wiggle can run at a time (mirrors focus.lua's single-`state` pattern).
local current = nil

local DEFAULTS = { axis = "x", amplitude = 18, frequency = 6, duration = 0.45 }

local function isAlive(win)
  local ok, visible = pcall(function() return win:isVisible() ~= nil end)
  return ok and visible
end

local function startWiggle(workspaces, win, opts)
  if current then current.cancel() end -- interrupt any in-flight wiggle first (possibly on a different window)

  local ws = workspaces.current()
  local wasMember = ws ~= nil and ws:pauseWatch(win)
  local origFrame = win:frame()

  local merged = {}
  for k, v in pairs(DEFAULTS) do merged[k] = v end
  for k, v in pairs(opts or {}) do merged[k] = v end
  merged.onComplete = function(cancelled)
    current = nil
    if not isAlive(win) then
      return -- window closed mid-wiggle: nothing left to restore
    end
    if wasMember then
      ws:resumeWatch(win) -- re-snaps to slot.zone + re-arms the watcher
    else
      pcall(function() win:setFrame(origFrame) end) -- exact pre-wiggle frame, default animated glide
    end
  end

  local handle = AnimFX:wiggle(win, merged)
  current = { win = win, cancel = handle.cancel }
end

function M.start(config, AnimFX_, leaderModal, workspaces)
  AnimFX = AnimFX_
  local opts = config.wiggle or {}

  leaderModal:bind({}, "j", nil, function()
    leaderModal:exit()
    if opts.enabled == false then
      hs.alert.show("WM: wiggle is disabled (see menu bar)", 1.5)
      return
    end
    if not AnimFX then
      hs.alert.show("WM: AnimFX not installed (git submodule update --init)", 2)
      return
    end
    local win = hs.window.focusedWindow()
    if not win then
      hs.alert.show("WM: no focused window", 1)
      return
    end
    startWiggle(workspaces, win, opts)
  end)
end

-- Used by the global escape hatch and pause.lua to recover if a wiggle is
-- stuck in flight (e.g. Hammerspoon reload fired mid-animation).
function M.forceExit()
  if current then current.cancel() end
end

return M
