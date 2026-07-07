local M = {}

local gridLib = nil
local gridConfig = nil
local placeholders = {} -- id -> { canvas, screen, zone, label }
local hints = {}        -- id -> { canvas, screen, zone, letter }
local badges = {}       -- id -> { canvas (nil if toggled off), screen, zone, label }
local badgesEnabled = true
local screenWatcher = nil

local function buildPlaceholderCanvas(screen, zone, label)
  local frame = gridLib.zoneToFrame(screen:frame(), gridConfig, zone)
  local c = hs.canvas.new(frame)
  c:appendElements({
    {
      type = "rectangle",
      action = "strokeAndFill",
      fillColor = { white = 0.2, alpha = 0.25 },
      strokeColor = { white = 1, alpha = 0.6 },
      strokeWidth = 2,
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
    },
    {
      type = "text",
      text = label or "empty slot",
      textColor = { white = 1, alpha = 0.85 },
      textSize = 16,
      textAlignment = "center",
      frame = { x = "5%", y = "45%", w = "90%", h = "10%" },
    },
  })
  -- Floats above normal windows; no mouse callback is registered, so clicks
  -- pass through rather than being captured by this overlay.
  c:level(hs.canvas.windowLevels.overlay)
  c:clickActivating(false)
  return c
end

local function buildHintCanvas(screen, zone, letter)
  local frame = gridLib.zoneToFrame(screen:frame(), gridConfig, zone)
  local c = hs.canvas.new(frame)
  c:appendElements({
    { type = "rectangle", action = "fill", fillColor = { white = 0, alpha = 0.35 } },
    {
      type = "text",
      text = letter,
      textColor = { white = 1, alpha = 0.95 },
      textSize = 72,
      textAlignment = "center",
      frame = { x = "0%", y = "35%", w = "100%", h = "30%" },
    },
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:clickActivating(false)
  return c
end

-- A small tag in the top-left corner of a zone, not covering the window,
-- naming which workspace that window belongs to.
local function buildBadgeCanvas(screen, zone, label)
  local zoneFrame = gridLib.zoneToFrame(screen:frame(), gridConfig, zone)
  local badgeW, badgeH = 120, 20
  local frame = { x = zoneFrame.x + 6, y = zoneFrame.y + 6, w = badgeW, h = badgeH }
  local c = hs.canvas.new(frame)
  c:appendElements({
    {
      type = "rectangle",
      action = "fill",
      fillColor = { white = 0, alpha = 0.55 },
      roundedRectRadii = { xRadius = 4, yRadius = 4 },
    },
    {
      type = "text",
      text = label,
      textColor = { white = 1, alpha = 0.9 },
      textSize = 11,
      textAlignment = "center",
      frame = { x = "0%", y = "12%", w = "100%", h = "76%" },
    },
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:clickActivating(false)
  return c
end

local function buildFlashCanvas(screen, zone)
  local frame = gridLib.zoneToFrame(screen:frame(), gridConfig, zone)
  local c = hs.canvas.new(frame)
  c:appendElements({
    {
      type = "rectangle",
      action = "stroke",
      strokeColor = { red = 1, green = 0.85, blue = 0.2, alpha = 0.95 },
      strokeWidth = 5,
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
    },
  })
  c:level(hs.canvas.windowLevels.overlay)
  c:clickActivating(false)
  return c
end

function M.start(config, grid)
  gridLib = grid
  gridConfig = config.grid
  screenWatcher = hs.screen.watcher.new(function()
    for _, entry in pairs(placeholders) do
      entry.canvas:delete()
      entry.canvas = buildPlaceholderCanvas(entry.screen, entry.zone, entry.label)
      entry.canvas:show()
    end
    for _, entry in pairs(hints) do
      entry.canvas:delete()
      entry.canvas = buildHintCanvas(entry.screen, entry.zone, entry.letter)
      entry.canvas:show()
    end
    for _, entry in pairs(badges) do
      if entry.canvas then
        entry.canvas:delete()
        entry.canvas = buildBadgeCanvas(entry.screen, entry.zone, entry.label)
        entry.canvas:show()
      end
    end
  end)
  screenWatcher:start()
end

function M.showPlaceholder(id, screen, zone, label)
  M.hidePlaceholder(id)
  local c = buildPlaceholderCanvas(screen, zone, label)
  c:show()
  placeholders[id] = { canvas = c, screen = screen, zone = zone, label = label }
end

function M.hidePlaceholder(id)
  local entry = placeholders[id]
  if entry then
    entry.canvas:delete()
    placeholders[id] = nil
  end
end

function M.hideAllPlaceholders()
  for id in pairs(placeholders) do
    M.hidePlaceholder(id)
  end
end

function M.showHint(id, screen, zone, letter)
  M.hideHint(id)
  local c = buildHintCanvas(screen, zone, letter)
  c:show()
  hints[id] = { canvas = c, screen = screen, zone = zone, letter = letter }
end

function M.hideHint(id)
  local entry = hints[id]
  if entry then
    entry.canvas:delete()
    hints[id] = nil
  end
end

function M.hideAllHints()
  for id in pairs(hints) do
    M.hideHint(id)
  end
end

function M.showBadge(id, screen, zone, label)
  M.hideBadge(id)
  local c = nil
  if badgesEnabled then
    c = buildBadgeCanvas(screen, zone, label)
    c:show()
  end
  badges[id] = { canvas = c, screen = screen, zone = zone, label = label }
end

function M.hideBadge(id)
  local entry = badges[id]
  if entry then
    if entry.canvas then
      entry.canvas:delete()
    end
    badges[id] = nil
  end
end

function M.hideAllBadges()
  for id in pairs(badges) do
    M.hideBadge(id)
  end
end

local function renameEntry(store, oldId, newId)
  local entry = store[oldId]
  if entry then
    store[oldId] = nil
    store[newId] = entry
  end
end

-- Re-keys any tracked placeholder/hint/badge from oldId to newId without
-- touching its canvas - used when a workspace is renamed, since hide()/
-- show() recompute ids from the workspace's current name and would
-- otherwise never find (and never clean up) elements created under the old
-- name.
function M.renameId(oldId, newId)
  renameEntry(placeholders, oldId, newId)
  renameEntry(hints, oldId, newId)
  renameEntry(badges, oldId, newId)
end

function M.badgesEnabled()
  return badgesEnabled
end

-- Toggles visibility of all currently-tracked badges immediately, without
-- needing callers to re-issue showBadge for windows that are already
-- displayed - re-enabling rebuilds a canvas for every remembered entry.
function M.setBadgesEnabled(enabled)
  badgesEnabled = enabled
  for _, entry in pairs(badges) do
    if enabled and not entry.canvas then
      entry.canvas = buildBadgeCanvas(entry.screen, entry.zone, entry.label)
      entry.canvas:show()
    elseif not enabled and entry.canvas then
      entry.canvas:delete()
      entry.canvas = nil
    end
  end
end

-- Briefly outlines a zone, then removes itself - no id/bookkeeping needed
-- since it's not meant to persist or be individually addressable.
function M.flash(screen, zone, duration)
  local c = buildFlashCanvas(screen, zone)
  c:show()
  hs.timer.doAfter(duration or 0.8, function()
    c:delete()
  end)
end

function M.stop()
  if screenWatcher then
    screenWatcher:stop()
    screenWatcher = nil
  end
  M.hideAllPlaceholders()
  M.hideAllHints()
  M.hideAllBadges()
end

return M
