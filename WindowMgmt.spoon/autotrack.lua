local M = {}

function M.start(config, ignore, watcher, leaderModal)
  leaderModal:bind({}, "i", nil, function()
    leaderModal:exit()
    local win = hs.window.focusedWindow()
    if not win then
      hs.alert.show("WM: no focused window", 1)
      return
    end
    local app = win:application()
    local bundleID = app and app:bundleID()
    if not bundleID then
      hs.alert.show("WM: could not determine app", 1)
      return
    end
    local nowEnabled, err = ignore.toggle(bundleID)
    if err then
      hs.alert.show("WM: " .. err, 1.5)
      return
    end
    watcher.refresh()
    local appName = app:name() or bundleID
    hs.alert.show("WM: auto-track " .. (nowEnabled and "enabled" or "disabled") .. " for " .. appName, 1.5)
  end)
end

return M
