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
  local unresolvedCount = 0
  for _, slot in ipairs(ws.slots) do
    if slot.window then
      local app = slot.window:application()
      local bundleID = app and app:bundleID() or nil
      if not bundleID then
        -- slot.window is stale (its owning app already quit) rather than
        -- genuinely empty - saving it as-is would silently produce a slot
        -- with a zone but no bundleID, which loads as an unlaunchable
        -- placeholder forever. Drop it back to an empty slot instead, and
        -- surface it so the user can notice and re-add the window.
        unresolvedCount = unresolvedCount + 1
        table.insert(slots, { zone = slot.zone })
      else
        table.insert(slots, {
          zone = slot.zone,
          bundleID = bundleID,
          titlePattern = slot.window:title(),
        })
      end
    else
      table.insert(slots, { zone = slot.zone })
    end
  end
  if unresolvedCount > 0 then
    hs.alert.show(
      "WM: " .. unresolvedCount .. " window(s) in '" .. ws.name ..
      "' had no resolvable app (likely quit) - saved as empty slot(s)", 3)
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

  -- Seed claimedIds with windows already owned by every OTHER registered
  -- workspace, so this load can't silently steal a window another
  -- workspace still considers its own (e.g. the same app window sitting in
  -- both a currently-open workspace and the one being loaded) - matcher
  -- falls through to the next unclaimed window of that bundle ID, or
  -- surfaces an "unresolved" placeholder, rather than snapping someone
  -- else's window into this workspace's zone out from under it.
  local claimedIds = {}
  for _, otherName in ipairs(workspaces.names()) do
    if otherName ~= name then
      local other = workspaces.get(otherName)
      if other then
        for _, slot in ipairs(other.slots) do
          if slot.window then
            claimedIds[slot.window:id()] = true
          end
        end
      end
    end
  end

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

-- Saves over the currently open workspace's own identity: if the name is
-- unchanged this just overwrites its file; if the name was edited in the
-- dialog, the workspace is renamed in place first (so it stays the same
-- workspace under a new name, rather than spawning a second one) and its
-- previous on-disk file is removed since it's now a stale snapshot of the
-- same workspace. Use promptSaveAsNewWorkspace for a deliberate duplicate.
function M.promptSaveWorkspace()
  local ws = deps.workspaces.current()
  if not ws then
    hs.alert.show("WM: no active workspace to save", 1.5)
    return
  end
  local button, name = hs.dialog.textPrompt("Save workspace", "Name:", ws.name, "Save", "Cancel")
  if button ~= "Save" or not name or #name == 0 then
    return
  end
  if name ~= ws.name then
    local oldName = ws.name
    local ok, err = deps.workspaces.rename(oldName, name)
    if not ok then
      hs.alert.show("WM: rename failed - " .. tostring(err), 2)
      return
    end
    deps.persistence.deleteWorkspace(oldName)
  end
  local ok, err = saveWorkspaceNamed(ws, name)
  if ok then
    hs.alert.show("WM: saved '" .. name .. "'", 1.5)
  else
    hs.alert.show("WM: save failed - " .. tostring(err), 2)
  end
end

-- Saves a copy under a new name without touching the currently open
-- workspace's identity or its existing on-disk file - the deliberate-
-- duplicate counterpart to promptSaveWorkspace's rename-in-place default.
function M.promptSaveAsNewWorkspace()
  local ws = deps.workspaces.current()
  if not ws then
    hs.alert.show("WM: no active workspace to save", 1.5)
    return
  end
  local button, name = hs.dialog.textPrompt("Save as new workspace", "Name:", ws.name .. " copy", "Save", "Cancel")
  if button ~= "Save" or not name or #name == 0 then
    return
  end
  local ok, err = saveWorkspaceNamed(ws, name)
  if ok then
    hs.alert.show("WM: saved new workspace '" .. name .. "'", 1.5)
  else
    hs.alert.show("WM: save failed - " .. tostring(err), 2)
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

function M.promptDeleteWorkspace()
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
    if not choice then return end
    local button = hs.dialog.blockAlert(
      "Delete workspace '" .. choice.text .. "'?",
      "This removes its saved file on disk. This cannot be undone.",
      "Delete", "Cancel")
    if button == "Delete" then
      local ok, err = deps.persistence.deleteWorkspace(choice.text)
      if ok then
        hs.alert.show("WM: deleted workspace '" .. choice.text .. "'", 1.5)
      else
        hs.alert.show("WM: delete failed - " .. tostring(err), 2)
      end
    end
  end)
  chooser:choices(choices)
  chooser:show()
end

function M.promptDeleteArrangement()
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
    if not choice then return end
    local button = hs.dialog.blockAlert(
      "Delete arrangement '" .. choice.text .. "'?",
      "This removes its saved file on disk (member workspaces are not deleted). This cannot be undone.",
      "Delete", "Cancel")
    if button == "Delete" then
      local ok, err = deps.persistence.deleteArrangement(choice.text)
      if ok then
        hs.alert.show("WM: deleted arrangement '" .. choice.text .. "'", 1.5)
      else
        hs.alert.show("WM: delete failed - " .. tostring(err), 2)
      end
    end
  end)
  chooser:choices(choices)
  chooser:show()
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
      "Save/Load: w save workspace, shift+w save as new workspace, a save arrangement, l load workspace, " ..
      "shift+l load arrangement, d delete workspace, shift+d delete arrangement, esc cancel", 4)
  end

  saveModal:bind({}, "w", nil, function()
    saveModal:exit()
    M.promptSaveWorkspace()
  end)

  saveModal:bind({ "shift" }, "w", nil, function()
    saveModal:exit()
    M.promptSaveAsNewWorkspace()
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

  saveModal:bind({}, "d", nil, function()
    saveModal:exit()
    M.promptDeleteWorkspace()
  end)

  saveModal:bind({ "shift" }, "d", nil, function()
    saveModal:exit()
    M.promptDeleteArrangement()
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
