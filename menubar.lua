local M = {}

local item = nil

function M.start(config)
  item = hs.menubar.new()
  M.setStatus("Playground") -- overwritten the instant workspaces.start() activates the default workspace
  return item
end

function M.stop()
  if item then
    item:delete()
    item = nil
  end
end

function M.setStatus(text)
  if item then
    item:setTitle("WM: " .. text)
  end
end

function M.setMenu(menuTable)
  if item then
    item:setMenu(menuTable)
  end
end

return M
