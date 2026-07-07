local M = {}

function M.start(config, callbacks)
  callbacks = callbacks or {}
  local modal = hs.hotkey.modal.new(config.leader[1], config.leader[2])
  local idleTimer = nil

  local function resetIdleTimer()
    if idleTimer then idleTimer:stop() end
    idleTimer = hs.timer.doAfter(config.modalIdleTimeout, function()
      modal:exit()
    end)
  end

  local cheatSheet = table.concat({
    "WM leader engaged",
    "t tile | g add/remove | 1-9/p/n workspace | x swap",
    "s save/load/delete | i autotrack | v reveal | f/c focus",
    config.virtualDisplay and config.virtualDisplay.enabled
        and "r restore parked | esc cancel"
        or "esc cancel",
  }, "\n")

  function modal:entered()
    hs.alert.show(cheatSheet, 3.5)
    resetIdleTimer()
    if callbacks.entered then callbacks.entered() end
  end

  function modal:exited()
    if idleTimer then
      idleTimer:stop()
      idleTimer = nil
    end
    if callbacks.exited then callbacks.exited() end
  end

  modal:bind({}, "escape", nil, function() modal:exit() end)

  -- Always-live outside the modal: recovers from a stuck modal (e.g. after
  -- hs.reload() fires while the modal was active and tore down mid-state).
  hs.hotkey.bind(config.escapeHatch[1], config.escapeHatch[2], function()
    modal:exit()
    if callbacks.forceReset then callbacks.forceReset() end
    hs.alert.show("WM: force reset", 1)
  end)

  M.instance = modal
  M.resetIdleTimer = resetIdleTimer
  return modal
end

-- Wraps fn so any in-modal action keeps the idle timer alive, not just entry.
function M.bind(mods, key, fn)
  if not M.instance then return end
  M.instance:bind(mods, key, nil, function()
    if M.resetIdleTimer then M.resetIdleTimer() end
    fn()
  end)
end

function M.exit()
  if M.instance then M.instance:exit() end
end

-- Exposes the raw hs.hotkey.modal so other modules (e.g. tiling.lua) can
-- bind directly on it and transition into their own nested modals.
function M.getInstance()
  return M.instance
end

function M.stop()
  if M.instance then
    M.instance:exit()
    M.instance:delete()
    M.instance = nil
  end
  M.resetIdleTimer = nil
end

return M
