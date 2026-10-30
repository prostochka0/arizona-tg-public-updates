--[[
  IPC публичной версии (изолирован от arizona_tg_notify).
  Каталог: moonloader/arizona_tg_public/clips/
]]
local json = require 'cjson.safe'

local M = {}

local function root()
  return getWorkingDirectory() .. '\\arizona_tg_public\\clips'
end

function M.paths()
  local d = root()
  return {
    dir = d,
    cmd = d .. '\\ipc_cmd.txt',
    status = d .. '\\ipc_status.json',
  }
end

function M.ensure()
  local d = root()
  local parent = getWorkingDirectory() .. '\\arizona_tg_public'
  local lfs_ok, lfs = pcall(require, 'lfs')
  if lfs_ok then
    if not lfs.attributes(parent) then pcall(lfs.mkdir, parent) end
    if not lfs.attributes(d) then pcall(lfs.mkdir, d) end
  end
  return d
end

function M.write_cmd(cmd)
  M.ensure()
  local p = M.paths().cmd
  local f = io.open(p, 'wb')
  if not f then return false end
  f:write(tostring(cmd or ''))
  f:close()
  return true
end

function M.read_cmd()
  local p = M.paths().cmd
  local f = io.open(p, 'rb')
  if not f then return nil end
  local d = f:read('*a')
  f:close()
  pcall(os.remove, p)
  if not d or d == '' then return nil end
  return (d:gsub('^%s+', ''):gsub('%s+$', ''))
end

function M.write_status(tbl)
  M.ensure()
  local p = M.paths().status
  local body = json.encode(tbl or {})
  if not body then return false end
  local f = io.open(p, 'wb')
  if not f then return false end
  f:write(body)
  f:close()
  return true
end

function M.read_status()
  local p = M.paths().status
  local f = io.open(p, 'rb')
  if not f then return nil end
  local d = f:read('*a')
  f:close()
  if not d or d == '' then return nil end
  return json.decode(d)
end

function M.helper_alive(max_age)
  local st = M.read_status()
  if not st or not st.alive then return false end
  max_age = max_age or 5
  return (os.time() - tonumber(st.alive)) <= max_age
end

return M
