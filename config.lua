local home = os.getenv("HOME")

return {
  leader = { { "cmd", "ctrl", "alt" }, "space" },
  escapeHatch = { { "cmd", "ctrl", "alt", "shift" }, "escape" },
  pauseHotkey = { { "cmd", "ctrl", "alt", "shift" }, "space" },

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

  -- Tunables for the `j` wiggle effect (see wiggle.lua / the vendored AnimFX
  -- Spoon). enabled toggles the hotkey on/off (also from the menu bar, see
  -- init.lua). axis: "x" or "y". amplitude in px, frequency in Hz, duration
  -- in seconds.
  wiggle = { enabled = true, axis = "x", amplitude = 18, frequency = 6, duration = 0.45 },

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
