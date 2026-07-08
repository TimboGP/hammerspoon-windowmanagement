local M = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(v, hi)) end

function M.start(config, gridLib, leaderModal, workspaces)
  local presets = gridLib.presetZones(config.grid)

  -- Routes through the workspace's retile() when the window is a member, so
  -- workspace.lua's resettle watcher (which otherwise fights any frame
  -- change as unwanted drift) re-points at this new zone instead of
  -- immediately snapping the window back to its old one.
  local function snap(zone)
    local win = hs.window.focusedWindow()
    if not win then
      hs.alert.show("WM: no focused window", 1)
      return
    end
    local ws = workspaces.current()
    if ws and ws:hasWindow(win) then
      ws:retile(win, zone)
    else
      gridLib.snapWindowToZone(win, config.grid, zone)
    end
  end

  local tilingModal = hs.hotkey.modal.new()
  local selectModal = hs.hotkey.modal.new()
  local selection = nil

  function tilingModal:entered()
    hs.alert.show(
      "Tiling: h/l/k/j halves - 1/2/3 thirds - 4/5 two-thirds - y/u/b/n quarters - f full - g custom - esc cancel",
      3)
  end

  local presetBindings = {
    h = presets.halfLeft,      l = presets.halfRight,
    k = presets.halfTop,       j = presets.halfBottom,
    ["1"] = presets.thirdLeft, ["2"] = presets.thirdCenter, ["3"] = presets.thirdRight,
    ["4"] = presets.twoThirdsLeft, ["5"] = presets.twoThirdsRight,
    y = presets.quarterTL,     u = presets.quarterTR,
    b = presets.quarterBL,     n = presets.quarterBR,
    f = presets.full,
  }

  for key, zone in pairs(presetBindings) do
    tilingModal:bind({}, key, nil, function()
      snap(zone)
      tilingModal:exit()
    end)
  end

  tilingModal:bind({}, "escape", nil, function() tilingModal:exit() end)

  tilingModal:bind({}, "g", nil, function()
    tilingModal:exit()
    -- Default selection: left half, a reasonable size to grow/shrink from
    -- rather than starting at a single cell.
    selection = { x0 = 0, y0 = 0, x1 = config.grid.cols / 2, y1 = config.grid.rows }
    selectModal:enter()
  end)

  local function announceSelection()
    hs.alert.closeAll(0)
    hs.alert.show(string.format(
      "Custom zone: cols %g-%g, rows %g-%g  (hjkl grow, shift+hjkl move start corner, enter confirm, esc cancel)",
      selection.x0, selection.x1, selection.y0, selection.y1), 1.5)
  end

  function selectModal:entered()
    announceSelection()
  end

  selectModal:bind({}, "l", nil, function()
    selection.x1 = clamp(selection.x1 + 1, selection.x0 + 1, config.grid.cols); announceSelection()
  end)
  selectModal:bind({}, "h", nil, function()
    selection.x1 = clamp(selection.x1 - 1, selection.x0 + 1, config.grid.cols); announceSelection()
  end)
  selectModal:bind({}, "j", nil, function()
    selection.y1 = clamp(selection.y1 + 1, selection.y0 + 1, config.grid.rows); announceSelection()
  end)
  selectModal:bind({}, "k", nil, function()
    selection.y1 = clamp(selection.y1 - 1, selection.y0 + 1, config.grid.rows); announceSelection()
  end)

  selectModal:bind({ "shift" }, "l", nil, function()
    selection.x0 = clamp(selection.x0 + 1, 0, selection.x1 - 1); announceSelection()
  end)
  selectModal:bind({ "shift" }, "h", nil, function()
    selection.x0 = clamp(selection.x0 - 1, 0, selection.x1 - 1); announceSelection()
  end)
  selectModal:bind({ "shift" }, "j", nil, function()
    selection.y0 = clamp(selection.y0 + 1, 0, selection.y1 - 1); announceSelection()
  end)
  selectModal:bind({ "shift" }, "k", nil, function()
    selection.y0 = clamp(selection.y0 - 1, 0, selection.y1 - 1); announceSelection()
  end)

  selectModal:bind({}, "return", nil, function()
    snap(selection)
    selectModal:exit()
  end)
  selectModal:bind({}, "escape", nil, function() selectModal:exit() end)

  leaderModal:bind({}, "t", nil, function()
    leaderModal:exit()
    tilingModal:enter()
  end)

  M.tilingModal = tilingModal
  M.selectModal = selectModal
  return M
end

-- Force-exits any nested tiling state without destroying the modal objects;
-- used by the global escape hatch to recover from a stuck modal.
function M.forceExit()
  if M.tilingModal then M.tilingModal:exit() end
  if M.selectModal then M.selectModal:exit() end
end

function M.stop()
  if M.tilingModal then
    M.tilingModal:exit()
    M.tilingModal:delete()
    M.tilingModal = nil
  end
  if M.selectModal then
    M.selectModal:exit()
    M.selectModal:delete()
    M.selectModal = nil
  end
end

return M
