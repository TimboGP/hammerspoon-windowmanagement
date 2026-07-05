local M = {}

local gridLib = nil
local gridConfig = nil
local placeholders = {} -- id -> { canvas, screen, zone }
local screenWatcher = nil

local function buildCanvas(screen, zone, label)
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

function M.start(config, grid)
  gridLib = grid
  gridConfig = config.grid
  screenWatcher = hs.screen.watcher.new(function()
    for _, entry in pairs(placeholders) do
      entry.canvas:delete()
      entry.canvas = buildCanvas(entry.screen, entry.zone, entry.label)
      entry.canvas:show()
    end
  end)
  screenWatcher:start()
end

function M.showPlaceholder(id, screen, zone, label)
  M.hidePlaceholder(id)
  local c = buildCanvas(screen, zone, label)
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

function M.hideAll()
  for id in pairs(placeholders) do
    M.hidePlaceholder(id)
  end
end

function M.stop()
  if screenWatcher then
    screenWatcher:stop()
    screenWatcher = nil
  end
  M.hideAll()
end

return M
