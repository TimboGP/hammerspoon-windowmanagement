-- A global on/off switch for the whole tool, independent of the leader
-- modal - lets someone stop it from tiling/auto-tracking/hiding windows
-- (e.g. before handing their laptop to someone else, or screen-sharing)
-- without quitting Hammerspoon or unloading the spoon outright. Bound
-- directly via hs.hotkey.bind (like the escape hatch in modal.lua), so it
-- always works regardless of current enabled state.
local M = {}

local enabled = true

function M.isEnabled()
  return enabled
end

function M.isPaused()
  return not enabled
end

-- initialEnabled restores whatever was persisted at the end of the previous
-- session (see init.lua's savedSettings.managementEnabled), so a reload
-- doesn't silently re-enable a tool someone deliberately paused - defaults
-- to true (today's boot-enabled behavior) for a fresh install / nil.
function M.start(config, callbacks, initialEnabled)
  callbacks = callbacks or {}
  if initialEnabled ~= nil then
    enabled = initialEnabled
  end

  function M.setEnabled(newEnabled)
    if newEnabled == enabled then
      return
    end
    enabled = newEnabled
    if callbacks.onChange then callbacks.onChange(enabled) end
    if enabled then
      if callbacks.onEnabled then callbacks.onEnabled() end
      hs.alert.show("WM: enabled", 1.5)
    else
      if callbacks.onDisabled then callbacks.onDisabled() end
      hs.alert.show("WM: disabled - tiling/auto-track paused (press again to re-enable)", 2.5)
    end
  end

  hs.hotkey.bind(config.pauseHotkey[1], config.pauseHotkey[2], function()
    M.setEnabled(not enabled)
  end)

  return M
end

return M
