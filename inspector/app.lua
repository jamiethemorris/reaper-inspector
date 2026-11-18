local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Theme,Model,View=dofile(here..'theme.lua'),dofile(here..'model.lua'),dofile(here..'view.lua')
local M={};M.__index=M;M.SECTION='ReaperInspector'
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
function M.new(r,g)
  return setmetatable({r=r,g=g,frames=0,closed=false},M)
end
function M:get(k) return self.r.GetExtState(M.SECTION,k) end
function M:put(k,v,persist) self.r.SetExtState(M.SECTION,k,tostring(v or ''),persist==true) end
function M:owned() return self.owner and self:get('owner')==self.owner end
function M:receipt(status)
  if not self:owned() then return end
  local s=self.view and self.view.snapshot
  self:put('current_track_guid',s and s.guid or '')
  self:put('current_track_name',s and s.name or '')
  self:put('current_project',s and tostring(s.project) or '')
  self:put('theme_source',self.theme and self.theme.source or self.theme_path)
  self:put('theme_directory',self.theme and self.theme.dir or '')
  self:put('assets_loaded',self.view and self.view.bitmaps and self.view.bitmaps.count or 0)
  self:put('assets_missing',self.view and self.view.bitmaps and table.concat(self.view.bitmaps.missing,',') or '')
  self:put('frame_count',self.frames);self:put('status',status)
end
function M:stop(status)
  if self.closed then return end
  self.closed=true
  if self:owned() then
    self:receipt(status or 'stopped')
    -- Window geometry is inspector-only; closing the window/Stop is explicit user intent.
    local ok,d,_,_,w,h=pcall(self.g.dock,-1,0,0,0,0)
    if ok then
      self:put('dock',d,true)
      if (d&1)==0 then self:put('width',clamp(w,128,800),true);self:put('height',clamp(h,430,1800),true) end
    end
    self.r.DeleteExtState(M.SECTION,'owner',false)
    if self:get('stop')==self.owner then self.r.DeleteExtState(M.SECTION,'stop',false) end
  end
  if self.view and self.view.bitmaps then self.view.bitmaps:clear() end
  self.g.quit()
end
function M:load_path(path)
  local theme,err=Theme.resolve(path)
  if not theme then self.view.options.status=err;self:put('error',err);return false,err end
  if self.view.bitmaps then self.view.bitmaps:clear();self.view.bitmaps=nil end
  self.theme=theme;self.theme_path=path;self.view.theme=theme;self.view.drag=nil
  self.view.options.status='';self:put('theme',path,true);self:put('error','');return true
end
function M:choose_theme()
  local choice=self.g.showmenu('Choose .ReaperTheme...|Enter asset folder...|Use Reapertips Custom2 default')
  if choice==1 then
    local ok,path=self.r.GetUserFileNameForRead(self.theme_path or Theme.DEFAULT,'Inspector: choose uncompressed .ReaperTheme','ReaperTheme')
    if ok then self:load_path(path) end
  elseif choice==2 then
    local ok,path=self.r.GetUserInputs('Inspector asset folder',1,'Folder path:,extrawidth=360',self.theme and self.theme.dir or '')
    if ok then self:load_path(path) end
  elseif choice==3 then self:load_path(Theme.DEFAULT) end
end
function M:menu()
  local d=self.g.dock(-1)
  local out=self.view.options.output_strip~=false
  local choice=self.g.showmenu(((d&1)~=0 and '!' or '')..'Dock inspector|'..(out and '!' or '')..'Show output strip||Load theme...|Use default theme|Close inspector')
  if choice==1 then
    local nextdock=(d&1)~=0 and (d&(~1)) or (d|1)
    self.g.dock(nextdock);self:put('dock',nextdock,true);self.view.drag=nil
  elseif choice==2 then self:set_output(not out)
  elseif choice==3 then self:choose_theme()
  elseif choice==4 then self:load_path(Theme.DEFAULT)
  elseif choice==5 then self:stop() end
end
function M:set_output(on)
  self.view.options.output_strip=on;self:put('output_strip',on and '1' or '0',true)
end
function M:start()
  -- Direct/CLI duplicates ask the exact incumbent to stop; never steal its registry.
  local incumbent=self:get('owner')
  if incumbent~='' then self:put('stop',incumbent);self.r.defer(function() end);return false end
  self.owner=tostring(self.r.time_precise())..':'..tostring(self)
  self:put('owner',self.owner);self:put('stop','');self.r.atexit(function() self:stop() end)
  if self.r.set_action_options then self.r.set_action_options(1) end
  self.r.defer(function() end) -- suppress REAPER automatic undo on every entry/exit path
  self.theme_path=self:get('theme');if self.theme_path=='' then self.theme_path=Theme.DEFAULT end
  local err;self.theme,err=Theme.resolve(self.theme_path)
  if not self.theme and self.theme_path==Theme.DEFAULT and self.r.GetLastColorThemeFile then
    -- No Custom2 copy installed: try the theme REAPER is using (works when it is an unpacked Reapertips theme).
    local current=self.r.GetLastColorThemeFile() or ''
    local theme=current~='' and Theme.resolve(current)
    if theme then self.theme,self.theme_path,err=theme,current,nil end
  end
  self.g.ext_retina=1
  local w=clamp(tonumber(self:get('width')) or 170,128,800)
  local h=clamp(tonumber(self:get('height')) or 700,430,1800)
  local d=math.floor(tonumber(self:get('dock')) or 0)
  self.g.init('Reaper Inspector',w,h,d)
  self.view=View.new(self.r,self.g,Model.new(self.r),self.theme,{
    load_theme=function() self:choose_theme() end,menu=function() self:menu() end,status=err or '',
    output_strip=self:get('output_strip')~='0',set_output=function(on) self:set_output(on) end})
  self:put('error',err or '');self:receipt('running');return true
end
function M:frame()
  if self.closed or not self:owned() then return false end
  local key=self.g.getchar()
  if key<0 or key==27 or self:get('stop')==self.owner then self:stop();return false end
  self.view:frame();self.frames=self.frames+1
  if not self.closed then self:receipt('running') end
  return not self.closed
end
function M:run()
  local function tick()
    local ok,again=xpcall(function() return self:frame() end,debug.traceback)
    if not ok then
      self:put('error',again);self:stop('error')
      if self.r.ShowConsoleMsg then self.r.ShowConsoleMsg('Reaper Inspector: '..again..'\n') end
    elseif again then self.r.defer(tick) end
  end
  local ok,started=xpcall(function() return self:start() end,debug.traceback)
  if not ok then self:put('error',started);self:stop('error');error(started) end
  if started then self.r.defer(tick) end
end
return M
