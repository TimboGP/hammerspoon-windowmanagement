-- A panic button, independent of workspaces/tiling entirely: when things
-- have gotten visually lost (windows minimized, hidden, parked on an
-- offscreen/virtual display, or just scattered), this puts every window on
-- the system back somewhere findable. Deliberately system-wide rather than
-- scoped to tracked windows - the point is recovering from a mess, not
-- respecting workspace membership.
local M = {}

local WIDTH, HEIGHT = 1280, 720 -- 720p
local CASCADE_STEP = 30 -- px offset per window, so corners/title bars peek out

-- Matches workspace.lua's UNMINIMIZE_ANIMATION_DELAY: unminimize() kicks off
-- the Dock's genie animation asynchronously at the OS level, and a
-- setFrame() issued before it settles is known to be silently dropped.
-- hs.application:unhide() plausibly has the same async-settle risk, so this
-- one delay is used to cover both before the placement pass runs.
local UNMINIMIZE_ANIMATION_DELAY = 0.35

local function unhideAllApps()
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:isHidden() then
      app:unhide()
    end
  end
end

-- Moves every window to the main screen, resizes it to a fixed 1280x720,
-- and cascades it from the screen's center - offset wraps back toward
-- center (rather than running off-screen) once it would no longer fit.
local function placeAll()
  local screen = hs.screen.primaryScreen()
  local frame = screen:frame()
  local baseX = frame.x + (frame.w - WIDTH) / 2
  local baseY = frame.y + (frame.h - HEIGHT) / 2
  local maxSteps = math.max(1, math.min(
    math.floor((frame.w - WIDTH) / CASCADE_STEP),
    math.floor((frame.h - HEIGHT) / CASCADE_STEP)
  ))

  local i = 0
  for _, win in ipairs(hs.window.allWindows()) do
    if win:screen() ~= screen then
      win:moveToScreen(screen, true, false, 0)
    end
    local offset = (i % maxSteps) * CASCADE_STEP
    win:setFrame({ x = baseX + offset, y = baseY + offset, w = WIDTH, h = HEIGHT })
    i = i + 1
  end
  hs.alert.show("WM: emergency restore complete (" .. i .. " window(s))", 1.5)
end

-- Disables window management first (stops resettle watchers, cancels
-- in-flight slides, un-parks anything on the virtual display - see
-- pause.lua's onDisabled), so nothing fights the placement pass below.
-- Then unhides every hidden app and unminimizes every minimized window,
-- and once their animations have had a moment to settle, moves/resizes/
-- cascades literally every window on the system.
function M.restoreAll(pause)
  if pause then pause.setEnabled(false) end

  hs.alert.show("WM: emergency restore in progress...", 2)
  unhideAllApps()

  local hadMinimized = false
  for _, win in ipairs(hs.window.allWindows()) do
    if win:isMinimized() then
      win:unminimize()
      hadMinimized = true
    end
  end

  if hadMinimized then
    hs.timer.doAfter(UNMINIMIZE_ANIMATION_DELAY, placeAll)
  else
    placeAll()
  end
end

-- Bound directly via hs.hotkey.bind (like pause.lua's own hotkey and
-- modal.lua's escape hatch), so it always works regardless of the leader
-- modal's state, pause state, or anything else that might be stuck -
-- that's the entire point of an emergency action.
function M.start(config, pause)
  hs.hotkey.bind(config.emergencyRestoreHotkey[1], config.emergencyRestoreHotkey[2], function()
    M.restoreAll(pause)
  end)
end

return M
