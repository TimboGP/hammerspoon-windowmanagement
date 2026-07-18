local home = os.getenv("HOME")

return {
  -- The physical leader combo (⌘⌃⌥Space) is no longer bound here - it's
  -- claimed once by Leader.spoon (see dotfiles' init.lua) and this modal is
  -- reached via the shared keybind_registry under path {"w"}. See
  -- modal.lua / init.lua's obj:start().
  escapeHatch = { { "cmd", "ctrl", "alt", "shift" }, "escape" },
  pauseHotkey = { { "cmd", "ctrl", "alt", "shift" }, "space" },

  grid = { cols = 12, rows = 12 },

  workspaceSlotCount = 9,

  -- On start, automatically re-load whatever workspace or arrangement was
  -- last loaded or saved in the previous session (tracked as `lastLoaded`
  -- in settings.json - see saveload.lua / init.lua). Set false to always
  -- boot into an empty state with nothing active.
  autoLoadLast = true,

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

  -- Tunables for the workspace hide/show slide animation (see windowanim.lua
  -- and the vendored AnimFX Spoon's `slide` effect). Deliberately runs ONLY on
  -- the virtual-display *park* path: the minimize fallback keeps its own Dock
  -- genie and gets no slide (double-animating a genie looks wrong). All of
  -- these are also toggled live from the menu bar "Window Animations" submenu.
  --   enabled     - master on/off for the slide.
  --   duration    - seconds per slide.
  --   easingOut/In- AnimFX easing names for hide (out) and show (in).
  --   direction   - the screen edge a window exits by on hide ("up"|"down"|
  --                 "left"|"right"); it re-enters from the same edge on show.
  --   followParkingDisplay - ignore `direction` and instead derive it from
  --                 where the parking display sits in the arrangement (and
  --                 place that display directly above the main screen so
  --                 "up/out" points at it). Only meaningful with virtualDisplay.
  windowAnim = {
    enabled = false,
    duration = 0.28,
    easingOut = "inCubic",
    easingIn = "outCubic",
    direction = "up",
    followParkingDisplay = false,
  },

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
