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
    -- realScreen = hs.screen|nil, resettleWatcher = hs.uielement.watcher|nil }
    -- - realScreen is only set while a window is parked on the virtual
    -- display, so it can be moved back on show(); resettleWatcher is set
    -- for as long as the workspace is shown, fighting any drift away from
    -- slot.zone (see snapAndWatch below) - retile() below is how a
    -- deliberate zone change (tiling, swap) updates what it defends instead
    -- of being fought by it.
    slots = {},
    lastFocusedWindow = nil,
  }, M)
end

local function slotId(self, index)
  return self.name .. ":" .. index
end

-- unminimize() kicks off the Dock's genie/scale animation asynchronously at
-- the OS level; hs.window:setFrame() calls issued before that animation
-- settles are known to be silently dropped, so the post-unminimize zone
-- snap in show() below has to wait rather than running in the same tick.
local UNMINIMIZE_ANIMATION_DELAY = 0.35

-- Some apps (confirmed via logging: Slack, Outlook) go further and
-- asynchronously re-apply their own last-remembered window bounds sometime
-- after being unminimized/refocused - observed 8-13s later after sitting
-- minimized for an hour, presumably once their own reconnect/resync finishes
-- - the window visibly lands in its zone, then "jumps" back out to a stale
-- cached size (an exact half/quarter of the screen in both observed cases,
-- from some prior manual macOS window-tile action, long before this tool
-- ever managed them). The delay isn't reliably bounded, so rather than
-- guess a timeout, this watches the window's own AX move/resize
-- notifications for as long as the workspace stays shown and re-snaps
-- whenever it drifts from the frame we last set. A re-snap that lands on
-- the frame we already hold produces no further notification, so this is a
-- no-op once the app stops interfering (or for windows, e.g. Mail, that
-- never self-reposition at all) rather than fighting anything continuously.
-- hide()/removeWindow() stop the watcher so it never fights a placement
-- change this tool itself intends (focus mode, workspace switch, etc).
local FRAME_EPSILON = 2

local function frameMatches(a, b)
  if not a or not b then return false end
  return math.abs(a.x - b.x) <= FRAME_EPSILON and math.abs(a.y - b.y) <= FRAME_EPSILON
      and math.abs(a.w - b.w) <= FRAME_EPSILON and math.abs(a.h - b.h) <= FRAME_EPSILON
end

local function stopResettleWatch(slot)
  if slot.resettleWatcher then
    slot.resettleWatcher:stop()
    slot.resettleWatcher = nil
  end
end

-- Snaps window into zone now, then keeps re-snapping it for as long as this
-- workspace stays shown (see the comment above) whenever it moves/resizes
-- away from the frame we set. Stores the watcher on slot so a later
-- hide()/removeWindow() can stop it.
local function snapAndWatch(gridLib, slot, win, gridConfig, zone)
  stopResettleWatch(slot)
  local targetFrame = gridLib.snapWindowToZone(win, gridConfig, zone)

  local watcher
  watcher = win:newWatcher(function(_, event)
    if event == hs.uielement.watcher.elementDestroyed then
      watcher:stop()
      return
    end
    local ok, currentFrame = pcall(function() return win:frame() end)
    if not ok or not currentFrame or frameMatches(currentFrame, targetFrame) then
      return
    end
    local newFrame = gridLib.snapWindowToZone(win, gridConfig, zone)
    if newFrame then
      targetFrame = newFrame
    end
  end)
  watcher:start({
    hs.uielement.watcher.windowMoved,
    hs.uielement.watcher.windowResized,
    hs.uielement.watcher.elementDestroyed,
  })
  slot.resettleWatcher = watcher
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
      snapAndWatch(self.gridLib, slot, window, self.gridConfig, slot.zone)
      self.overlay.hidePlaceholder(slotId(self, i))
      self.overlay.showBadge(slotId(self, i), window:screen(), slot.zone, self.name)
      return slot
    end
  end

  local zone = self.gridLib.frameToZone(window:screen():frame(), self.gridConfig, window:frame())
  local slot = { window = window, zone = zone }
  table.insert(self.slots, slot)
  snapAndWatch(self.gridLib, slot, window, self.gridConfig, zone)
  self.overlay.showBadge(slotId(self, #self.slots), window:screen(), zone, self.name)
  return slot
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
      stopResettleWatch(slot)
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
      snapAndWatch(self.gridLib, slot, window, self.gridConfig, slot.zone)
      self.overlay.hidePlaceholder(slotId(self, i))
      self.overlay.showBadge(slotId(self, i), window:screen(), slot.zone, self.name)
      return true
    end
  end
  return false
end

-- Deliberately changes a member window's zone (e.g. from the tiling or swap
-- modules) and re-points the resettle watcher at the new frame, instead of
-- leaving it defending the old one and immediately undoing the change.
-- Returns false if window isn't a member of this workspace.
function M:retile(window, newZone)
  for _, slot in ipairs(self.slots) do
    if sameWindow(slot.window, window) then
      slot.zone = newZone
      snapAndWatch(self.gridLib, slot, window, self.gridConfig, newZone)
      return true
    end
  end
  return false
end

-- Stops the resettle watcher for window's slot without touching slot/window
-- state otherwise, so a caller (e.g. an animation) can move the window
-- itself without the watcher fighting every intermediate frame. Returns
-- true iff window is a member of this workspace (and was paused).
function M:pauseWatch(window)
  for _, slot in ipairs(self.slots) do
    if sameWindow(slot.window, window) then
      stopResettleWatch(slot)
      return true
    end
  end
  return false
end

-- Counterpart to pauseWatch: re-snaps window to slot.zone (read fresh, not a
-- value cached at pauseWatch time, so this self-heals correctly even if
-- something else changed the zone while paused) and re-arms the resettle
-- watcher against that frame. No-op returning false if window isn't a member.
function M:resumeWatch(window)
  for _, slot in ipairs(self.slots) do
    if sameWindow(slot.window, window) then
      snapAndWatch(self.gridLib, slot, window, self.gridConfig, slot.zone)
      return true
    end
  end
  return false
end

-- Re-keys this workspace's overlay elements from its current name to
-- newName before adopting it, so hide()/show() (which recompute each
-- slot's id from self.name at call time) keep finding the same on-screen
-- badges/placeholders instead of orphaning them under the old name.
function M:rename(newName)
  for i = 1, #self.slots do
    self.overlay.renameId(slotId(self, i), newName .. ":" .. i)
  end
  self.name = newName
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
      stopResettleWatch(slot)
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
      local win = slot.window
      local zone = slot.zone
      if win:isMinimized() then
        win:unminimize()
        hs.timer.doAfter(UNMINIMIZE_ANIMATION_DELAY, function()
          if not win:isMinimized() then
            snapAndWatch(self.gridLib, slot, win, self.gridConfig, zone)
          end
        end)
      else
        if slot.realScreen then
          restoreSlotFromPark(self, slot)
        end
        snapAndWatch(self.gridLib, slot, win, self.gridConfig, zone)
      end
      self.overlay.showBadge(slotId(self, i), win:screen(), zone, self.name)
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

-- Re-fits every member window to its zone against whatever screen it's
-- currently on. Zones are stored as grid-relative fractions of a screen,
-- not absolute pixels, so they're already resolution-independent - but
-- they only get recomputed against the *current* screen when something
-- explicitly re-snaps. Nothing does that when a monitor is connected/
-- disconnected mid-session, so workspaces.lua calls this (for the current
-- workspace only) on hs.screen.watcher events. Windows macOS already
-- relocated on its own (e.g. off a monitor that just disconnected) get
-- fit to wherever they actually landed, same as everywhere else in this
-- file. Skips minimized windows (nothing to re-fit) and windows pulled out
-- via focus mode (already removed from their slot).
function M:resnapAll()
  for i, slot in ipairs(self.slots) do
    if slot.window and not slot.window:isMinimized() then
      snapAndWatch(self.gridLib, slot, slot.window, self.gridConfig, slot.zone)
      self.overlay.showBadge(slotId(self, i), slot.window:screen(), slot.zone, self.name)
    end
  end
end

-- Stops every active resettle watcher without touching window/slot state
-- otherwise - used when the tool is paused (pause.lua), so it immediately
-- stops fighting drift without minimizing or moving anything.
function M:stopAllWatches()
  for _, slot in ipairs(self.slots) do
    stopResettleWatch(slot)
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
