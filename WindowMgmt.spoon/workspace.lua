local M = {}
M.__index = M

function M.new(name, overlay)
  return setmetatable({
    name = name,
    overlay = overlay,
    slots = {}, -- ordered list of { window = hs.window|nil, zone = {x0,y0,x1,y1} }
  }, M)
end

local function slotId(self, index)
  return self.name .. ":" .. index
end

function M:hasWindow(window)
  for _, slot in ipairs(self.slots) do
    if slot.window == window then return true end
  end
  return false
end

-- Prefers filling an existing empty slot (snapping the window into that
-- slot's zone) so a previously vacated spot can be refilled with a
-- different window. Only creates a new slot, registered at the window's
-- current on-screen position, if no empty slot exists.
function M:addWindow(window, gridLib, gridConfig)
  if self:hasWindow(window) then
    return
  end

  for i, slot in ipairs(self.slots) do
    if not slot.window then
      slot.window = window
      gridLib.snapWindowToZone(window, gridConfig, slot.zone)
      self.overlay.hidePlaceholder(slotId(self, i))
      return slot
    end
  end

  local zone = gridLib.frameToZone(window:screen():frame(), gridConfig, window:frame())
  table.insert(self.slots, { window = window, zone = zone })
  return self.slots[#self.slots]
end

-- Unregisters the window from its slot, leaving the zone as an empty
-- placeholder rather than deleting the slot outright, so the layout
-- doesn't collapse. Does not touch the window itself (e.g. minimizing it
-- is the caller's decision).
function M:removeWindow(window)
  for i, slot in ipairs(self.slots) do
    if slot.window == window then
      local appName = window:application() and window:application():name() or "?"
      local label = appName .. " - " .. (window:title() or "")
      slot.window = nil
      self.overlay.showPlaceholder(slotId(self, i), window:screen(), slot.zone, label)
      return slot
    end
  end
  return nil
end

return M
