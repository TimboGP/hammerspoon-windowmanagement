local M = {}

local deps = nil

-- The virtualDisplay strategy (if enabled) can make hs.screen.mainScreen()
-- resolve to the virtual "park" display rather than a real one. Placeholder
-- canvases must always land on a real screen, so this falls back to the
-- first non-virtual screen whenever mainScreen() is the virtual one. A no-op
-- for anyone who hasn't enabled the feature (deps.virtualDisplay is nil).
local function realMainScreen()
  local main = hs.screen.mainScreen()
  if deps.virtualDisplay and deps.virtualDisplay.getScreen() == main then
    for _, screen in ipairs(hs.screen.allScreens()) do
      if screen ~= main then
        return screen
      end
    end
  end
  return main
end

local function buildSaveData(ws)
  local slots = {}
  for _, slot in ipairs(ws.slots) do
    if slot.window then
      local app = slot.window:application()
      table.insert(slots, {
        zone = slot.zone,
        bundleID = app and app:bundleID() or nil,
        titlePattern = slot.window:title(),
      })
    else
      table.insert(slots, { zone = slot.zone })
    end
  end
  return { name = ws.name, grid = ws.gridConfig, slots = slots }
end

local function saveWorkspaceNamed(ws, name)
  return deps.persistence.saveWorkspace(name, buildSaveData(ws))
end

-- Builds a workspace's slots from its saved JSON (launching apps and
-- matching windows asynchronously) without touching which workspace is
-- "current" or visible - that's the caller's decision, since a single
-- workspace load activates it immediately but an arrangement load should
-- only activate the one workspace, keeping the rest hidden once populated.
-- Calls onComplete(workspaceOrNil).
local function populateWorkspaceFromSaved(name, onComplete)
  local gridLib, overlay, persistence, matcher, workspaces =
      deps.gridLib, deps.overlay, deps.persistence, deps.matcher, deps.workspaces

  local data = persistence.loadWorkspace(name)
  if not data then
    hs.alert.show("WM: could not load '" .. name .. "'", 1.5)
    onComplete(nil)
    return
  end

  local ws = workspaces.register(name)

  local pending = 0
  for _, slotData in ipairs(data.slots) do
    if slotData.bundleID then
      pending = pending + 1
    end
  end

  local function finishIfDone()
    if pending <= 0 then
      onComplete(ws)
    end
  end

  local claimedIds = {}
  for _, slotData in ipairs(data.slots) do
    if slotData.bundleID then
      matcher.matchWindow(slotData.bundleID, slotData.titlePattern, claimedIds, function(win, warning)
        if win then
          claimedIds[win:id()] = true
          table.insert(ws.slots, { window = win, zone = slotData.zone })
          gridLib.snapWindowToZone(win, ws.gridConfig, slotData.zone)
        else
          table.insert(ws.slots, { zone = slotData.zone })
          overlay.showPlaceholder(name .. ":" .. #ws.slots, realMainScreen(), slotData.zone,
            "unresolved: " .. slotData.bundleID)
        end
        if warning then
          hs.alert.show("WM: " .. warning, 2)
        end
        pending = pending - 1
        finishIfDone()
      end)
    else
      table.insert(ws.slots, { zone = slotData.zone })
      overlay.showPlaceholder(name .. ":" .. #ws.slots, realMainScreen(), slotData.zone, "empty slot")
    end
  end
  finishIfDone() -- covers the all-empty-slots case, where the loop above never decrements pending
end

local function loadWorkspaceByName(name)
  deps.workspaces.hideCurrent()
  hs.alert.show("WM: loading '" .. name .. "'...", 1.5)
  populateWorkspaceFromSaved(name, function(ws)
    if ws then
      deps.workspaces.activate(name)
    end
  end)
end

local function loadArrangementByName(name)
  local data = deps.persistence.loadArrangement(name)
  if not data then
    hs.alert.show("WM: could not load arrangement '" .. name .. "'", 1.5)
    return
  end

  deps.workspaces.hideCurrent()
  hs.alert.show("WM: loading arrangement '" .. name .. "'...", 1.5)

  local pending = #data.workspaces
  if pending == 0 then
    return
  end
  for _, wsName in ipairs(data.workspaces) do
    populateWorkspaceFromSaved(wsName, function(ws)
      if ws and wsName == data.activeWorkspace then
        deps.workspaces.activate(wsName)
      elseif ws then
        ws:hide()
      end
      pending = pending - 1
      if pending <= 0 then
        hs.alert.show("WM: arrangement '" .. name .. "' loaded", 1.5)
      end
    end)
  end
end

-- The four actions below are called both from saveModal's key bindings and
-- directly from the menu bar dropdown.

function M.promptSaveWorkspace()
  local ws = deps.workspaces.current()
  if not ws then
    hs.alert.show("WM: no active workspace to save", 1.5)
    return
  end
  local button, name = hs.dialog.textPrompt("Save workspace", "Name:", ws.name, "Save", "Cancel")
  if button == "Save" and name and #name > 0 then
    local ok, err = saveWorkspaceNamed(ws, name)
    if ok then
      hs.alert.show("WM: saved '" .. name .. "'", 1.5)
    else
      hs.alert.show("WM: save failed - " .. tostring(err), 2)
    end
  end
end

function M.promptSaveArrangement()
  local names = deps.workspaces.names()
  if #names == 0 then
    hs.alert.show("WM: no workspaces to save into an arrangement", 1.5)
    return
  end
  local cur = deps.workspaces.current()
  local button, name = hs.dialog.textPrompt("Save arrangement", "Name:", "", "Save", "Cancel")
  if button ~= "Save" or not name or #name == 0 then
    return
  end
  -- Ensure every member workspace has an up-to-date on-disk copy, since
  -- the arrangement itself only stores a pointer list, not full data.
  for _, wsName in ipairs(names) do
    local ws = deps.workspaces.get(wsName)
    if ws then
      saveWorkspaceNamed(ws, wsName)
    end
  end
  local ok, err = deps.persistence.saveArrangement(name, {
    name = name,
    workspaces = names,
    activeWorkspace = cur and cur.name or names[1],
  })
  if ok then
    hs.alert.show("WM: saved arrangement '" .. name .. "'", 1.5)
  else
    hs.alert.show("WM: arrangement save failed - " .. tostring(err), 2)
  end
end

function M.promptLoadWorkspace()
  local names = deps.persistence.savedWorkspaceNames()
  if #names == 0 then
    hs.alert.show("WM: no saved workspaces", 1.5)
    return
  end
  local choices = {}
  for _, name in ipairs(names) do
    table.insert(choices, { text = name })
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then
      loadWorkspaceByName(choice.text)
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

function M.promptLoadArrangement()
  local names = deps.persistence.savedArrangementNames()
  if #names == 0 then
    hs.alert.show("WM: no saved arrangements", 1.5)
    return
  end
  local choices = {}
  for _, name in ipairs(names) do
    table.insert(choices, { text = name })
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then
      loadArrangementByName(choice.text)
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

function M.start(config, gridLib, overlay, persistence, matcher, leaderModal, workspaces, virtualDisplay)
  deps = {
    gridLib = gridLib,
    overlay = overlay,
    persistence = persistence,
    matcher = matcher,
    workspaces = workspaces,
    virtualDisplay = virtualDisplay,
  }

  local saveModal = hs.hotkey.modal.new()

  function saveModal:entered()
    hs.alert.show(
      "Save/Load: w save workspace, a save arrangement, l load workspace, shift+l load arrangement, esc cancel", 3)
  end

  saveModal:bind({}, "w", nil, function()
    saveModal:exit()
    M.promptSaveWorkspace()
  end)

  saveModal:bind({}, "a", nil, function()
    saveModal:exit()
    M.promptSaveArrangement()
  end)

  saveModal:bind({}, "l", nil, function()
    saveModal:exit()
    M.promptLoadWorkspace()
  end)

  saveModal:bind({ "shift" }, "l", nil, function()
    saveModal:exit()
    M.promptLoadArrangement()
  end)

  saveModal:bind({}, "escape", nil, function() saveModal:exit() end)

  leaderModal:bind({}, "s", nil, function()
    leaderModal:exit()
    saveModal:enter()
  end)

  M.saveModal = saveModal
end

function M.forceExit()
  if M.saveModal then M.saveModal:exit() end
end

function M.stop()
  if M.saveModal then
    M.saveModal:exit()
    M.saveModal:delete()
    M.saveModal = nil
  end
end

return M
