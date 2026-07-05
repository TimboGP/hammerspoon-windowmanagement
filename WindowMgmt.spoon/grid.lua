local M = {}

-- zone: {x0, y0, x1, y1} in grid cell units (0..cols, 0..rows)
function M.zoneToFrame(screenFrame, gridConfig, zone)
  local cellW = screenFrame.w / gridConfig.cols
  local cellH = screenFrame.h / gridConfig.rows
  return {
    x = screenFrame.x + zone.x0 * cellW,
    y = screenFrame.y + zone.y0 * cellH,
    w = (zone.x1 - zone.x0) * cellW,
    h = (zone.y1 - zone.y0) * cellH,
  }
end

-- Sets the frame and reads it back, since some apps (Chrome/Electron) round
-- frames to their own internal grid rather than honoring the exact request.
function M.snapWindowToZone(window, gridConfig, zone)
  if not window then return nil end
  local screen = window:screen()
  local frame = M.zoneToFrame(screen:frame(), gridConfig, zone)
  window:setFrame(frame)
  return window:frame()
end

-- Halves/thirds/quarters computed from the configured grid so they still
-- land on exact lines if cols/rows are changed from the 12x12 default.
function M.presetZones(gridConfig)
  local cols, rows = gridConfig.cols, gridConfig.rows
  local halfW, halfH = cols / 2, rows / 2
  local third, twoThirds = cols / 3, cols * 2 / 3

  return {
    full           = { x0 = 0,          y0 = 0,     x1 = cols,  y1 = rows },
    halfLeft       = { x0 = 0,          y0 = 0,     x1 = halfW, y1 = rows },
    halfRight      = { x0 = halfW,      y0 = 0,     x1 = cols,  y1 = rows },
    halfTop        = { x0 = 0,          y0 = 0,     x1 = cols,  y1 = halfH },
    halfBottom     = { x0 = 0,          y0 = halfH, x1 = cols,  y1 = rows },
    thirdLeft      = { x0 = 0,          y0 = 0,     x1 = third, y1 = rows },
    thirdCenter    = { x0 = third,      y0 = 0,     x1 = third * 2, y1 = rows },
    thirdRight     = { x0 = third * 2,  y0 = 0,     x1 = cols,  y1 = rows },
    twoThirdsLeft  = { x0 = 0,          y0 = 0,     x1 = twoThirds, y1 = rows },
    twoThirdsRight = { x0 = cols - twoThirds, y0 = 0, x1 = cols, y1 = rows },
    quarterTL      = { x0 = 0,          y0 = 0,     x1 = halfW, y1 = halfH },
    quarterTR      = { x0 = halfW,      y0 = 0,     x1 = cols,  y1 = halfH },
    quarterBL      = { x0 = 0,          y0 = halfH, x1 = halfW, y1 = rows },
    quarterBR      = { x0 = halfW,      y0 = halfH, x1 = cols,  y1 = rows },
  }
end

return M
