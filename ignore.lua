local M = {}

local config = nil
local blocklist = nil -- blocklist module, or nil
local enabled = {} -- bundleID -> true, apps opted into auto-track

local function isDefaultIgnored(bundleID)
  for _, id in ipairs(config.defaultIgnoreList) do
    if id == bundleID then
      return true
    end
  end
  return false
end

function M.start(cfg, blocklistModule)
  config = cfg
  blocklist = blocklistModule
  if hs.fs.attributes(config.autoTrackFile) then
    local data = hs.json.read(config.autoTrackFile)
    if data then
      for _, bundleID in ipairs(data) do
        enabled[bundleID] = true
      end
    end
  end
end

local function persist()
  local list = {}
  for bundleID in pairs(enabled) do
    table.insert(list, bundleID)
  end
  table.sort(list)
  hs.json.write(list, config.autoTrackFile, true, true)
end

function M.isEnabled(bundleID)
  return enabled[bundleID] == true
end

-- Returns (nowEnabled, error). Refuses to auto-track apps on the default
-- ignore list (Hammerspoon itself, system UI, etc.) - toggling those would
-- be actively harmful, not just pointless - or apps on the user's own
-- persisted block-list (blocklist.lua), which exists specifically to keep
-- an app out of auto-track (among other places) without a config-file edit.
function M.toggle(bundleID)
  if isDefaultIgnored(bundleID) then
    return false, "this app is never auto-trackable"
  end
  if blocklist and blocklist.isBlocked(bundleID) then
    return false, "this app is blocked - unblock it first (shift+i)"
  end
  if enabled[bundleID] then
    enabled[bundleID] = nil
  else
    enabled[bundleID] = true
  end
  persist()
  return enabled[bundleID] == true
end

function M.enabledList()
  local list = {}
  for bundleID in pairs(enabled) do
    table.insert(list, bundleID)
  end
  table.sort(list)
  return list
end

return M
