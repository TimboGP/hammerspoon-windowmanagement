local M = {}

local rulesRef, watcherRef, workspacesRef = nil, nil, nil

function M.toggleFocusedApp()
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("WM: no focused window", 1)
    return
  end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if not bundleID then
    hs.alert.show("WM: could not determine app", 1)
    return
  end
  local nowEnabled, err = rulesRef.toggle(bundleID)
  if err then
    hs.alert.show("WM: " .. err, 1.5)
    return
  end
  watcherRef.refresh()
  local appName = app:name() or bundleID
  hs.alert.show("WM: auto-track " .. (nowEnabled and "enabled" or "disabled") .. " for " .. appName, 1.5)
end

local function sameWin(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a:id() == b:id()
end

local function zoneOf(ws, win)
  for _, slot in ipairs(ws.slots) do
    if slot.window and sameWin(slot.window, win) then return slot.zone end
  end
  return nil
end

-- Richer capture: snapshots the focused window's app, its current
-- workspace, and its current zone (nil if it isn't a tiled member) into a
-- rule, prepended so first-match-wins tries it before any plain `i` rule
-- for the same app. New windows of this app land pre-placed in this
-- workspace from now on, instead of wherever happens to be active.
function M.captureFocusedApp()
  local win = hs.window.focusedWindow()
  if not win then
    hs.alert.show("WM: no focused window", 1)
    return
  end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if not bundleID then
    hs.alert.show("WM: could not determine app", 1)
    return
  end
  local ws = workspacesRef.current()
  if not ws then
    hs.alert.show("WM: no active workspace", 1)
    return
  end
  local rule = {
    match = { bundleID = bundleID },
    action = { workspace = ws.name, zone = zoneOf(ws, win) },
  }
  local ok, err = rulesRef.addRule(rule, true)
  if not ok then
    hs.alert.show("WM: " .. err, 1.5)
    return
  end
  watcherRef.refresh()
  local appName = app:name() or bundleID
  hs.alert.show("WM: new " .. appName .. " windows will auto-track to '" .. ws.name .. "'", 2)
end

function M.start(config, rules, watcher, workspaces, leaderModal)
  rulesRef, watcherRef, workspacesRef = rules, watcher, workspaces

  leaderModal:bind({}, "i", nil, function()
    leaderModal:exit()
    M.toggleFocusedApp()
  end)

  leaderModal:bind({ "shift" }, "g", nil, function()
    leaderModal:exit()
    M.captureFocusedApp()
  end)
end

return M
