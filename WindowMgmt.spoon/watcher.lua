local M = {}

local ignore = nil
local workspaces = nil
local filter = nil

-- Scoped to only auto-track-enabled apps, not hs.window.filter.default,
-- which is known to add noticeable lag when watching every running app
-- (especially Electron apps with many windows).
local function rebuildFilter()
  if filter then
    filter:unsubscribeAll()
    filter = nil
  end

  local names = {}
  for _, bundleID in ipairs(ignore.enabledList()) do
    local name = hs.application.nameForBundleID(bundleID)
    if name then
      table.insert(names, name)
    end
  end

  if #names == 0 then
    return
  end

  filter = hs.window.filter.new(names)
  filter:subscribe(hs.window.filter.windowCreated, function(win)
    local ws = workspaces.current()
    if ws and not ws:hasWindow(win) then
      ws:addWindow(win)
    end
  end)
end

function M.start(config, ignoreModule, workspacesModule)
  ignore = ignoreModule
  workspaces = workspacesModule
  rebuildFilter()
end

-- Called after ignore.toggle() changes the auto-track list, since
-- hs.window.filter doesn't support adding/removing apps from an existing
-- instance - toggles are infrequent manual actions, so rebuilding is fine.
function M.refresh()
  rebuildFilter()
end

function M.stop()
  if filter then
    filter:unsubscribeAll()
    filter = nil
  end
end

return M
