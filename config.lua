local home = os.getenv("HOME")

return {
  leader = { { "cmd", "ctrl", "alt" }, "space" },
  escapeHatch = { { "cmd", "ctrl", "alt", "shift" }, "escape" },

  grid = { cols = 12, rows = 12 },

  workspaceSlotCount = 9,

  storageDir = home .. "/.hammerspoon/window-mgmt",
  workspacesDir = home .. "/.hammerspoon/window-mgmt/workspaces",
  arrangementsDir = home .. "/.hammerspoon/window-mgmt/arrangements",
  autoTrackFile = home .. "/.hammerspoon/window-mgmt/autotrack.json",

  defaultIgnoreList = {
    "com.apple.Hammerspoon",
    "com.apple.systempreferences",
    "com.apple.Spotlight",
    "com.apple.loginwindow",
    "com.apple.ScreenSaver.Engine",
  },

  modalIdleTimeout = 5,

  matchTimeout = 8,
  matchPollInterval = 0.25,
}
