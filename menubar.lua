local M = {}

local item = nil

function M.start(config, spoonPath)
  item = hs.menubar.new()
  if spoonPath then
    local icon = hs.image.imageFromPath(spoonPath .. "icon.svg")
    if icon then
      item:setIcon(icon:setSize({ w = 18, h = 18 }), true)
    end
  end
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
    item:setTitle(text)
  end
end

function M.setMenu(menuTable)
  if item then
    item:setMenu(menuTable)
  end
end

return M
