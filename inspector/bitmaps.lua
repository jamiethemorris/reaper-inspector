local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Theme=dofile(here..'theme.lua')
local M={};M.__index=M
-- Sprite sheets: three states side by side, or three stacked list-cell states.
local horizontal={}
for name in ([[mcp_recarm_off mcp_recarm_on mcp_monitor_off mcp_monitor_on mcp_monitor_auto mcp_mute_off mcp_mute_on
  mcp_solo_off mcp_solo_on mcp_phase_norm mcp_phase_inv mcp_io mcp_io_dis mcp_io_r mcp_io_r_dis mcp_io_s mcp_io_s_dis
  mcp_io_s_r mcp_io_s_r_dis mcp_env mcp_env_read mcp_env_touch mcp_env_write mcp_env_latch mcp_env_preview
  mcp_fx_norm mcp_fx_empty mcp_fx_dis track_fxon_v track_fxoff_v track_fxempty_v
  mcp_recmode_in mcp_recmode_out mcp_recmode_off]]):gmatch('%S+') do horizontal[name]=true end
local vertical={}
for name in ([[mcp_fxlist_norm mcp_fxlist_byp mcp_fxlist_off mcp_fxlist_empty
  mcp_sendlist_norm mcp_sendlist_empty mcp_sendlist_mute mcp_sendlist_midihw]]):gmatch('%S+') do vertical[name]=true end
function M.new(g,theme,density) return setmetatable({g=g,theme=theme,density=density,cache={},count=0,missing={}},M) end
-- REAPER guide perimeter: pink marks the margins that must not stretch, yellow the
-- overhang drawn outside the control. Both are metadata, never visible art.
local function kind(r,g,b)
  if r>0.99 and g<0.01 and b>0.99 then return 1 end
  if r>0.99 and g>0.99 and b<0.01 then return 2 end
  return 0
end
function M:get(name)
  if self.cache[name]~=nil then return self.cache[name] or nil end
  local a=Theme.asset(self.theme,name,self.density)
  if not a then self.cache[name]=false;self.missing[#self.missing+1]=name;return nil end
  local g=self.g;local slot=self.count
  if g.loadimg(slot,a.path)<0 then self.cache[name]=false;self.missing[#self.missing+1]=name;return nil end
  self.count=self.count+1;a.slot=slot
  local dest,x,y=g.dest,g.x,g.y;g.dest=slot
  local function at(px,py) g.x=px;g.y=py;return kind(g.getpixel()) end
  local w,h=a.width,a.height
  local border=false
  for i=0,w-1 do if at(i,0)~=0 or at(i,h-1)~=0 then border=true end end
  for i=0,h-1 do if at(0,i)~=0 or at(w-1,i)~=0 then border=true end end
  -- Guides run from a corner: optional yellow (overhang), then optional pink (fixed margin).
  local function run(px,py,dx,dy,n)
    local yellow,pink,i=0,0,0
    while i<n and at(px+dx*i,py+dy*i)==2 do yellow=yellow+1;i=i+1 end
    while i<n and at(px+dx*i,py+dy*i)==1 do pink=pink+1;i=i+1 end
    if yellow>0 then return yellow-1,pink end
    return 0,math.max(0,pink-1)
  end
  a.margin,a.over={0,0,0,0},{0,0,0,0} -- left, top, right, bottom
  if border then
    for i,sd in ipairs({{0,0,1,0,w},{0,0,0,1,h},{w-1,h-1,-1,0,w},{w-1,h-1,0,-1,h}}) do
      a.over[i],a.margin[i]=run(sd[1],sd[2],sd[3],sd[4],sd[5])
    end
  end
  g.dest,g.x,g.y=dest,x,y
  a.x=border and 1 or 0;a.y=a.x;a.w=w-2*a.x;a.h=h-2*a.y
  self.cache[name]=a;return a
end
-- Source rectangle of one state inside the guide-free interior.
function M:frame(name,state)
  local a=self:get(name);if not a then return nil end
  local sx,sy,sw,sh=a.x,a.y,a.w,a.h
  state=math.max(0,math.min(2,state or 0))
  if horizontal[name] then sw=math.floor(sw/3);sx=sx+state*sw end
  if vertical[name] then
    -- A locally edited sheet can be a row or two short: integral rows, last one clamped.
    local endy=sy+sh;local step=math.ceil(sh/3)
    sy=sy+state*step;sh=math.min(step,endy-sy)
  end
  return a,sx,sy,sw,sh
end
-- Device-pixel blit of source pixels. Nearest sampling keeps 1:1 art crisp and
-- cannot pull guide colours into a slice; smooth is for genuinely resized art.
function M:blit(a,sx,sy,sw,sh,dx,dy,dw,dh,smooth)
  if dw<=0 or dh<=0 or sw<=0 or sh<=0 then return end
  local g=self.g;g.a=1;g.mode=smooth and 0 or 4
  g.blit(a.slot,1,0,sx,sy,sw,sh,dx,dy,dw,dh)
end
-- Draw a sprite into the logical control rectangle x,y,w,h (nil w/h = the art's own size).
-- Guide margins keep their pixel size and only the middle stretches, so glyphs such as
-- the input arrow are never scaled. Yellow-guide overhang is drawn outside the rectangle.
function M:draw(name,state,x,y,w,h,scale)
  local a,sx,sy,sw,sh=self:frame(name,state);if not a then return false end
  local k=scale/a.scale
  local function px(v) return math.floor(v*scale+.5) end
  local function ip(v) return math.floor(v*k+.5) end
  local ol,ot,orr,ob=a.over[1],a.over[2],a.over[3],a.over[4]
  local X,Y=px(x)-ip(ol),px(y)-ip(ot)
  local Wd=(w and px(x+w)-px(x) or ip(sw-ol-orr))+ip(ol)+ip(orr)
  local Hd=(h and px(y+h)-px(y) or ip(sh-ot-ob))+ip(ot)+ip(ob)
  local function cuts(size,dsize,first,last)
    local f,l=ip(first),ip(last)
    if dsize==ip(size) or first+last>=size or f+l>dsize then return {{0,size,0,dsize}} end
    return {{0,first,0,f},{first,size-first-last,f,dsize-f-l},{size-last,last,dsize-l,l}}
  end
  local cols=cuts(sw,Wd,a.margin[1]+ol,a.margin[3]+orr)
  local rows=cuts(sh,Hd,a.margin[2]+ot,a.margin[4]+ob)
  local smooth=#cols==1 and #rows==1 and (Wd~=sw or Hd~=sh)
  for _,r in ipairs(rows) do for _,c in ipairs(cols) do
    self:blit(a,sx+c[1],sy+r[1],c[2],r[2],X+c[3],Y+r[3],c[4],r[4],smooth)
  end end
  return true
end
function M:clear()
  for _,a in pairs(self.cache) do if a then self.g.setimgdim(a.slot,0,0) end end
  self.cache={};self.count=0;self.missing={}
end
return M
