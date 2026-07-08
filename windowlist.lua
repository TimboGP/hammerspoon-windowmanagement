local M = {}

local function windowEntries(ws)
  local entries = {}
  for i, slot in ipairs(ws.slots) do
    if slot.window then
      local win = slot.window
      local appName = win:application() and win:application():name() or "?"
      table.insert(entries, {
        text = appName .. " - " .. (win:title() or ""),
        subText = "slot " .. i,
        window = win,
      })
    end
  end
  return entries
end

-- Shows a chooser over the given workspace's member windows and invokes
-- onPick with the chosen hs.window. No-ops with an alert if the workspace
-- has nothing in it, rather than showing an empty chooser.
local function pickWindow(ws, placeholderText, onPick)
  local entries = windowEntries(ws)
  if #entries == 0 then
    hs.alert.show("WM: workspace '" .. ws.name .. "' has no windows", 1.5)
    return
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then
      onPick(choice.window)
    end
  end)
  chooser:placeholderText(placeholderText)
  chooser:choices(entries)
  chooser:show()
end

function M.start(config, leaderModal, workspaces, focus)
  local windowListModal = hs.hotkey.modal.new()

  function windowListModal:entered()
    hs.alert.show("Workspace windows: f focus, c pull out/center, r remove, esc cancel", 2.5)
  end

  local function withCurrentWorkspace(fn)
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
      return
    end
    fn(ws)
  end

  windowListModal:bind({}, "f", nil, function()
    windowListModal:exit()
    withCurrentWorkspace(function(ws)
      pickWindow(ws, "Focus which window?", function(win)
        win:focus()
      end)
    end)
  end)

  windowListModal:bind({}, "c", nil, function()
    windowListModal:exit()
    withCurrentWorkspace(function(ws)
      pickWindow(ws, "Pull out & center which window?", function(win)
        focus.pullOutAndCenter(workspaces, win)
      end)
    end)
  end)

  windowListModal:bind({}, "r", nil, function()
    windowListModal:exit()
    withCurrentWorkspace(function(ws)
      pickWindow(ws, "Remove which window from workspace?", function(win)
        ws:removeWindow(win)
        win:minimize()
        hs.alert.show("WM: removed from workspace '" .. ws.name .. "'", 1)
      end)
    end)
  end)

  windowListModal:bind({}, "escape", nil, function() windowListModal:exit() end)

  leaderModal:bind({}, "w", nil, function()
    leaderModal:exit()
    windowListModal:enter()
  end)

  M.windowListModal = windowListModal
  return M
end

-- Used by the global escape hatch to recover if this sub-modal gets stuck.
function M.forceExit()
  if M.windowListModal then M.windowListModal:exit() end
end

function M.stop()
  if M.windowListModal then
    M.windowListModal:exit()
    M.windowListModal:delete()
    M.windowListModal = nil
  end
end

return M
