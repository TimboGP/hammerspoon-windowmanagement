local M = {}

local config = nil

function M.start(cfg)
  config = cfg
end

-- Polls `predicate` on a timer until it returns truthy or `timeout` seconds
-- elapse, then calls onDone(result-or-nil). Not a one-shot check: app
-- launch + window creation is asynchronous and takes a variable amount of
-- time, so we can't just check once.
local function pollUntil(predicate, timeout, interval, onDone)
  local elapsed = 0
  local function tick()
    local result = predicate()
    if result then
      onDone(result)
      return
    end
    elapsed = elapsed + interval
    if elapsed >= timeout then
      onDone(nil)
      return
    end
    hs.timer.doAfter(interval, tick)
  end
  hs.timer.doAfter(interval, tick)
end

-- Among a bundle ID's windows not already claimed this load pass, returns
-- (titleMatch, anyUnclaimed) - a window whose title contains titlePattern
-- (plain substring, not a Lua pattern, since saved titles may contain
-- pattern-special characters), and separately the first unclaimed window
-- regardless of title, for fallback.
local function findCandidates(bundleID, titlePattern, claimedIds)
  local app = hs.application.get(bundleID)
  if not app then
    return nil, nil
  end
  local titleMatch, anyUnclaimed = nil, nil
  for _, w in ipairs(app:allWindows()) do
    if not claimedIds[w:id()] then
      if not anyUnclaimed then
        anyUnclaimed = w
      end
      if not titleMatch and titlePattern and titlePattern ~= "" and w:title()
          and w:title():find(titlePattern, 1, true) then
        titleMatch = w
      end
    end
  end
  return titleMatch, anyUnclaimed
end

-- Launches (or focuses) the app, then polls for a window matching
-- titlePattern. On timeout, falls back to the first unclaimed window of
-- that bundle ID. Calls callback(window-or-nil, warningMessage-or-nil).
-- claimedIds is a set of window IDs already assigned to another slot in
-- this load pass, keyed by hs.window:id() (not the window object itself,
-- since Hammerspoon doesn't guarantee stable userdata identity across
-- separate :allWindows() calls for the same underlying window).
function M.matchWindow(bundleID, titlePattern, claimedIds, callback)
  local app = hs.application.launchOrFocusByBundleID(bundleID)
  if not app then
    callback(nil, "could not launch " .. bundleID)
    return
  end

  pollUntil(function()
    return (findCandidates(bundleID, titlePattern, claimedIds))
  end, config.matchTimeout, config.matchPollInterval, function(titleMatch)
    if titleMatch then
      callback(titleMatch, nil)
      return
    end
    local _, anyUnclaimed = findCandidates(bundleID, titlePattern, claimedIds)
    if anyUnclaimed then
      callback(anyUnclaimed, "no title match for " .. bundleID .. ", used first available window")
    else
      callback(nil, "no window appeared for " .. bundleID)
    end
  end)
end

return M
