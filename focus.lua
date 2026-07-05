local M = {}

local gridLib = nil
-- { ws = Workspace, slot = <exact slot table>, window = hs.window } or nil.
-- Only one window can be in focus mode at a time.
local state = nil

local function fullscreenZone(gridConfig)
  return { x0 = 0, y0 = 0, x1 = gridConfig.cols, y1 = gridConfig.rows }
end

local function centeredZone(gridConfig)
  local marginX, marginY = gridConfig.cols * 0.15, gridConfig.rows * 0.15
  return {
    x0 = marginX,
    y0 = marginY,
    x1 = gridConfig.cols - marginX,
    y1 = gridConfig.rows - marginY,
  }
end

local function enterFocus(workspaces, zoneFn)
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("WM: no focused window", 1)
    return
  end
  local ws = workspaces.current()
  if not ws or not ws:hasWindow(win) then
    hs.alert.show("WM: focused window isn't in the active workspace", 1.5)
    return
  end
  -- removeWindow leaves a placeholder in the origin slot and returns that
  -- exact slot table, which we hang onto so exiting focus mode can restore
  -- precisely there via refillSlot, rather than "any empty slot".
  local slot = ws:removeWindow(win)
  state = { ws = ws, slot = slot, window = win }
  gridLib.snapWindowToZone(win, ws.gridConfig, zoneFn(ws.gridConfig))
  hs.alert.show("WM: focus mode (press f or c again to exit)", 1.5)
end

local function exitFocus()
  if not state then
    return
  end
  local ws, slot, win = state.ws, state.slot, state.window
  state = nil
  ws:refillSlot(slot, win)
  hs.alert.show("WM: exited focus mode", 1)
end

function M.start(config, gridLib_, leaderModal, workspaces)
  gridLib = gridLib_

  leaderModal:bind({}, "f", nil, function()
    leaderModal:exit()
    if state then
      exitFocus()
    else
      enterFocus(workspaces, fullscreenZone)
    end
  end)

  leaderModal:bind({}, "c", nil, function()
    leaderModal:exit()
    if state then
      exitFocus()
    else
      enterFocus(workspaces, centeredZone)
    end
  end)
end

-- Used by the global escape hatch to recover if focus mode gets stuck.
function M.forceExit()
  exitFocus()
end

return M
