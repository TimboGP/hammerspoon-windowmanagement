-- Slides workspace windows out (on hide) and in (on show) via the vendored
-- AnimFX Spoon's generic `slide` effect. Mirrors wiggle.lua's role: it owns
-- the AnimFX interaction and the direction/geometry math, while workspace.lua
-- owns the park/unpark + resettle-watcher bookkeeping in the completion
-- callbacks it hands in here.
--
-- Deliberately only ever used on the virtual-display *park* path. The minimize
-- fallback (parking off/unavailable) keeps its own Dock genie and gets no
-- slide - double-animating a genie looks wrong (see the menu-bar "Window
-- Animations" submenu, and config.lua's windowAnim comment).
local M = {}

local AnimFX = nil
local cfg = {}      -- config.windowAnim (same table reference init.lua mutates)
local active = {}   -- handle -> true, for forceExit()

local DEFAULTS = {
  enabled = true,
  duration = 0.28,
  easingOut = "inCubic",
  easingIn = "outCubic",
  direction = "up",
  followParkingDisplay = false,
}

local function opt(key)
  local v = cfg[key]
  if v == nil then return DEFAULTS[key] end
  return v
end

function M.start(config, AnimFX_)
  AnimFX = AnimFX_
  cfg = config.windowAnim or {}
end

-- True only when AnimFX is actually present and the master toggle is on -
-- callers treat a false here (or a nil return from slideOut/slideIn) as "do
-- the move synchronously, no animation".
function M.isEnabled()
  return AnimFX ~= nil and opt("enabled") ~= false
end

function M.followsParkingDisplay()
  return opt("followParkingDisplay") == true
end

-- Resolves the edge a window exits by. In follow-the-arrangement mode it's
-- derived from the parking display's centre relative to `screen` (so parking a
-- display placed above the main screen yields "up"); it falls back to the
-- fixed config direction if that mode is off or the parking screen isn't
-- resolvable.
local function resolveDirection(screen, parkScreen)
  if M.followsParkingDisplay() and screen and parkScreen then
    local a = screen:frame()
    local b = parkScreen:frame()
    local dx = (b.x + b.w / 2) - (a.x + a.w / 2)
    local dy = (b.y + b.h / 2) - (a.y + a.h / 2)
    if math.abs(dx) >= math.abs(dy) then
      return dx >= 0 and "right" or "left"
    end
    return dy >= 0 and "down" or "up"
  end
  return opt("direction") or "up"
end

-- (dx, dy) that carries `frame` fully off `screenFrame` past the given edge -
-- i.e. until the trailing edge of the window clears the screen boundary.
local function offScreenOffset(direction, screenFrame, frame)
  if direction == "down" then
    return 0, (screenFrame.y + screenFrame.h) - frame.y
  elseif direction == "left" then
    return -(frame.x - screenFrame.x + frame.w), 0
  elseif direction == "right" then
    return (screenFrame.x + screenFrame.w) - frame.x, 0
  end
  -- default "up": move up until the window's bottom edge passes the screen top
  return 0, -(frame.y - screenFrame.y + frame.h)
end

local function track(handle)
  if handle then active[handle] = true end
  return handle
end

-- Slides `win` off `screen` toward the resolved exit edge, then calls
-- onComplete(cancelled). onComplete fires with cancelled=true if the slide is
-- interrupted (e.g. the workspace is re-shown mid-hide) - the caller must NOT
-- park in that case. Returns the AnimFX handle, or nil if animation is off /
-- the window's frame can't be read (caller should then park synchronously).
function M.slideOut(win, screen, parkScreen, onComplete)
  if not M.isEnabled() then return nil end
  local ok, frame = pcall(function() return win:frame() end)
  if not ok or not frame then return nil end

  local dir = resolveDirection(screen, parkScreen)
  local dx, dy = offScreenOffset(dir, screen:frame(), frame)

  local handle
  handle = AnimFX:run("slide", win, {
    dx = dx,
    dy = dy,
    duration = opt("duration"),
    easing = opt("easingOut"),
    onComplete = function(cancelled)
      active[handle] = nil
      onComplete(cancelled)
    end,
  })
  return track(handle)
end

-- Positions `win` just off `screen`'s entry edge (at targetFrame's size), then
-- slides it into targetFrame, then calls onComplete(cancelled). The entry edge
-- is the same one slideOut used, so a window that left upward drops back down.
-- Returns nil (caller should snap synchronously) if animation is off or the
-- pre-position setFrame fails.
function M.slideIn(win, screen, targetFrame, parkScreen, onComplete)
  if not M.isEnabled() then return nil end

  local dir = resolveDirection(screen, parkScreen)
  local dx, dy = offScreenOffset(dir, screen:frame(), targetFrame)

  local startFrame = {
    x = targetFrame.x + dx,
    y = targetFrame.y + dy,
    w = targetFrame.w,
    h = targetFrame.h,
  }
  local ok = pcall(function() win:setFrame(startFrame, 0) end)
  if not ok then return nil end

  local handle
  handle = AnimFX:run("slide", win, {
    dx = -dx,
    dy = -dy,
    duration = opt("duration"),
    easing = opt("easingIn"),
    onComplete = function(cancelled)
      active[handle] = nil
      onComplete(cancelled)
    end,
  })
  return track(handle)
end

-- Cancels every in-flight slide (escape hatch / pause / reload recovery),
-- mirroring wiggle.forceExit. Cancelling fires each slide's onComplete with
-- cancelled=true, so callers skip their park/snap follow-up and windows are
-- left wherever they are mid-slide rather than yanked.
function M.forceExit()
  for handle in pairs(active) do
    pcall(handle.cancel)
  end
  active = {}
end

return M
