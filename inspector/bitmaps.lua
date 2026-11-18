local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Theme=dofile(here..'theme.lua')
local M={};M.__index=M
-- Sprite sheets: three states side by side, or three stacked list-cell states.
local horizontal={}
for name in ([[mcp_recarm_off mcp_recarm_on mcp_monitor_off mcp_monitor_on mcp_monitor_auto mcp_mute_off mcp_mute_on
  mcp_solo_off mcp_solo_on mcp_phase_norm mcp_phase_inv mcp_io mcp_io_dis mcp_io_r mcp_io_r_dis mcp_io_s mcp_io_s_dis
  mcp_io_s_r mcp_io_s_r_dis mcp_env mcp_env_read mcp_env_touch mcp_env_write mcp_env_latch mcp_env_preview
  mcp_fx_norm mcp_fx_empty mcp_fx_dis track_fxon_v track_fxoff_v track_fxempty_v
  mcp_recmode_in mcp_recmode_out mcp_recmode_off
  track_mute_off track_mute_on track_solo_off track_solo_on track_recarm_off track_recarm_on track_phase_norm track_phase_inv
  track_fx_in_norm track_fx_in_empty mcp_fx_in_norm mcp_fx_in_empty
  track_fx_norm track_fx_empty track_fx_dis track_fxon_h track_fxoff_h track_fxempty_h
  track_env track_env_read track_env_touch track_env_write track_env_latch track_env_preview
  track_monitor_off track_monitor_on track_monitor_auto
  mcp_mono mcp_stereo mixer_menu
  track_io track_io_dis track_io_r track_io_r_dis track_io_s track_io_s_dis track_io_s_r track_io_s_r_dis]]):gmatch('%S+') do horizontal[name]=true end
local vertical={}
local borrow={}
for _,control in ipairs({'mute','solo'}) do
  for _,state in ipairs({'off','on'}) do
    for _,prefix in ipairs({'mcp_','track_'}) do
      local name=prefix..control..'_'..state
      borrow[name]=true;borrow[name..'_ol']=true
    end
  end
end
for name in ([[mcp_fxlist_norm mcp_fxlist_byp mcp_fxlist_off mcp_fxlist_empty
  mcp_sendlist_norm mcp_sendlist_empty mcp_sendlist_mute mcp_sendlist_midihw]]):gmatch('%S+') do vertical[name]=true end
function M.new(g,theme,density,full_artwork) return setmetatable({g=g,theme=theme,density=density,full_artwork=full_artwork,cache={},count=0,missing={}},M) end
-- REAPER guide perimeter: pink marks the margins that must not stretch, yellow the
-- overhang drawn outside the control. Both are metadata, never visible art.
local function kind(r,g,b)
  if r>0.99 and g<0.01 and b>0.99 then return 1 end
  if r>0.99 and g>0.99 and b<0.01 then return 2 end
  return 0
end
-- `optional` art (overlays, per-theme alternatives) is not reported as missing when a theme lacks it.
function M:get(name,optional)
  if self.cache[name]~=nil then return self.cache[name] or nil end
  -- Generic geometry admits only list art and candidates for the guarded mute/solo path.
  if self.theme.layout=='generic' and not self.full_artwork and not vertical[name] and not borrow[name] then self.cache[name]=false;return nil end
  local a=Theme.asset(self.theme,name,self.density)
  if not a then self.cache[name]=false;if not optional then self.missing[#self.missing+1]=name end;return nil end
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
  -- An overlay ("_ol") is the part drawn on top of a control, larger than the control itself: its pink
  -- lines say how far it reaches past each edge.
  if name:sub(-3)=='_ol' then for i=1,4 do a.over[i]=a.over[i]+a.margin[i];a.margin[i]=0 end end
  g.dest,g.x,g.y=dest,x,y
  a.x=border and 1 or 0;a.y=a.x;a.w=w-2*a.x;a.h=h-2*a.y
  self.cache[name]=a;return a
end
-- Source rectangle of one state inside the guide-free interior.
function M:frame(name,state,optional)
  local a=self:get(name,optional);if not a then return nil end
  local sx,sy,sw,sh=a.x,a.y,a.w,a.h
  state=math.max(0,math.min(2,state or 0))
  if horizontal[name] or horizontal[name:gsub('_ol$','')] then sw=math.floor(sw/3);sx=sx+state*sw end
  if vertical[name] then
    -- A locally edited sheet can be a row or two short: integral rows, last one clamped.
    local endy=sy+sh;local step=math.ceil(sh/3)
    sy=sy+state*step;sh=math.min(step,endy-sy)
  end
  return a,sx,sy,sw,sh
end
-- Logical size of the control inside one state, excluding its guide perimeter and overhang.
function M:size(name,optional)
  local a,_,_,w,h=self:frame(name,0,optional)
  if a then return (w-a.over[1]-a.over[3])/a.scale,(h-a.over[2]-a.over[4])/a.scale end
end
-- Device-pixel blit of source pixels. Nearest sampling keeps 1:1 art crisp and
-- cannot pull guide colours into a slice; smooth is for genuinely resized art.
function M:blit(a,sx,sy,sw,sh,dx,dy,dw,dh,smooth)
  if dw<=0 or dh<=0 or sw<=0 or sh<=0 then return end
  local g=self.g;g.a=1;g.mode=smooth and 0 or 4
  g.blit(a.slot,1,0,sx,sy,sw,sh,dx,dy,dw,dh)
end
-- Knob stacks are vertical strips of square frames, ordered from minimum to maximum.
-- `fit` (points) resizes a frame to the knob it belongs to; otherwise it is drawn at native size.
function M:knob_frame(name,position,cx,cy,scale,fit)
  local a=self:get(name,true)
  if not a or a.w<=0 or a.h<a.w*2 or a.h%a.w~=0 then return false end
  local frame=math.floor(math.max(0,math.min(1,position))*(a.h//a.w-1)+.5)
  local size=math.floor((fit or a.w/a.scale)*scale+.5)
  if size<=0 then return false end
  local x,y=math.floor(cx*scale-size/2+.5),math.floor(cy*scale-size/2+.5)
  self:blit(a,a.x,a.y+frame*a.w,a.w,a.w,x,y,size,size,fit~=nil and size~=a.w)
  return true
end
-- Draw a sprite into the logical control rectangle x,y,w,h (nil w/h = the art's own size).
-- Guide margins keep their pixel size and only the middle stretches, so glyphs such as
-- the input arrow are never scaled. Yellow-guide overhang is drawn outside the rectangle.
-- `crop` (points) draws only the top of the art, for a control shown shorter than its artwork.
function M:draw(name,state,x,y,w,h,scale,optional,crop)
  local a,sx,sy,sw,sh=self:frame(name,state,optional);if not a then return false end
  if crop then sh=math.min(sh,math.floor(crop*a.scale+.5)+a.over[2]) end
  local k=scale/a.scale
  local function px(v) return math.floor(v*scale+.5) end
  local function ip(v) return math.floor(v*k+.5) end
  local ol,ot,orr,ob=a.over[1],a.over[2],a.over[3],a.over[4]
  local X,Y=px(x)-ip(ol),px(y)-ip(ot)
  local Wd=(w and px(x+w)-px(x) or ip(sw-ol-orr))+ip(ol)+ip(orr)
  if crop then ob=0 end
  local Hd=(h and px(y+h)-px(y) or ip(sh-ot-ob))+ip(ot)+ip(ob)
  local function cuts(size,dsize,first,last)
    local f,l=ip(first),ip(last)
    if dsize==ip(size) or first+last>=size or f+l>dsize then return {{0,size,0,dsize}} end
    return {{0,first,0,f},{first,size-first-last,f,dsize-f-l},{size-last,last,dsize-l,l}}
  end
  local cols=cuts(sw,Wd,a.margin[1]+ol,a.margin[3]+orr)
  local top,bottom=a.margin[2]+ot,a.margin[4]+ob
  local rows=cuts(sh,Hd,top,bottom)
  if (name=='mcp_extmixbg' or name=='mcp_extmixbgsel') and top>0 and bottom>0
    and top+bottom==sh and Hd>ip(top)+ip(bottom) then
    -- When the guides meet, extend their boundary row and keep the caps fixed.
    rows={{0,top,0,ip(top)},{top,1,ip(top),Hd-ip(top)-ip(bottom)},{top,bottom,Hd-ip(bottom),ip(bottom)}}
  end
  local smooth=#cols==1 and #rows==1 and (Wd~=sw or Hd~=sh)
  for _,r in ipairs(rows) do for _,c in ipairs(cols) do
    self:blit(a,sx+c[1],sy+r[1],c[2],r[2],X+c[3],Y+r[3],c[4],r[4],smooth)
  end end
  return true
end
-- Borrow a slice of the mixer background only when the entire panel lies inside
-- its fixed top region. Never stretch a vertical guide, stretch the footer, or
-- pull transparent/coloured sections up from the bottom of the native strip.
function M:pan_background(selected,top,bottom,x,y,w,scale)
  local a=self:get(selected and 'mcp_bgsel' or 'mcp_bg',true)
  if not a then return end
  local first,last=math.floor(top*a.scale+.5),math.floor(bottom*a.scale+.5)
  if first<0 or last<=first or last>math.min(a.margin[2],a.h) then return end
  for _,v in ipairs(a.over) do if v~=0 then return end end
  local l,r=a.margin[1],a.margin[3]
  local function px(v) return math.floor(v*scale+.5) end
  local L,R=px(l/a.scale),px(r/a.scale)
  local X,Y=px(x),px(y)
  local W,H=px(x+w)-X,px(y+bottom-top)-Y
  if l+r>=a.w or L+R>=W or H<=0 then return end
  local sy,sh=a.y+first,last-first
  self:blit(a,a.x,sy,l,sh,X,Y,L,H)
  self:blit(a,a.x+l,sy,a.w-l-r,sh,X+L,Y,W-L-R,H)
  self:blit(a,a.x+a.w-r,sy,r,sh,X+W-R,Y,R,H)
  if not a.pan_color then
    local g=self.g;local dest,gx,gy=g.dest,g.x,g.y
    g.dest,g.x,g.y=a.slot,a.x+l+(a.w-l-r)//2,sy+sh//2
    local cr,cg,cb=g.getpixel()
    g.dest,g.x,g.y=dest,gx,gy
    a.pan_color={cr*255,cg*255,cb*255}
  end
  return a.pan_color
end
-- Art whose guides say it overhangs far above its control (PhaseLab paints the whole strip from
-- its number tile). Draws the overhang from `top` down to the control at y, then the control's
-- fixed top rows, all at native size: nothing is stretched vertically. False if it cannot reach.
function M:rise(name,x,top,y,h,w,scale)
  local a=self:get(name,true)
  if not a or a.over[1]~=0 or a.over[3]~=0 then return false end
  local function px(v) return math.floor(v*scale+.5) end
  local k=scale/a.scale
  local X,W,Y=px(x),px(x+w)-px(x),px(top)
  local above=math.floor((px(y)-Y)/k+.5)
  local tile=math.min(a.margin[2],a.h-a.over[2],math.floor((px(y+h)-px(y))/k+.5))
  local l,r=a.margin[1],a.margin[3]
  local L,R=math.floor(l*k+.5),math.floor(r*k+.5)
  if above<=0 or above>a.over[2] or tile<0 or l+r>=a.w or L+R>=W then return false end
  local sy,sh=a.y+a.over[2]-above,above+tile
  local H=math.floor(sh*k+.5)
  self:blit(a,a.x,sy,l,sh,X,Y,L,H)
  self:blit(a,a.x+l,sy,a.w-l-r,sh,X+L,Y,W-L-R,H)
  self:blit(a,a.x+a.w-r,sy,r,sh,X+W-R,Y,R,H)
  return true
end
-- Colour of an opaque panel image: its centre, or the centre of its left overhang.
function M:tone(name,left)
  local a=self:get(name,true)
  if not a or (left and a.over[1]<4) then return nil end
  local key=left and 'tone_left' or 'tone'
  if not a[key] then
    local g=self.g;local dest,gx,gy=g.dest,g.x,g.y
    g.dest,g.x,g.y=a.slot,left and a.x+a.over[1]//2 or a.x+a.w//2,a.y+a.h//2
    local cr,cg,cb=g.getpixel()
    g.dest,g.x,g.y=dest,gx,gy
    a[key]={cr*255,cg*255,cb*255}
  end
  return a[key]
end
-- Borrow only conventional three-state buttons that fit the existing generic hit box.
function M:generic_button(name,state,x,y,w,h,scale)
  if not borrow[name] then return false end
  local function fit(a)
    return a and a.w%3==0 and a.w/3/a.scale<=w and a.h/a.scale<=h
      and a.w/3/a.scale>=12 and a.h/a.scale>=12
  end
  for _,candidate in ipairs({name,(name:gsub('^mcp_','track_'))}) do
    local a=self:get(candidate,true)
    if fit(a) then
      local overlay=self:get(candidate..'_ol',true)
      if overlay and overlay.width==1 and overlay.height==1 then overlay=nil end
      local cw,ch=self:size(candidate,true)
      local ow,oh
      if fit(overlay) then ow,oh=self:size(candidate..'_ol',true) end
      if cw>0 and ch>0 and (not overlay or (ow and ow>0 and oh>0 and math.abs(ow-cw)<=1 and math.abs(oh-ch)<=1)) then
        local dx=x+(w-a.w/3/a.scale)/2+a.over[1]/a.scale
        local dy=y+(h-a.h/a.scale)/2+a.over[2]/a.scale
        self:draw(candidate,state,dx,dy,nil,nil,scale,true)
        if overlay then self:draw(candidate..'_ol',state,dx,dy,nil,nil,scale,true) end
        return true
      end
    end
  end
  return false
end
function M:clear()
  for _,a in pairs(self.cache) do if a then self.g.setimgdim(a.slot,0,0) end end
  self.cache={};self.count=0;self.missing={}
end
return M
