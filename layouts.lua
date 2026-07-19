local M = {}

-- Pure zone math: partition the grid into n zones. All return grid-cell
-- {x0,y0,x1,y1} tables, same shape as grid.presetZones, so they compose with
-- everything downstream (retile, save, resnapAll) unchanged. Callers only
-- invoke these with n >= 1 (M.apply below returns early on an empty
-- workspace), so none of them need to guard against n == 0.

local function columns(g, n)
  local zones = {}
  local w = g.cols / n
  for i = 1, n do
    table.insert(zones, { x0 = (i - 1) * w, y0 = 0, x1 = i * w, y1 = g.rows })
  end
  return zones
end

local function rows(g, n)
  local zones = {}
  local h = g.rows / n
  for i = 1, n do
    table.insert(zones, { x0 = 0, y0 = (i - 1) * h, x1 = g.cols, y1 = i * h })
  end
  return zones
end

-- Slot 1 = left half (full height); the rest stack in equal rows on the
-- right. A single window just gets the full screen.
local function masterStack(g, n)
  if n <= 1 then
    return { { x0 = 0, y0 = 0, x1 = g.cols, y1 = g.rows } }
  end
  local zones = { { x0 = 0, y0 = 0, x1 = g.cols / 2, y1 = g.rows } }
  local stackH = g.rows / (n - 1)
  for i = 1, n - 1 do
    table.insert(zones, { x0 = g.cols / 2, y0 = (i - 1) * stackH, x1 = g.cols, y1 = i * stackH })
  end
  return zones
end

-- ceil(sqrt(n)) columns x however many rows that needs. A short last row
-- (n not a perfect square) gets its cells widened to fill the full width
-- rather than leaving a gap, so the result is always gapless.
local function gridNxM(g, n)
  local cols = math.ceil(math.sqrt(n))
  local rowCount = math.ceil(n / cols)
  local cellH = g.rows / rowCount
  local zones = {}
  for i = 1, n do
    local row = math.floor((i - 1) / cols)
    local colsInRow = math.min(cols, n - row * cols)
    local col = (i - 1) % cols
    local w = g.cols / colsInRow
    table.insert(zones, { x0 = col * w, y0 = row * cellH, x1 = (col + 1) * w, y1 = (row + 1) * cellH })
  end
  return zones
end

local LAYOUTS = { columns = columns, rows = rows, master = masterStack, grid = gridNxM }
local LAYOUT_KEYS = { c = "columns", r = "rows", m = "master", g = "grid" }

-- Remembers each workspace's most recently applied layout (by name, not
-- instance, so a rename doesn't need updating here) - purely so
-- "make focused window master" has something to re-apply; not persisted.
local lastLayoutByWorkspace = {}

-- Applies a layout to the active workspace's OCCUPIED slots, in slot order
-- (empty placeholder slots are left where they are - untouched, not part of
-- the new partition - so the *visible* result is gapless even though
-- ws.slots may still contain leftover empty entries at arbitrary indices).
function M.apply(ws, name)
  local occupied = {}
  for _, slot in ipairs(ws.slots) do
    if slot.window then table.insert(occupied, slot) end
  end
  if #occupied == 0 then
    hs.alert.show("WM: no windows in '" .. ws.name .. "' to lay out", 1.5)
    return
  end
  local zones = LAYOUTS[name](ws.gridConfig, #occupied)
  for i, slot in ipairs(occupied) do
    ws:retile(slot.window, zones[i])
  end
  lastLayoutByWorkspace[ws.name] = name
end

local function sameWin(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a:id() == b:id()
end

-- Re-orders the focused window's slot to the front of ws.slots (so it
-- becomes the "master"/first slot the ordering-sensitive layouts key off
-- of), then re-applies whichever layout this workspace last had (or
-- "master" if none yet, since that's the layout order actually matters for).
function M.makeMasterAndReapply(ws)
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("WM: no focused window", 1)
    return
  end
  if not ws:hasWindow(win) then
    hs.alert.show("WM: focused window isn't in this workspace", 1)
    return
  end
  for i, slot in ipairs(ws.slots) do
    if sameWin(slot.window, win) then
      table.remove(ws.slots, i)
      table.insert(ws.slots, 1, slot)
      break
    end
  end
  M.apply(ws, lastLayoutByWorkspace[ws.name] or "master")
end

function M.start(config, leaderModal, workspaces)
  local layoutsModal = hs.hotkey.modal.new()

  function layoutsModal:entered()
    hs.alert.show("Layout: c columns, r rows, m master-stack, g grid, shift+m make focused window master, esc cancel", 3)
  end

  local function applyCurrent(name)
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
      return
    end
    M.apply(ws, name)
  end

  for key, name in pairs(LAYOUT_KEYS) do
    layoutsModal:bind({}, key, nil, function()
      applyCurrent(name)
      layoutsModal:exit()
    end)
  end

  layoutsModal:bind({ "shift" }, "m", nil, function()
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
    else
      M.makeMasterAndReapply(ws)
    end
    layoutsModal:exit()
  end)

  layoutsModal:bind({}, "escape", nil, function() layoutsModal:exit() end)

  leaderModal:bind({}, "l", nil, function()
    leaderModal:exit()
    layoutsModal:enter()
  end)

  M.layoutsModal = layoutsModal
  return M
end

-- Force-exits the layouts sub-modal without destroying it; used by the
-- global escape hatch to recover from a stuck modal.
function M.forceExit()
  if M.layoutsModal then M.layoutsModal:exit() end
end

function M.stop()
  if M.layoutsModal then
    M.layoutsModal:exit()
    M.layoutsModal:delete()
    M.layoutsModal = nil
  end
end

return M
