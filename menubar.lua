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

-- A muted gray - confirmed visually (against both light and dark menu bar
-- backgrounds) to read as clearly dimmed relative to the default title
-- color, without needing per-pixel icon-alpha tricks (hs.canvas's
-- imageFromCanvas didn't preserve partial alpha reliably when tried).
local DIMMED_COLOR = { white = 0.55, alpha = 1.0 }

-- dimmed (optional): renders the title in DIMMED_COLOR instead of the
-- default color, to visually reflect e.g. pause.lua's disabled state.
function M.setStatus(text, dimmed)
  if not item then return end
  if dimmed then
    item:setTitle(hs.styledtext.new(text, { color = DIMMED_COLOR }))
  else
    item:setTitle(text)
  end
end

function M.setMenu(menuTable)
  if item then
    item:setMenu(menuTable)
  end
end

return M
