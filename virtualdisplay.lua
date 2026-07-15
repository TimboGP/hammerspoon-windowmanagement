-- Experimental, opt-in client for the sibling vdisplay-helper daemon (a
-- standalone Swift binary, separate repo) that owns a virtual display's
-- lifecycle via the private CGVirtualDisplay API and exposes it over a Unix
-- domain socket. This module never speaks the private API directly - it only
-- talks JSON over the socket, and degrades to "unavailable" (letting callers
-- fall back to minimize) whenever the daemon can't be reached.
local M = {}

local config = nil
local availability = nil -- nil = not yet checked this session; true/false after
local screenCache = nil
local activeDisplayID = nil
local warnedOnce = false
local changeWatcher = nil

-- Matches the name the daemon posts to (see vdisplay-helper's main.swift) -
-- a crash/restart there hands out a new displayID for what is otherwise the
-- same "park" display, and this is how the daemon tells this client without
-- waiting for it to notice on its own next lazy lookup (M.getScreen()'s
-- resolve-by-name fallback).
local DISPLAY_CHANGED_NOTIFICATION = "com.timbogp.vdisplay-helper.displayChanged"

local function warnOnce(message)
  if warnedOnce then return end
  warnedOnce = true
  hs.alert.show("WindowMgmt: " .. message, 3)
  print("WindowMgmt virtualdisplay: " .. message)
end

-- Sends one JSON command over a fresh connection and calls back with the
-- decoded response (or nil + an error string). One connection per request
-- matches the daemon's thread-per-connection model and keeps this client
-- simple, since commands here are infrequent (workspace switches, not a
-- steady stream).
local function sendCommand(cmd, callback)
  local sock = hs.socket.new()
  local done = false

  local function finish(response, err)
    if done then return end
    done = true
    sock:disconnect()
    callback(response, err)
  end

  sock:setCallback(function(data)
    local trimmed = data and data:gsub("%s+$", "") or ""
    local ok, decoded = pcall(hs.json.decode, trimmed)
    if ok and decoded then
      finish(decoded, nil)
    else
      finish(nil, "invalid JSON response from vdisplay-helper")
    end
  end)

  sock:setTimeout(config.connectTimeout or 3)

  local connected = sock:connect(config.socketPath, function()
    sock:write(hs.json.encode(cmd) .. "\n")
    sock:read("\n")
  end)

  if not connected then
    finish(nil, "could not connect to vdisplay-helper socket at " .. config.socketPath)
  end
end

-- Forward-declared: assigned below once resolveScreenByID exists, but
-- referenced here since M.start (which wires up the subscription) is
-- defined first in the file.
local handleDisplayChanged

function M.start(cfg)
  config = cfg.virtualDisplay
  if not changeWatcher then
    changeWatcher = hs.distributednotifications.new(function(name, obj, userInfo)
      handleDisplayChanged(userInfo)
    end, DISPLAY_CHANGED_NOTIFICATION)
    changeWatcher:start()
  end
end

-- Cached per session (re-checked only via M.reset()) since a ping round-trip
-- on every hide()/show() would be wasteful for a check that rarely changes
-- mid-session.
function M.isAvailable(callback)
  if availability ~= nil then
    callback(availability)
    return
  end
  sendCommand({ cmd = "ping" }, function(response, err)
    availability = response ~= nil and response.ok == true
    if not availability then
      warnOnce("vdisplay-helper not reachable (" .. tostring(err) .. "); falling back to minimize")
    end
    callback(availability)
  end)
end

local function resolveScreenByID(displayID)
  if not displayID then return nil end
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:id() == displayID then
      return screen
    end
  end
  return nil
end

-- The daemon always names the display it creates "park" (see the `create`
-- call below), and that name survives a daemon restart even though the
-- displayID doesn't - the daemon is launchd-supervised and independent of
-- this Spoon's lifecycle, so it can crash/restart and hand out a new ID for
-- what is, from the user's perspective, the same parking display. Used as a
-- fallback so a stale cached ID doesn't strand windows already sitting on
-- the new display (see M.getScreen()).
local function resolveScreenByName(name)
  for _, screen in ipairs(hs.screen.allScreens()) do
    if screen:name() == name then
      return screen
    end
  end
  return nil
end

-- Reacts to the daemon's push notification (see vdisplay-helper's main.swift)
-- instead of waiting for the next lazy getScreen() lookup - lets a freshly
-- created display be adopted (and positionAboveMain re-applied by init.lua's
-- ensureDisplay callers) right away rather than only on the next hide/show.
-- A "destroyed" event only clears the cache when it matches what's cached,
-- since a stale destroy for an ID we've already moved on from shouldn't wipe
-- a newer one out from under us.
handleDisplayChanged = function(userInfo)
  local event = userInfo and userInfo.event
  local displayID = userInfo and userInfo.displayID
  if event == "created" and displayID then
    local screen = resolveScreenByID(displayID)
    if screen then
      screenCache = screen
      activeDisplayID = displayID
    end
  elseif event == "destroyed" and displayID and displayID == activeDisplayID then
    screenCache = nil
    activeDisplayID = nil
  end
end

-- Idempotent from the caller's perspective too: if a display is already
-- cached and still resolvable, returns it immediately without a round-trip.
function M.ensureDisplay(callback)
  local cached = M.getScreen()
  if cached then
    callback(cached, nil)
    return
  end

  M.isAvailable(function(available)
    if not available then
      callback(nil, "vdisplay-helper unavailable")
      return
    end
    sendCommand({
      cmd = "create",
      name = "park",
      width = config.width,
      height = config.height,
    }, function(response, err)
      if not response or not response.ok then
        local reason = err or (response and response.error) or "unknown error"
        warnOnce("virtual display creation failed (" .. tostring(reason) .. "); falling back to minimize")
        callback(nil, reason)
        return
      end
      local screen = resolveScreenByID(response.displayID)
      if not screen then
        callback(nil, "created display not found in hs.screen.allScreens()")
        return
      end
      activeDisplayID = response.displayID
      screenCache = screen
      callback(screen, nil)
    end)
  end)
end

-- Synchronous accessor for hide()/show(), which must stay synchronous - also
-- re-validates the cache so an externally-destroyed display (daemon killed,
-- display removed) is noticed rather than handed out stale. Falls back to
-- resolving by name ("park") before giving up entirely, since a daemon
-- restart hands out a new displayID for what is otherwise the same parking
-- display - without this, windows already sitting on the new display would
-- be reported as unparked (see WISHLIST.md/git history for the stranded-
-- window bug this was chasing).
function M.getScreen()
  if screenCache and not resolveScreenByID(activeDisplayID) then
    screenCache = nil
    activeDisplayID = nil
  end
  if not screenCache then
    local byName = resolveScreenByName("park")
    if byName then
      screenCache = byName
      activeDisplayID = byName:id()
    end
  end
  return screenCache
end

function M.hasCachedDisplay()
  return M.getScreen() ~= nil
end

function M.parkWindow(window)
  local screen = M.getScreen()
  if not screen then return false end
  window:moveToScreen(screen, false, false, 0)
  return true
end

-- Best-effort: repositions the parking display so its bottom edge sits flush
-- above the primary screen's top edge (centred horizontally), making an
-- "up and out" hide animation physically coherent with where windows land.
-- Called by init.lua only when the animation is set to follow the parking
-- display (see windowanim.lua's resolveDirection). No-op returning false if
-- the display isn't currently resolvable; pcall'd because setOrigin can reject
-- an origin the window server won't accept. Tries both known setOrigin call
-- forms (two numbers, or a {x,y} table) across Hammerspoon versions.
function M.positionAboveMain()
  local screen = M.getScreen()
  if not screen then return false end
  local main = hs.screen.primaryScreen()
  if not main or main == screen then return false end
  local mf = main:fullFrame()
  local pf = screen:fullFrame()
  local x = mf.x + (mf.w - pf.w) / 2
  local y = mf.y - pf.h
  if pcall(function() screen:setOrigin(x, y) end) then return true end
  return pcall(function() screen:setOrigin({ x = x, y = y }) end)
end

-- Falls back to asking the daemon via `list` when there's no cached
-- displayID, so this still works for a display this session never created
-- itself (e.g. discovered by the stop-time orphan check after a reload).
function M.removeDisplay(callback)
  local function destroyID(id)
    sendCommand({ cmd = "destroy", displayID = id }, function(response)
      screenCache = nil
      activeDisplayID = nil
      callback(response ~= nil and response.ok == true)
    end)
  end

  if activeDisplayID then
    destroyID(activeDisplayID)
    return
  end

  sendCommand({ cmd = "list" }, function(response)
    local displays = response and response.displays or {}
    if #displays == 0 then
      callback(true) -- nothing to remove
      return
    end
    destroyID(displays[1].displayID)
  end)
end

-- Authoritative check for the stop-time orphan-check dialog: asks the daemon
-- directly rather than trusting the local cache, since the daemon persists
-- via launchd independently of this Spoon's lifecycle (it may have a display
-- active that this particular Hammerspoon session never created itself).
function M.hasActiveDisplay(callback)
  sendCommand({ cmd = "list" }, function(response)
    local displays = response and response.displays or {}
    callback(response ~= nil and response.ok == true and #displays > 0)
  end)
end

function M.reset()
  availability = nil
  screenCache = nil
  activeDisplayID = nil
  warnedOnce = false
end

-- Deliberately does NOT destroy the display or contact the daemon - the
-- daemon and its virtual display are independent, launchd-supervised, and
-- outlive this Spoon's lifecycle by design. Only in-memory client state is
-- cleared. See init.lua's stop-time orphan-check for the explicit,
-- user-driven cleanup path.
function M.stop()
  M.reset()
  if changeWatcher then
    changeWatcher:stop()
    changeWatcher = nil
  end
end

return M
