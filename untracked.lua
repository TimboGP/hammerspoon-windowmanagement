local M = {}

local config = nil
local workspaces = nil
local hideConfig = nil     -- config.virtualDisplay, or nil
local virtualDisplay = nil -- virtualdisplay module, or nil
local windowanim = nil     -- windowanim module, or nil

local function isDefaultIgnored(bundleID)
  for _, id in ipairs(config.defaultIgnoreList) do
    if id == bundleID then return true end
  end
  return false
end

-- A window counts as trackable if it's a normal, visible app window (not a
-- panel/popover/etc, per hs.window:isStandard()) and its app isn't on the
-- default ignore list (Hammerspoon itself, System Prefs, Spotlight, etc -
-- see config.lua) - mirrors the filter ignore.lua uses for auto-track
-- eligibility, so this view and that toggle agree on what counts as a window.
local function isTrackable(win)
  if not win:isStandard() then return false end
  local app = win:application()
  if not app then return false end
  return not isDefaultIgnored(app:bundleID())
end

-- Finds which registered workspace (if any) currently owns this window, by
-- brute-force scanning every workspace's slots (workspace.lua keeps no
-- reverse index) - fine at this scale since it only runs while the chooser
-- is being built, not on every window event.
local function ownerOf(win)
  for _, name in ipairs(workspaces.names()) do
    local ws = workspaces.get(name)
    if ws:hasWindow(win) then return ws end
  end
  return nil
end

local function untrackedEntries()
  local cur = workspaces.current()
  local entries = {}
  for _, win in ipairs(hs.window.allWindows()) do
    if isTrackable(win) and not (cur and cur:hasWindow(win)) then
      local owner = ownerOf(win)
      local appName = win:application() and win:application():name() or "?"
      table.insert(entries, {
        text = appName .. " - " .. (win:title() or ""),
        subText = owner and ("on workspace '" .. owner.name .. "'") or "untracked",
        window = win,
        owner = owner,
      })
    end
  end
  return entries
end

-- Moves the window into the current workspace, first removing it from
-- whichever other workspace owns it (if any) so it isn't left registered
-- in two places at once.
local function pullIntoCurrent(choice)
  local cur = workspaces.current()
  if not cur then
    hs.alert.show("WM: no active workspace", 1)
    return
  end
  if choice.owner then
    choice.owner:removeWindow(choice.window)
  end
  cur:addWindow(choice.window)
  hs.alert.show("WM: pulled into workspace '" .. cur.name .. "'", 1)
end

local function showChooser()
  local entries = untrackedEntries()
  if #entries == 0 then
    hs.alert.show("WM: no untracked windows", 1.5)
    return
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then pullIntoCurrent(choice) end
  end)
  chooser:placeholderText("Pull which window into the current workspace?")
  chooser:choices(entries)
  chooser:show()
end

local function useVirtualDisplay()
  return hideConfig and hideConfig.enabled and virtualDisplay ~= nil
end

local function isAlive(win)
  local ok, visible = pcall(function() return win:isVisible() ~= nil end)
  return ok and visible
end

-- Hides a single window the same way workspace.lua:hide() hides a member
-- slot (slide-out + virtualDisplay park if enabled/available, else plain
-- minimize) - but for a window that isn't a workspace slot, so there's no
-- realScreen/watcher bookkeeping to do. Idempotent: no-ops on a window
-- that's already minimized or already sitting on the parking display, so
-- re-running "park all" doesn't re-trigger the slide on windows it already
-- parked.
local function parkWindow(win)
  if win:isMinimized() then return end

  local useVD = useVirtualDisplay()
  local vdScreen = useVD and virtualDisplay.getScreen() or nil
  if useVD and not vdScreen then
    virtualDisplay.ensureDisplay(function() end) -- fire-and-forget for next time
  end

  if not vdScreen then
    win:minimize() -- minimize fallback is deliberately un-animated
    return
  end
  if win:screen() == vdScreen then return end -- already parked

  local realScreen = win:screen()
  local handle = windowanim and windowanim.slideOut(win, realScreen, vdScreen, function(cancelled)
    if cancelled or not isAlive(win) then return end
    virtualDisplay.parkWindow(win)
  end)
  if not handle then
    virtualDisplay.parkWindow(win)
  end
end

-- Parks every trackable window not owned by the current workspace - the
-- untracked ones the chooser above lets you pull in one at a time, plus
-- anything sitting in another workspace (including the default
-- "Playground") that happens to still be visible. A quick way to declutter
-- down to just the active workspace without switching away and back.
local function parkAllUntracked()
  local entries = untrackedEntries()
  if #entries == 0 then
    hs.alert.show("WM: no off-workspace windows to park", 1.5)
    return
  end
  for _, entry in ipairs(entries) do
    parkWindow(entry.window)
  end
  hs.alert.show("WM: parked " .. #entries .. " off-workspace window(s)", 1.5)
end

function M.start(cfg, leaderModal, workspacesModule, virtualDisplayModule, windowanimModule)
  config = cfg
  workspaces = workspacesModule
  hideConfig = cfg.virtualDisplay
  virtualDisplay = virtualDisplayModule
  windowanim = windowanimModule

  leaderModal:bind({}, "u", nil, function()
    leaderModal:exit()
    showChooser()
  end)

  leaderModal:bind({ "shift" }, "u", nil, function()
    leaderModal:exit()
    parkAllUntracked()
  end)

  return M
end

-- No sub-modal of its own (the chooser is self-contained), so there's
-- nothing to force-exit - kept only for parity with the other sub-features'
-- lifecycle calls in init.lua.
function M.forceExit() end

function M.stop() end

return M
