-- Theme-specific bitmap adapter; deliberately not a WALTER interpreter.
local M = {}
-- The default theme lives in REAPER's own resource folder (asked of REAPER when running inside it).
local resource = reaper and reaper.GetResourcePath and reaper.GetResourcePath()
  or (os.getenv('HOME') or '')..'/Library/Application Support/REAPER'
M.DEFAULT = resource..'/ColorThemes/Reapertips Theme_Custom2.ReaperTheme'
M.COLORS = {mcp_fx_normal={216,216,216}, mcp_fx_bypassed={160,126,59}, mcp_fx_offlined={156,58,58},
  mcp_sends_normal={254,207,103}, mcp_sends_muted={228,94,101}, mcp_send_midihw={70,185,254},
  mcp_list_scrollbar={140,140,140}, col_vubot={42,102,190}, col_vumid={70,185,254}, col_vutop={70,185,254}, col_vuclip={255,33,69}}
local function read(path, n)
  local f = io.open(path, 'rb'); if not f then return nil end
  local s = f:read(n or '*a'); f:close(); return s
end
local function join(a,b) return a:gsub('[/\\]+$', '')..'/'..b end
local function trim(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end
local function unquote(s)
  s = trim(s)
  if s:sub(1,1) == '"' and s:sub(-1) == '"' then return s:sub(2,-2) end
  return s
end
function M.resolve(path)
  if type(path) ~= 'string' or path == '' or path:find('[\r\n%z]') then return nil, 'Invalid theme path' end
  path = unquote(path):gsub('[/\\]+$', '')
  local dir, ini = path, nil
  if path:lower():match('%.reapertheme$') then
    local s = read(path); if not s then return nil, 'Cannot read .ReaperTheme' end
    ini = s
    local img = s:match('[\r\n]ui_img%s*=%s*([^\r\n]+)')
    if not img then return nil, 'Theme has no ui_img asset directory' end
    img = unquote(img)
    local parent = path:match('^(.*)[/\\]') or '.'
    dir = (img:match('^[/\\]') or img:match('^%a:[/\\]')) and img or join(parent,img)
  end
  local cfg = read(join(dir,'rtconfig.txt'))
  if not cfg then return nil, 'Choose an uncompressed asset folder containing rtconfig.txt' end
  local row = tonumber(cfg:match('define_parameter%s+mcp_list_row_h%s+[^\r\n]-[\'\"]%s+(%d+)')) or 17
  -- List/meter text colours live in the .ReaperTheme (0x00BBGGRR). An asset-folder
  -- source has no such file, so the installed Custom2 values are the fallback.
  local colors = {}
  for key,fallback in pairs(M.COLORS) do
    local n = ini and tonumber(ini:match('[\r\n]'..key..'%s*=%s*(-?%d+)'))
    if n then n = n & 0xFFFFFF; colors[key] = {n & 255, (n >> 8) & 255, (n >> 16) & 255} else colors[key] = fallback end
  end
  return {source=path, dir=dir, row_height=math.max(12,math.min(26,row)), rtconfig=cfg, colors=colors}
end
function M.asset(t,name,density)
  local variants = density >= 1.75 and {{'200',2},{'150',1.5},{'',1}}
    or density >= 1.25 and {{'150',1.5},{'200',2},{'',1}} or {{'',1},{'150',1.5},{'200',2}}
  for _,v in ipairs(variants) do
    local path = join(t.dir,(v[1] ~= '' and v[1]..'/' or '')..name..'.png')
    local s = read(path,24)
    if s and #s == 24 and s:sub(1,8) == '\137PNG\r\n\26\n' then
      local w,h = string.unpack('>I4I4',s,17)
      return {path=path,width=w,height=h,scale=v[2]}
    end
  end
end
return M
