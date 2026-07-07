local M = {}

local HINT_LETTERS = "asdfghjklqwertyuiopzxcvbnm"

local function overlapsRange(a0, a1, b0, b1)
  return a0 < b1 and b0 < a1
end

-- Finds the nearest occupied slot in `direction` from `fromSlot`, requiring
-- the candidate to actually be on that side (not just closer) and to
-- overlap on the perpendicular axis, so it feels like a spatial neighbor
-- rather than "whichever slot happens to be nearest by raw distance".
local function findNeighbor(workspace, fromSlot, direction)
  local best, bestDist = nil, math.huge
  local f = fromSlot.zone
  for _, slot in ipairs(workspace.slots) do
    if slot ~= fromSlot and slot.window then
      local z = slot.zone
      local ok, dist = false, nil
      if direction == "left" and z.x1 <= f.x0 and overlapsRange(z.y0, z.y1, f.y0, f.y1) then
        ok, dist = true, f.x0 - z.x1
      elseif direction == "right" and z.x0 >= f.x1 and overlapsRange(z.y0, z.y1, f.y0, f.y1) then
        ok, dist = true, z.x0 - f.x1
      elseif direction == "up" and z.y1 <= f.y0 and overlapsRange(z.x0, z.x1, f.x0, f.x1) then
        ok, dist = true, f.y0 - z.y1
      elseif direction == "down" and z.y0 >= f.y1 and overlapsRange(z.x0, z.x1, f.x0, f.x1) then
        ok, dist = true, z.y0 - f.y1
      end
      if ok and dist < bestDist then
        best, bestDist = slot, dist
      end
    end
  end
  return best
end

local function swapSlots(gridLib, gridConfig, slotA, slotB)
  slotA.window, slotB.window = slotB.window, slotA.window
  gridLib.snapWindowToZone(slotA.window, gridConfig, slotA.zone)
  gridLib.snapWindowToZone(slotB.window, gridConfig, slotB.zone)
end

local function findFocusedSlot(ws)
  local win = hs.window.focusedWindow()
  if not win then
    return nil, nil
  end
  for _, slot in ipairs(ws.slots) do
    -- Compare by :id(), not ==: hs.window.focusedWindow() returns a distinct
    -- userdata from whatever query originally populated slot.window, even
    -- for the same real window (see workspace.lua's sameWindow).
    if slot.window and slot.window:id() == win:id() then
      return slot, win
    end
  end
  return nil, win
end

function M.start(config, gridLib, overlay, leaderModal, workspaces)
  local swapModal = hs.hotkey.modal.new()
  local activeLetters = nil -- letter -> slot, populated on entry

  local function clearHints()
    if activeLetters then
      for letter in pairs(activeLetters) do
        overlay.hideHint("swap:" .. letter)
      end
    end
    activeLetters = nil
  end

  function swapModal:entered()
    hs.alert.show("Swap: arrows for a neighbor, or a letter for any window, esc cancel", 2)
    local ws = workspaces.current()
    if not ws then
      return
    end
    local focusedSlot = findFocusedSlot(ws)
    activeLetters = {}
    local i = 1
    for _, slot in ipairs(ws.slots) do
      if slot.window and slot ~= focusedSlot then
        local letter = HINT_LETTERS:sub(i, i)
        if letter == "" then
          break
        end
        i = i + 1
        activeLetters[letter] = slot
        overlay.showHint("swap:" .. letter, slot.window:screen(), slot.zone, letter:upper())
      end
    end
  end

  function swapModal:exited()
    clearHints()
  end

  for letter in HINT_LETTERS:gmatch(".") do
    swapModal:bind({}, letter, nil, function()
      local ws = workspaces.current()
      local focusedSlot = ws and findFocusedSlot(ws)
      local target = activeLetters and activeLetters[letter]
      if focusedSlot and target then
        swapSlots(gridLib, config.grid, focusedSlot, target)
        hs.alert.show("WM: swapped", 1)
      end
      swapModal:exit()
    end)
  end

  local function bindDirection(key, direction)
    swapModal:bind({}, key, nil, function()
      local ws = workspaces.current()
      local focusedSlot = ws and findFocusedSlot(ws)
      if not focusedSlot then
        hs.alert.show("WM: focused window isn't in this workspace", 1)
        swapModal:exit()
        return
      end
      local target = findNeighbor(ws, focusedSlot, direction)
      if target then
        swapSlots(gridLib, config.grid, focusedSlot, target)
        hs.alert.show("WM: swapped " .. direction, 1)
      else
        hs.alert.show("WM: no neighbor to the " .. direction, 1)
      end
      swapModal:exit()
    end)
  end

  bindDirection("left", "left")
  bindDirection("right", "right")
  bindDirection("up", "up")
  bindDirection("down", "down")

  swapModal:bind({}, "escape", nil, function() swapModal:exit() end)

  leaderModal:bind({}, "x", nil, function()
    leaderModal:exit()
    swapModal:enter()
  end)

  M.swapModal = swapModal
  return M
end

-- Force-exits the swap sub-modal (also clearing hint overlays via its own
-- :exited() handler) without destroying it; used by the global escape hatch.
function M.forceExit()
  if M.swapModal then M.swapModal:exit() end
end

function M.stop()
  if M.swapModal then
    M.swapModal:exit()
    M.swapModal:delete()
    M.swapModal = nil
  end
end

return M
