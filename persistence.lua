local M = {}

local config = nil

local function ensureDir(path)
  if not hs.fs.attributes(path) then
    hs.fs.mkdir(path)
  end
end

function M.start(cfg)
  config = cfg
  ensureDir(config.storageDir)
  ensureDir(config.workspacesDir)
  ensureDir(config.arrangementsDir)
end

-- Writes to a temp file then renames into place, so a crash mid-write can't
-- leave a corrupt file.
local function atomicSave(dir, name, data)
  local path = dir .. "/" .. name .. ".json"
  local tmpPath = path .. ".tmp"
  local json = hs.json.encode(data, true)
  local f = io.open(tmpPath, "w")
  if not f then
    return false, "could not open " .. tmpPath
  end
  f:write(json)
  f:close()
  local ok, err = os.rename(tmpPath, path)
  return ok ~= nil, err
end

local function deleteSaved(dir, name)
  local ok, err = os.remove(dir .. "/" .. name .. ".json")
  return ok ~= nil, err
end

local function savedNames(dir)
  local names = {}
  local ok, iter, dirObj = pcall(hs.fs.dir, dir)
  if not ok then
    return names
  end
  for file in iter, dirObj do
    local name = file:match("^(.+)%.json$")
    if name then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function M.saveWorkspace(name, data)
  return atomicSave(config.workspacesDir, name, data)
end

function M.loadWorkspace(name)
  return hs.json.read(config.workspacesDir .. "/" .. name .. ".json")
end

function M.savedWorkspaceNames()
  return savedNames(config.workspacesDir)
end

function M.deleteWorkspace(name)
  return deleteSaved(config.workspacesDir, name)
end

function M.saveArrangement(name, data)
  return atomicSave(config.arrangementsDir, name, data)
end

function M.loadArrangement(name)
  return hs.json.read(config.arrangementsDir .. "/" .. name .. ".json")
end

function M.savedArrangementNames()
  return savedNames(config.arrangementsDir)
end

function M.deleteArrangement(name)
  return deleteSaved(config.arrangementsDir, name)
end

-- Small global key/value store for cross-session UI preferences (e.g.
-- whether workspace badges are shown), distinct from named
-- workspaces/arrangements.
function M.saveSettings(data)
  return atomicSave(config.storageDir, "settings", data)
end

function M.loadSettings()
  return hs.json.read(config.storageDir .. "/settings.json") or {}
end

return M
