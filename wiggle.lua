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

-- Set by M.start; module-level (like AnimFX above) so M.wiggleWindow is
-- reachable from outside the leaderModal hotkey closure below, e.g. from an
-- external `hs -c` caller via obj:wiggleFocusedWindow in init.lua.
local workspacesRef = nil
local defaultOpts = {}

local DEFAULTS = { axis = "x", amplitude = 18, frequency = 6, duration = 0.45 }

-- Per-error-string alert duration, preserved exactly from the original
-- inline hotkey checks below.
local ALERT_DURATIONS = {
  ["wiggle is disabled (see menu bar)"] = 1.5,
  ["no focused window"] = 1,
}

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

-- Public entry point for wiggling a specific window, used by both the `j`
-- hotkey below and external callers (e.g. `hs -c
-- "spoon.WindowMgmt:wiggleFocusedWindow()"`, see obj:wiggleFocusedWindow in
-- init.lua). Returns `ok, err` rather than alerting directly, so a scripted
-- caller can inspect failure instead of just seeing a Hammerspoon alert flash
-- by. Preserves the original hotkey's exact check order (disabled -> AnimFX
-- missing -> no focused window), since reordering would silently change
-- which alert wins when multiple conditions are true at once.
function M.wiggleWindow(win, opts)
  opts = opts or defaultOpts
  if opts.enabled == false then
    return false, "wiggle is disabled (see menu bar)"
  end
  if not AnimFX then
    return false, "AnimFX not installed (git submodule update --init)"
  end
  if not win then
    return false, "no focused window"
  end
  startWiggle(workspacesRef, win, opts)
  return true
end

function M.start(config, AnimFX_, leaderModal, workspaces)
  AnimFX = AnimFX_
  workspacesRef = workspaces
  defaultOpts = config.wiggle or {}

  leaderModal:bind({}, "j", nil, function()
    leaderModal:exit()
    local ok, err = M.wiggleWindow(hs.window.focusedWindow())
    if not ok then
      hs.alert.show("WM: " .. err, ALERT_DURATIONS[err] or 2)
    end
  end)
end

-- Used by the global escape hatch and pause.lua to recover if a wiggle is
-- stuck in flight (e.g. Hammerspoon reload fired mid-animation).
function M.forceExit()
  if current then current.cancel() end
end

return M
