-- Theme-specific bitmap adapter; deliberately not a WALTER interpreter.
local M = {}
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
local here = debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Unzip = dofile(here..'unzip.lua')
local function is_zip(p) local l = p:lower(); return l:match('%.reaperthemezip$') ~= nil or l:match('%.zip$') ~= nil end
local function write(path, data)
  local f = io.open(path, 'wb'); if not f then return false end
  f:write(data); f:close(); return true
end
-- Which hand-made strip layout fits this theme. Anything unrecognised gets the generic arrangement.
local function layout_of(cfg)
  if cfg:sub(1,600):find('Reapertips',1,true) then
    -- v1.95 redesigned the mixer strip (new sizes and artwork, a sidebar option); v1.90 and earlier share the first layout.
    return cfg:find('define_parameter%s+mcp_sidebar_w') and 'reapertips2' or 'reapertips'
  end
  -- REAPER's Default 7 and themes built on its layout script.
  if cfg:find('define_parameter%s+mcpStripFlowLocation1') and cfg:find('macro%s+drawMcp%s+thisLayout') then return 'default7' end
  return 'generic'
end
local function finish(t, cfg, inis)
  local row = tonumber(cfg:match('define_parameter%s+mcp_list_row_h%s+[^\r\n]-[\'\"]%s+(%d+)'))
    or tonumber(cfg:match('set%s+mcp%.fxlist%.font[^\r\n]-%[%s*%d+%s+(%d+)')) or 17
  -- List/meter text colours live in the .ReaperTheme (0x00BBGGRR); the first file that names a colour wins.
  local colors = {}
  for key,fallback in pairs(M.COLORS) do
    local n
    for _,ini in ipairs(inis) do
      n = tonumber(ini:match('[\r\n]'..key..'%s*=%s*(-?%d+)'))
      if n then break end
    end
    if n then n = n & 0xFFFFFF; colors[key] = {n & 255, (n >> 8) & 255, (n >> 16) & 255} else colors[key] = fallback end
  end
  t.row_height = math.max(12,math.min(26,row)); t.rtconfig = cfg; t.colors = colors; t.layout = layout_of(cfg)
  -- The theme's own defaults for the values its layout script uses (colour variants differ only in these).
  local source = '\n'..cfg
  t.version = tonumber(source:match('\nset theme_version%s+(%d+)')) or 1
  -- t.live, when set, holds the values currently chosen in REAPER's Theme Adjuster; they win over the defaults.
  t.param = function(name, fallback)
    if t.live and t.live[name] ~= nil then return t.live[name] end
    local literal = name:gsub('%p','%%%0') -- names such as "LayoutA-verboseMcp" contain pattern characters
    return tonumber(source:match('\ndefine_parameter%s+'..literal.."%s+'[^']*'%s+(%-?%d+)")) or fallback
  end
  return t
end
-- A theme archive is read in place. Only the images actually drawn are copied out, on demand, into
-- the Inspector's own cache folder (gfx can only load images from files).
local function resolve_zip(path, zip_path, outer, env)
  if not env or not env.cache or not env.mkdir then return nil, 'Theme archives need a cache folder' end
  local zip, err = Unzip.open(zip_path); if not zip then return nil, err end
  local inner, prefix
  for key,e in pairs(zip.entries) do
    if not key:find('/',1,true) and key:match('%.reapertheme$') then inner = Unzip.read(zip, e.name) end
  end
  local img = inner and inner:match('[\r\n]ui_img%s*=%s*([^\r\n]+)')
  if img then prefix = unquote(img):gsub('[/\\]+$','')..'/' end
  if not prefix or not zip.entries[(prefix..'rtconfig.txt'):lower()] then
    prefix = nil
    for key,e in pairs(zip.entries) do
      local dir = key:match('^(.-)rtconfig%.txt$')
      if dir and (not prefix or #dir < #prefix) then prefix = e.name:sub(1,#dir) end
    end
  end
  if not prefix then return nil, 'Theme archive has no rtconfig.txt' end
  local cfg, cerr = Unzip.read(zip, prefix..'rtconfig.txt'); if not cfg then return nil, cerr end
  local base = (zip_path:match('([^/\\]+)$') or 'theme'):gsub('%.[^.]*$',''):gsub('[^A-Za-z0-9%-_ ]','_') -- not %w: it follows the locale and can split UTF-8
  local dir = join(env.cache, base..'-'..zip.fingerprint)
  env.mkdir(dir)
  return finish({source=path, dir=dir, zip=zip, prefix=prefix}, cfg, {outer or '', inner or ''})
end
function M.resolve(path, env)
  if type(path) ~= 'string' or path == '' or path:find('[\r\n%z]') then return nil, 'Invalid theme path' end
  path = unquote(path):gsub('[/\\]+$', '')
  if is_zip(path) then return resolve_zip(path, path, nil, env) end
  local dir, ini = path, nil
  if path:lower():match('%.reapertheme$') then
    local s = read(path); if not s then return nil, 'Cannot read .ReaperTheme' end
    ini = s
    local img = s:match('[\r\n]ui_img%s*=%s*([^\r\n]+)')
    if not img then return nil, 'Theme has no ui_img asset directory' end
    img = unquote(img)
    local parent = path:match('^(.*)[/\\]') or '.'
    dir = (img:match('^[/\\]') or img:match('^%a:[/\\]')) and img or join(parent,img)
    -- REAPER keeps a user's colour tweaks to a zipped theme in a .ReaperTheme that points at the archive.
    if is_zip(dir) then return resolve_zip(path, dir, ini, env) end
  end
  local cfg = read(join(dir,'rtconfig.txt'))
  if not cfg then return nil, 'Choose a theme file, a theme archive or an asset folder containing rtconfig.txt' end
  return finish({source=path, dir=dir}, cfg, {ini or ''})
end
local function describe(path, scale)
  local s = read(path,24)
  if s and #s == 24 and s:sub(1,8) == '\137PNG\r\n\26\n' then
    local w,h = string.unpack('>I4I4',s,17)
    return {path=path,width=w,height=h,scale=scale}
  end
end
function M.asset(t,name,density)
  local variants = density >= 1.75 and {{'200',2},{'150',1.5},{'',1}}
    or density >= 1.25 and {{'150',1.5},{'200',2},{'',1}} or {{'',1},{'150',1.5},{'200',2}}
  for _,v in ipairs(variants) do
    if t.zip then
      local entry = t.zip.entries[(t.prefix..(v[1] ~= '' and v[1]..'/' or '')..name..'.png'):lower()]
      if entry then
        local path = join(t.dir,(v[1] ~= '' and v[1]..'_' or '')..name..'.png')
        local found = describe(path,v[2])
        if not found then
          local data = Unzip.read(t.zip, entry.name)
          if data and write(path,data) then found = describe(path,v[2])
          elseif data then t.error = 'Cannot write the theme image cache: '..t.dir end
        end
        if found then return found end
      end
    else
      local found = describe(join(t.dir,(v[1] ~= '' and v[1]..'/' or '')..name..'.png'),v[2])
      if found then return found end
    end
  end
end
return M
