local M = {}
M.__index = M

function M.new(name, overlay, gridLib, gridConfig, hideConfig, virtualDisplay)
  return setmetatable({
    name = name,
    overlay = overlay,
    gridLib = gridLib,
    gridConfig = gridConfig,
    hideConfig = hideConfig,         -- config.virtualDisplay table, or nil
    virtualDisplay = virtualDisplay, -- virtualdisplay module, or nil
    -- slots: ordered list of { window = hs.window|nil, zone = {x0,y0,x1,y1},
    -- realScreen = hs.screen|nil } - realScreen is only set while a window is
    -- parked on the virtual display, so it can be moved back on show().
    slots = {},
    lastFocusedWindow = nil,
  }, M)
end

local function slotId(self, index)
  return self.name .. ":" .. index
end

-- hs.window objects fetched via separate queries (e.g. app:allWindows() vs
-- hs.window.filter's windowCreated) are distinct userdata for the same real
-- window - Lua's == compares userdata by reference, not by the underlying
-- AXUIElement/window. Comparing by :id() is the stable way to tell whether
-- two handles refer to the same window (see matcher.lua's claimedIds, which
-- works around the same issue).
local function sameWindow(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a:id() == b:id()
end

function M:hasWindow(window)
  for _, slot in ipairs(self.slots) do
    if sameWindow(slot.window, window) then return true end
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
    if sameWindow(slot.window, window) then
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

local function useVirtualDisplay(self)
  return self.hideConfig and self.hideConfig.enabled and self.virtualDisplay ~= nil
end

-- Hides every member window, remembering whichever one is currently focused
-- so it can be restored on the next show(). When the virtualDisplay strategy
-- is enabled and its display is ready, windows are parked there instead of
-- minimized, avoiding the genie/Dock animation. If the display isn't ready
-- yet, this falls back to minimize for this call and kicks off display
-- creation in the background so a later call can use it.
function M:hide()
  local focused = hs.window.focusedWindow()
  if focused and self:hasWindow(focused) then
    self.lastFocusedWindow = focused
  end

  local useVD = useVirtualDisplay(self)
  local vdScreen = useVD and self.virtualDisplay.getScreen() or nil
  if useVD and not vdScreen then
    self.virtualDisplay.ensureDisplay(function() end) -- fire-and-forget for next time
  end

  for i, slot in ipairs(self.slots) do
    if slot.window then
      if vdScreen then
        slot.realScreen = slot.window:screen()
        self.virtualDisplay.parkWindow(slot.window)
      else
        slot.window:minimize()
      end
    end
    self.overlay.hideBadge(slotId(self, i))
  end
end

-- Restores a single parked window back onto its real screen. No-op if the
-- window isn't currently parked (e.g. it was minimized, or never hidden).
-- Shared by show() and restoreParkedWindows() so both paths handle the
-- "virtual display disappeared out from under us" case identically.
local function restoreSlotFromPark(self, slot)
  if not slot.realScreen then return end
  local stillOnVirtual = self.virtualDisplay and self.virtualDisplay.hasCachedDisplay()
      and slot.window:screen() == self.virtualDisplay.getScreen()
  if stillOnVirtual then
    slot.window:moveToScreen(slot.realScreen, false, false, 0)
  end
  -- Otherwise the virtual display (or the window's presence on it) is gone;
  -- leave the window wherever macOS already relocated it and let the
  -- zone re-snap below correct its position.
  slot.realScreen = nil
end

-- Unminimizes/un-parks every member window, reapplies its zone (in case the
-- screen changed while hidden), and restores focus to the last-focused
-- window. Re-snapping via grid.lua against the real screen - rather than
-- caching an absolute frame at park time - keeps this path consistent with
-- the minimize path above and with every other placement path in this
-- codebase, all of which treat slot.zone as the source of truth.
function M:show()
  for i, slot in ipairs(self.slots) do
    if slot.window then
      if slot.window:isMinimized() then
        slot.window:unminimize()
      elseif slot.realScreen then
        restoreSlotFromPark(self, slot)
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

-- Restores any parked windows in this workspace regardless of whether it's
-- currently shown - powers the explicit "bring back all parked windows"
-- action, which must work even for hidden/inactive workspaces (e.g. after
-- the vdisplay-helper daemon was killed or the display removed externally).
-- Does not touch badges/focus, since a hidden workspace has none to show.
function M:restoreParkedWindows()
  for _, slot in ipairs(self.slots) do
    if slot.window and slot.realScreen then
      restoreSlotFromPark(self, slot)
      self.gridLib.snapWindowToZone(slot.window, self.gridConfig, slot.zone)
    end
  end
end

return M
