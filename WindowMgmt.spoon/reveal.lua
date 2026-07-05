local M = {}

function M.start(config, overlay, leaderModal, workspaces)
  leaderModal:bind({}, "v", nil, function()
    leaderModal:exit()
    local ws = workspaces.current()
    if not ws then
      hs.alert.show("WM: no active workspace", 1)
      return
    end
    local any = false
    for _, slot in ipairs(ws.slots) do
      if slot.window then
        any = true
        overlay.flash(slot.window:screen(), slot.zone, 0.8)
      end
    end
    if not any then
      hs.alert.show("WM: workspace '" .. ws.name .. "' is empty", 1.5)
    end
  end)
end

return M
