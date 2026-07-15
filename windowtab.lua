local M = {}

-- Tap-to-advance cycling through the current workspace's windows, in stable
-- slot order (same order shown in windowlist.lua). Unlike macOS's held-
-- modifier cmd+tab, each Tab press here immediately focuses the next window
-- rather than just previewing it - fits this Spoon's existing modal pattern
-- (leader -> sub-modal -> escape/leader-exit to stop) instead of needing a
-- low-level eventtap on modifier release.

local function sameWindow(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a:id() == b:id()
end

local function orderedWindows(ws)
  local wins = {}
  for _, slot in ipairs(ws.slots) do
    if slot.window then
      table.insert(wins, slot.window)
    end
  end
  return wins
end

local function indexOf(wins, win)
  for i, w in ipairs(wins) do
    if sameWindow(w, win) then return i end
  end
  return nil
end

local function describe(win)
  local appName = win:application() and win:application():name() or "?"
  return appName .. " - " .. (win:title() or "")
end

function M.start(config, leaderModal, workspaces)
  local windowTabModal = hs.hotkey.modal.new()

  -- Live only while windowTabModal is entered: { wins = {hs.window,...},
  -- index = <position in wins currently focused> }.
  local cycle = nil

  local function step(delta)
    if not cycle or #cycle.wins == 0 then return end
    local n = #cycle.wins
    cycle.index = ((cycle.index - 1 + delta) % n) + 1
    local win = cycle.wins[cycle.index]
    win:focus()
    hs.alert.show("WM: " .. describe(win) .. "  (" .. cycle.index .. "/" .. n .. ")", 1)
  end

  function windowTabModal:entered()
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
      windowTabModal:exit()
      return
    end
    local wins = orderedWindows(ws)
    if #wins == 0 then
      hs.alert.show("WM: workspace '" .. ws.name .. "' has no windows", 1.5)
      windowTabModal:exit()
      return
    end
    local focused = hs.window.focusedWindow()
    -- Starting index defaults to the last slot so the first Tab press below
    -- lands on slot 1 (wrapping), matching "Tab moves to the next window"
    -- when nothing in the workspace is currently focused.
    local startIndex = (focused and indexOf(wins, focused)) or #wins
    cycle = { wins = wins, index = startIndex }
    hs.alert.show("WM: tab through windows - tab next, \u{21e7}tab prev, esc done", 2)
    step(1)
  end

  function windowTabModal:exited()
    cycle = nil
  end

  windowTabModal:bind({}, "tab", nil, function() step(1) end)
  windowTabModal:bind({ "shift" }, "tab", nil, function() step(-1) end)
  windowTabModal:bind({}, "escape", nil, function() windowTabModal:exit() end)

  leaderModal:bind({}, "tab", nil, function()
    leaderModal:exit()
    windowTabModal:enter()
  end)

  M.windowTabModal = windowTabModal
  return M
end

-- Used by the global escape hatch to recover if this sub-modal gets stuck.
function M.forceExit()
  if M.windowTabModal then M.windowTabModal:exit() end
end

function M.stop()
  if M.windowTabModal then
    M.windowTabModal:exit()
    M.windowTabModal:delete()
    M.windowTabModal = nil
  end
end

return M
