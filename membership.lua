local M = {}

-- Adds the focused window to the current workspace. A window can belong to
-- multiple workspaces at once by design (see WISHLIST.md) - addWindow is
-- already a no-op if it's already a member here, and this never touches any
-- other workspace the window happens to also belong to. Refuses a window
-- whose app is on the user's persisted block-list (blocklist.lua) - blocked
-- apps shouldn't be pullable into a workspace by any route.
local function addFocusedToCurrent(workspaces, blocklist)
  local win = hs.window.focusedWindow()
  local ws = workspaces.current()
  if not win then
    hs.alert.show("WM: no focused window", 1)
    return
  end
  if not ws then
    hs.alert.show("WM: no active workspace (press a number key first)", 1)
    return
  end
  local app = win:application()
  local bundleID = app and app:bundleID()
  if blocklist and bundleID and blocklist.isBlocked(bundleID) then
    hs.alert.show("WM: " .. (app:name() or bundleID) .. " is blocked", 1.5)
    return
  end
  ws:addWindow(win)
  hs.alert.show("WM: added to workspace '" .. ws.name .. "'", 1)
end

function M.start(config, leaderModal, workspaces, blocklist)
  local membershipModal = hs.hotkey.modal.new()

  function membershipModal:entered()
    hs.alert.show("Workspace: a add focused window, r remove focused window, esc cancel", 2)
  end

  membershipModal:bind({}, "a", nil, function()
    addFocusedToCurrent(workspaces, blocklist)
    membershipModal:exit()
  end)

  membershipModal:bind({}, "r", nil, function()
    local win = hs.window.focusedWindow()
    local ws = workspaces.current()
    if not win then
      hs.alert.show("WM: no focused window", 1)
    elseif not ws or not ws:hasWindow(win) then
      hs.alert.show("WM: focused window isn't in this workspace", 1)
    else
      ws:removeWindow(win)
      win:minimize()
      hs.alert.show("WM: removed from workspace '" .. ws.name .. "'", 1)
    end
    membershipModal:exit()
  end)

  membershipModal:bind({}, "escape", nil, function() membershipModal:exit() end)

  leaderModal:bind({}, "g", nil, function()
    leaderModal:exit()
    membershipModal:enter()
  end)

  -- Top-level shortcut for the same action as `g a`, skipping the sub-modal
  -- for the common case of "just pull this window into my current workspace".
  leaderModal:bind({}, "a", nil, function()
    leaderModal:exit()
    addFocusedToCurrent(workspaces, blocklist)
  end)

  M.membershipModal = membershipModal
  return M
end

-- Force-exits the membership sub-modal without destroying it; used by the
-- global escape hatch to recover from a stuck modal.
function M.forceExit()
  if M.membershipModal then M.membershipModal:exit() end
end

function M.stop()
  if M.membershipModal then
    M.membershipModal:exit()
    M.membershipModal:delete()
    M.membershipModal = nil
  end
end

return M
