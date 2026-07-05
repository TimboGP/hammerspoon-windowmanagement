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

local function workspacePath(name)
  return config.workspacesDir .. "/" .. name .. ".json"
end

-- Writes to a temp file then renames into place, so a crash mid-write can't
-- leave a corrupt workspace file.
function M.saveWorkspace(name, data)
  local path = workspacePath(name)
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

function M.loadWorkspace(name)
  return hs.json.read(workspacePath(name))
end

function M.savedWorkspaceNames()
  local names = {}
  local ok, iter, dirObj = pcall(hs.fs.dir, config.workspacesDir)
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

return M
