local M = {}

local config = nil
local blocklist = nil -- blocklist module, or nil

-- Ordered list of rules: { match = { bundleID, titlePattern|nil },
-- action = { workspace|nil, zone|nil, layout|nil } }. First-match-wins order
-- - watcher.lua's windowCreated handler stops at the first rule whose match
-- fires for a newly created window. workspace/zone/layout nil in an action
-- means "current workspace" / "addWindow's default placement" / "don't
-- re-apply a layout" respectively - exactly today's plain auto-track
-- behavior, which is what an empty action produces.
local rules = {}

local function isDefaultIgnored(bundleID)
  for _, id in ipairs(config.defaultIgnoreList) do
    if id == bundleID then
      return true
    end
  end
  return false
end

-- Shared by M.toggle and M.addRule so both refuse identically: apps on the
-- default ignore list (Hammerspoon itself, system UI, etc. - toggling those
-- would be actively harmful, not just pointless) or on the user's own
-- persisted block-list (blocklist.lua, which exists specifically to keep an
-- app out of auto-track, among other places, without a config-file edit).
local function checkAllowed(bundleID)
  if isDefaultIgnored(bundleID) then
    return false, "this app is never auto-trackable"
  end
  if blocklist and blocklist.isBlocked(bundleID) then
    return false, "this app is blocked - unblock it first (shift+i)"
  end
  return true
end

-- A saved entry is either a rule table already, or - from before rules
-- existed - a bare bundleID string, migrated into a rule with an empty
-- action (today's default: current workspace, default placement), so an
-- old autotrack.json keeps working unchanged. Once loaded and re-saved, the
-- file is always written back out in the rule-table form.
local function toRule(entry)
  if type(entry) == "string" then
    return { match = { bundleID = entry }, action = {} }
  end
  return entry
end

function M.start(cfg, blocklistModule)
  config = cfg
  blocklist = blocklistModule
  if hs.fs.attributes(config.autoTrackFile) then
    local data = hs.json.read(config.autoTrackFile)
    if data then
      for _, entry in ipairs(data) do
        table.insert(rules, toRule(entry))
      end
    end
  end
end

local function persist()
  hs.json.write(rules, config.autoTrackFile, true, true)
end

-- Every match.bundleID across every rule, de-duped - what watcher.lua scopes
-- its hs.window.filter to (a rule matching by titlePattern alone isn't
-- supported in v1; every rule needs a bundleID).
function M.enabledList()
  local seen, list = {}, {}
  for _, rule in ipairs(rules) do
    local id = rule.match.bundleID
    if id and not seen[id] then
      seen[id] = true
      table.insert(list, id)
    end
  end
  table.sort(list)
  return list
end

function M.isEnabled(bundleID)
  for _, rule in ipairs(rules) do
    if rule.match.bundleID == bundleID then return true end
  end
  return false
end

-- Returns (nowEnabled, error). The quick path (`i`): ensures exactly one
-- simple rule (current workspace, default placement) exists for bundleID if
-- none did, or removes every rule for it - simple or richer, e.g. from
-- M.addRule's capture - if any already exist. `i` is a blunt "is this app
-- tracked at all" switch, not a per-rule toggle.
function M.toggle(bundleID)
  local allowed, err = checkAllowed(bundleID)
  if not allowed then return false, err end

  local hadAny = false
  for i = #rules, 1, -1 do
    if rules[i].match.bundleID == bundleID then
      table.remove(rules, i)
      hadAny = true
    end
  end
  if not hadAny then
    table.insert(rules, { match = { bundleID = bundleID }, action = {} })
  end
  persist()
  return not hadAny
end

-- Adds a full rule (e.g. from autotrack.lua's richer capture). Returns
-- (ok, error). `prepend` puts it first, so first-match-wins tries a
-- deliberately captured, more specific rule before whatever plain `i` may
-- already have added for the same app.
function M.addRule(rule, prepend)
  local allowed, err = checkAllowed(rule.match.bundleID)
  if not allowed then return false, err end
  if prepend then
    table.insert(rules, 1, rule)
  else
    table.insert(rules, rule)
  end
  persist()
  return true
end

-- Read-only view for watcher.lua's match-on-window-create loop.
function M.rules()
  return rules
end

return M
