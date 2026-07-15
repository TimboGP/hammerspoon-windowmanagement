local M = {}

-- The chooser currently on screen, if any - kept so forceExit/stop can hide
-- it without needing a full hs.hotkey.modal (the chooser is already modal:
-- it captures keystrokes and Escape cancels it on its own).
local activeChooser = nil

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

-- The base view: immediately shows every window in the workspace. Enter
-- focuses the highlighted window; the modifier held at selection time picks
-- a different action instead (there's no per-row hotkey support in
-- hs.chooser, so this is the standard Hammerspoon way to get more than one
-- action out of a single chooser).
local function showWindowChooser(ws, workspaces, focus)
  local entries = windowEntries(ws)
  if #entries == 0 then
    hs.alert.show("WM: workspace '" .. ws.name .. "' has no windows", 1.5)
    return
  end

  hs.alert.show(
    "Workspace windows: \u{21b5} focus, \u{2318}\u{21b5} remove, \u{2325}\u{21b5} pull out/center, esc cancel",
    3)

  local chooser = hs.chooser.new(function(choice)
    activeChooser = nil
    if not choice then return end
    local mods = hs.eventtap.checkKeyboardModifiers()
    if mods.cmd then
      ws:removeWindow(choice.window)
      choice.window:minimize()
      hs.alert.show("WM: removed from workspace '" .. ws.name .. "'", 1)
    elseif mods.alt then
      focus.pullOutAndCenter(workspaces, choice.window)
    else
      choice.window:focus()
    end
  end)
  chooser:placeholderText("Workspace windows")
  chooser:choices(entries)
  activeChooser = chooser
  chooser:show()
end

function M.start(config, leaderModal, workspaces, focus)
  leaderModal:bind({}, "w", nil, function()
    leaderModal:exit()
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
      return
    end
    showWindowChooser(ws, workspaces, focus)
  end)
end

-- Used by the global escape hatch to recover if the chooser gets stuck.
function M.forceExit()
  if activeChooser then
    activeChooser:hide()
    activeChooser = nil
  end
end

function M.stop()
  M.forceExit()
end

return M
