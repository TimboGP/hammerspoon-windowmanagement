local M = {}

local rules = nil
local workspaces = nil
local grid = nil
local layouts = nil
local filter = nil

-- Finds the first rule (first-match-wins) whose match fires for this window:
-- bundleID always required, titlePattern (if present) additionally checked
-- via string.find against the window's current title.
local function findRule(bundleID, title)
  for _, rule in ipairs(rules.rules()) do
    if rule.match.bundleID == bundleID then
      if not rule.match.titlePattern then
        return rule
      end
      if title and string.find(title, rule.match.titlePattern) then
        return rule
      end
    end
  end
  return nil
end

local function resolveZone(gridConfig, zone)
  if type(zone) == "string" then
    return grid.presetZones(gridConfig)[zone]
  end
  return zone
end

-- Scoped to only rule-matched apps, not hs.window.filter.default, which is
-- known to add noticeable lag when watching every running app (especially
-- Electron apps with many windows).
local function rebuildFilter()
  if filter then
    filter:unsubscribeAll()
    filter = nil
  end

  local names = {}
  for _, bundleID in ipairs(rules.enabledList()) do
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
    local app = win:application()
    local bundleID = app and app:bundleID()
    if not bundleID then return end

    local rule = findRule(bundleID, win:title())
    if not rule then return end
    local action = rule.action or {}

    local ws = action.workspace and workspaces.get(action.workspace) or workspaces.current()
    if action.workspace and not ws then
      ws = workspaces.register(action.workspace)
    end
    if not ws then return end

    local isCurrent = (ws == workspaces.current())
    ws:addWindow(win)

    if action.zone then
      local zone = resolveZone(ws.gridConfig, action.zone)
      if zone then ws:retile(win, zone) end
    end

    if action.layout then
      layouts.apply(ws, action.layout)
    end

    -- A window auto-tracked to a workspace other than the one currently
    -- shown briefly snaps into that workspace's zone (same on-screen
    -- geometry as the current workspace - there's no per-display model yet)
    -- before this hides it. That flash is the same "populate then hide"
    -- pattern already accepted elsewhere (e.g. saveload.lua's arrangement
    -- load for non-active members). Plain minimize rather than the animated
    -- slide/park path everywhere else in this codebase uses for hiding -
    -- see WISHLIST.md's animation/park-dedup entry for folding this into
    -- that shared path once it exists.
    if not isCurrent then
      win:minimize()
    end
  end)
end

function M.start(config, rulesModule, workspacesModule, gridLib, layoutsModule)
  rules = rulesModule
  workspaces = workspacesModule
  grid = gridLib
  layouts = layoutsModule
  rebuildFilter()
end

-- Called after rules.toggle()/rules.addRule() change the rule set, since
-- hs.window.filter doesn't support adding/removing apps from an existing
-- instance - toggles/captures are infrequent manual actions, so rebuilding
-- is fine.
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
