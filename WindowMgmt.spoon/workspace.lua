local M = {}
M.__index = M

function M.new(name, overlay, gridLib, gridConfig)
  return setmetatable({
    name = name,
    overlay = overlay,
    gridLib = gridLib,
    gridConfig = gridConfig,
    slots = {}, -- ordered list of { window = hs.window|nil, zone = {x0,y0,x1,y1} }
    lastFocusedWindow = nil,
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
function M:addWindow(window)
  if self:hasWindow(window) then
    return
  end

  for i, slot in ipairs(self.slots) do
    if not slot.window then
      slot.window = window
      self.gridLib.snapWindowToZone(window, self.gridConfig, slot.zone)
      self.overlay.hidePlaceholder(slotId(self, i))
      self.overlay.showBadge(slotId(self, i), window:screen(), slot.zone, self.name)
      return slot
    end
  end

  local zone = self.gridLib.frameToZone(window:screen():frame(), self.gridConfig, window:frame())
  table.insert(self.slots, { window = window, zone = zone })
  self.overlay.showBadge(slotId(self, #self.slots), window:screen(), zone, self.name)
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
      self.overlay.hideBadge(slotId(self, i))
      self.overlay.showPlaceholder(slotId(self, i), window:screen(), slot.zone, label)
      return slot
    end
  end
  return nil
end

-- Directly restores a window into a specific, previously-vacated slot
-- (as opposed to addWindow's "first empty slot" heuristic) - used by focus
-- mode, which needs to snap a window back to its exact origin rather than
-- wherever happens to be free after other membership changes.
function M:refillSlot(slot, window)
  for i, s in ipairs(self.slots) do
    if s == slot then
      slot.window = window
      self.gridLib.snapWindowToZone(window, self.gridConfig, slot.zone)
      self.overlay.hidePlaceholder(slotId(self, i))
      self.overlay.showBadge(slotId(self, i), window:screen(), slot.zone, self.name)
      return true
    end
  end
  return false
end

-- Minimizes every member window, remembering whichever one is currently
-- focused so it can be restored on the next show().
function M:hide()
  local focused = hs.window.focusedWindow()
  if focused and self:hasWindow(focused) then
    self.lastFocusedWindow = focused
  end
  for i, slot in ipairs(self.slots) do
    if slot.window then
      slot.window:minimize()
    end
    self.overlay.hideBadge(slotId(self, i))
  end
end

-- Unminimizes every member window, reapplies its zone (in case the screen
-- changed while hidden), and restores focus to the last-focused window.
function M:show()
  for i, slot in ipairs(self.slots) do
    if slot.window then
      if slot.window:isMinimized() then
        slot.window:unminimize()
      end
      self.gridLib.snapWindowToZone(slot.window, self.gridConfig, slot.zone)
      self.overlay.showBadge(slotId(self, i), slot.window:screen(), slot.zone, self.name)
    end
  end

  local toFocus = self.lastFocusedWindow
  if not (toFocus and self:hasWindow(toFocus)) then
    toFocus = self.slots[1] and self.slots[1].window
  end
  if toFocus then
    toFocus:focus()
  end
end

return M
