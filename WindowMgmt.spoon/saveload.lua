local M = {}

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

local function loadWorkspaceByName(deps, name)
  local gridLib, overlay, persistence, matcher, workspaces = deps.gridLib, deps.overlay, deps.persistence, deps.matcher, deps.workspaces

  local data = persistence.loadWorkspace(name)
  if not data then
    hs.alert.show("WM: could not load '" .. name .. "'", 1.5)
    return
  end

  workspaces.hideCurrent()
  local ws = workspaces.register(name)
  hs.alert.show("WM: loading '" .. name .. "'...", 1.5)

  local pending = 0
  for _, slotData in ipairs(data.slots) do
    if slotData.bundleID then
      pending = pending + 1
    end
  end

  local function finishIfDone()
    if pending <= 0 then
      workspaces.activate(name)
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
          overlay.showPlaceholder(name .. ":" .. #ws.slots, hs.screen.mainScreen(), slotData.zone,
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
      overlay.showPlaceholder(name .. ":" .. #ws.slots, hs.screen.mainScreen(), slotData.zone, "empty slot")
    end
  end
  finishIfDone() -- covers the all-empty-slots case, where the loop above never decrements pending
end

function M.start(config, gridLib, overlay, persistence, matcher, leaderModal, workspaces)
  local deps = {
    gridLib = gridLib,
    overlay = overlay,
    persistence = persistence,
    matcher = matcher,
    workspaces = workspaces,
  }

  local saveModal = hs.hotkey.modal.new()

  function saveModal:entered()
    hs.alert.show("Save/Load: w save workspace, l load workspace, esc cancel", 2)
  end

  saveModal:bind({}, "w", nil, function()
    saveModal:exit()
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace to save", 1.5)
      return
    end
    local button, name = hs.dialog.textPrompt("Save workspace", "Name:", ws.name, "Save", "Cancel")
    if button == "Save" and name and #name > 0 then
      local ok, err = persistence.saveWorkspace(name, buildSaveData(ws))
      if ok then
        hs.alert.show("WM: saved '" .. name .. "'", 1.5)
      else
        hs.alert.show("WM: save failed - " .. tostring(err), 2)
      end
    end
  end)

  saveModal:bind({}, "l", nil, function()
    saveModal:exit()
    local names = persistence.savedWorkspaceNames()
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
        loadWorkspaceByName(deps, choice.text)
      end
    end)
    chooser:choices(choices)
    chooser:show()
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
