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

  modalIdleTimeout = 3.5,

  matchTimeout = 8,
  matchPollInterval = 0.25,

  -- Experimental, off by default: parks hidden workspace windows on a
  -- virtual display (via the sibling vdisplay-helper daemon) instead of
  -- minimizing them, to avoid the genie/Dock animation on every workspace
  -- switch. See README "Experimental: Virtual-Display Hide/Show".
  virtualDisplay = {
    enabled = false,
    socketPath = home .. "/.vdisplay-helper/vdisplay-helper.sock",
    width = 1920,
    height = 1080,
    connectTimeout = 3,
  },
}
