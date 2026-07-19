local M = {}

function M.start(config, callbacks)
  callbacks = callbacks or {}
  -- Unbound: entry is now driven by the shared keybind_registry (see
  -- init.lua's registration under path {"w"}), not a direct hs.hotkey bind
  -- on config.leader here, so the physical `⌘⌃⌥Space` combo is claimed
  -- exactly once, by Leader.spoon.
  local modal = hs.hotkey.modal.new()
  local idleTimer = nil

  local function resetIdleTimer()
    if idleTimer then idleTimer:stop() end
    idleTimer = hs.timer.doAfter(config.modalIdleTimeout, function()
      modal:exit()
    end)
  end

  local bindings = {
    { key = "t", description = "tile" },
    { key = "g", description = "workspace membership toggle (add/remove)" },
    { key = "a", description = "pull focused window into current workspace" },
    { key = "1-9", description = "switch to workspace slot" },
    { key = "p", description = "workspace picker" },
    { key = "shift+p", description = "pull focused window into Playground + switch" },
    { key = "n", description = "new workspace" },
    { key = "x", description = "swap windows" },
    { key = "s", description = "save/load/delete workspace" },
    { key = "i", description = "autotrack toggle" },
    { key = "v", description = "reveal window" },
    { key = "f", description = "focus" },
    { key = "c", description = "center/close" },
    { key = "w", description = "window list" },
    { key = "tab", description = "cycle windows" },
    { key = "u", description = "untracked window handling" },
    { key = "shift+u", description = "park all off-workspace windows" },
    { key = "j", description = "wiggle toggle" },
  }
  if config.virtualDisplay and config.virtualDisplay.enabled then
    table.insert(bindings, { key = "r", description = "restore parked window" })
  end
  M._bindings = bindings

  local cheatSheetLines = { "WM leader engaged" }
  local row = {}
  for _, b in ipairs(bindings) do
    table.insert(row, b.key .. " " .. b.description)
    if #row == 4 then
      table.insert(cheatSheetLines, table.concat(row, " | "))
      row = {}
    end
  end
  if #row > 0 then table.insert(cheatSheetLines, table.concat(row, " | ")) end
  table.insert(cheatSheetLines, "esc cancel")
  local cheatSheet = table.concat(cheatSheetLines, "\n")

  function modal:entered()
    if callbacks.isPaused and callbacks.isPaused() then
      modal:exit()
      hs.alert.show("WM: disabled (see menu bar or the pause hotkey to re-enable)", 2)
      return
    end
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

-- Structured {key, description} rows for the leader modal's flat verb menu,
-- built once in M.start(); consumed by CheatSheet.spoon.
function M.bindings()
  return M._bindings or {}
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
