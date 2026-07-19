local M = {}

local config = nil
local blocked = {} -- bundleID -> true, apps excluded from tracking/pulling anywhere

local function isDefaultIgnored(bundleID)
  for _, id in ipairs(config.defaultIgnoreList) do
    if id == bundleID then
      return true
    end
  end
  return false
end

local function persist()
  local list = {}
  for bundleID in pairs(blocked) do
    table.insert(list, bundleID)
  end
  table.sort(list)
  hs.json.write(list, config.blockListFile, true, true)
end

function M.isBlocked(bundleID)
  return blocked[bundleID] == true
end

-- Refuses toggling apps already on config.defaultIgnoreList - those are
-- already permanently excluded, so blocking them here would be redundant
-- (mirrors ignore.lua's M.toggle refusing the same apps for the opposite
-- reason).
function M.toggle(bundleID)
  if isDefaultIgnored(bundleID) then
    return false, "this app is already excluded by default"
  end
  if blocked[bundleID] then
    blocked[bundleID] = nil
  else
    blocked[bundleID] = true
  end
  persist()
  return blocked[bundleID] == true
end

function M.blockedList()
  local list = {}
  for bundleID in pairs(blocked) do
    table.insert(list, bundleID)
  end
  table.sort(list)
  return list
end

-- Toggles the focused window's app on the block-list. If this newly blocks
-- an app that's currently auto-track-enabled (ignore.lua's allow-list),
-- also force auto-track off for it and refreshes watcher.lua's window
-- filter - otherwise a stale auto-track entry would keep tracking new
-- windows of an app that's supposed to be blocked everywhere.
local function toggleFocusedApp(ignoreModule, watcherModule)
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
  local nowBlocked, err = M.toggle(bundleID)
  if err then
    hs.alert.show("WM: " .. err, 1.5)
    return
  end
  if nowBlocked and ignoreModule.isEnabled(bundleID) then
    ignoreModule.toggle(bundleID)
    watcherModule.refresh()
  end
  local appName = app:name() or bundleID
  hs.alert.show("WM: " .. (nowBlocked and "blocked" or "unblocked") .. " " .. appName, 1.5)
end

function M.start(cfg, leaderModal, ignoreModule, watcherModule)
  config = cfg
  if hs.fs.attributes(config.blockListFile) then
    local data = hs.json.read(config.blockListFile)
    if data then
      for _, bundleID in ipairs(data) do
        blocked[bundleID] = true
      end
    end
  end

  leaderModal:bind({ "shift" }, "i", nil, function()
    leaderModal:exit()
    toggleFocusedApp(ignoreModule, watcherModule)
  end)

  return M
end

return M
