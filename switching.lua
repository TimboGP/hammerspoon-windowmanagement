local M = {}

local workspacesRef = nil

function M.promptNewWorkspace()
  local button, name = hs.dialog.textPrompt("New workspace", "Name:", "", "Create", "Cancel")
  if button == "Create" and name and #name > 0 then
    local ws = workspacesRef.switchTo(name)
    hs.alert.show("WM: workspace '" .. ws.name .. "'", 1)
  end
end

function M.start(config, leaderModal, workspaces)
  workspacesRef = workspaces

  for i = 1, config.workspaceSlotCount do
    local key = tostring(i)
    leaderModal:bind({}, key, nil, function()
      local ws = workspaces.switchToSlot(i)
      hs.alert.show("WM: workspace '" .. ws.name .. "'", 1)
    end)
  end

  leaderModal:bind({}, "p", nil, function()
    local names = workspaces.names()
    if #names == 0 then
      hs.alert.show("WM: no workspaces yet (press a number key to create one)", 1.5)
      return
    end
    local choices = {}
    for _, name in ipairs(names) do
      table.insert(choices, { text = name })
    end
    local chooser = hs.chooser.new(function(choice)
      if choice then
        local ws = workspaces.switchTo(choice.text)
        hs.alert.show("WM: workspace '" .. ws.name .. "'", 1)
      end
    end)
    chooser:choices(choices)
    chooser:show()
  end)

  leaderModal:bind({}, "n", nil, function()
    M.promptNewWorkspace()
  end)
end

return M
