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
  mcp_mono mcp_stereo mixer_menu mcp_solodefeat_on mcp_recarm_auto mcp_recarm_auto_on
  track_mono track_stereo track_recmode_in track_recmode_out track_recmode_off render
  track_io track_io_dis track_io_r track_io_r_dis track_io_s track_io_s_dis track_io_s_r track_io_s_r_dis
  mcp_custom_customFX mcp_custom_customFX2 mcp_custom_stereo_off mcp_custom_quad_off mcp_custom_surround_off]]):gmatch('%S+') do horizontal[name]=true end
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
function M:frame(name,state,optional,frames)
  local a=self:get(name,optional);if not a then return nil end
  local sx,sy,sw,sh=a.x,a.y,a.w,a.h
  if frames then sw=a.w//frames;sx=sx+math.max(0,math.min(frames-1,state or 0))*sw end -- a strip of frames the layout picks from (not three states)
  state=math.max(0,math.min(2,state or 0))
  if not frames and (horizontal[name] or horizontal[name:gsub('_ol$','')]) then sw=math.floor(sw/3);sx=sx+state*sw end
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
  local clip=self.clip -- device columns [x0,x1) a layout keeps its art inside (the source is cut in proportion)
  if clip then
    local x0,x1=math.max(dx,clip[1]),math.min(dx+dw,clip[2]);if x1<=x0 then return end
    if x0~=dx or x1~=dx+dw then local k=sw/dw;sx=sx+math.floor((x0-dx)*k+.5);sw=math.max(1,math.floor((x1-x0)*k+.5));dx,dw=x0,x1-x0 end
  end
  local g=self.g;g.a=self.alpha or 1;g.mode=smooth and 0 or 4 -- (`alpha`: a layout dimming what it draws next, e.g. the knob of an empty send slot)
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
-- A knob's cap: one image with its marker at the top, fitted to a `size` pt square at x,y and turned clockwise by `angle` radians about its centre
-- (what gfx.blit's rotation does). Default 4.0's send knobs are a disc and this cap.
function M:rotated(name,angle,x,y,size,scale)
  local a=self:get(name,true)
  if not a or a.w<=0 or a.h<=0 then return false end
  local S=math.floor(size*scale+.5)
  if S<=0 then return false end
  local g=self.g;g.a=self.alpha or 1;g.mode=0
  g.blit(a.slot,1,angle,a.x,a.y,a.w,a.h,math.floor(x*scale+.5),math.floor(y*scale+.5),S,S)
  return true
end
-- A stack whose frames are as wide as the control and `h` points tall (theFRXST's bar-shaped pan and width).
-- `frame_h` (points) is for frames shorter than the control they are stretched into (Mydaw).
function M:stack(name,position,x,y,w,h,scale,frame_h)
  local a=self:get(name,true);if not a then return false end
  local fh=math.floor((frame_h or h)*a.scale+.5);local frames=fh>0 and a.h//fh or 0
  if frames<2 then return false end
  local frame=math.floor(math.max(0,math.min(1,position))*(frames-1)+.5)
  local function px(v) return math.floor(v*scale+.5) end
  self:blit(a,a.x,a.y+frame*fh,a.w,fh,px(x),px(y),px(x+w)-px(x),px(y+h)-px(y),true)
  return true
end
-- Draw a sprite into the logical control rectangle x,y,w,h (nil w/h = the art's own size).
-- Guide margins keep their pixel size and only the middle stretches, so glyphs such as
-- the input arrow are never scaled. Yellow-guide overhang is drawn outside the rectangle.
-- `crop` (points) draws only the top of the art, for a control shown shorter than its artwork.
function M:draw(name,state,x,y,w,h,scale,optional,crop,frames)
  local a,sx,sy,sw,sh=self:frame(name,state,optional,frames);if not a then return false end
  if crop then sh=math.min(sh,math.floor(crop*a.scale+.5)+a.over[2]) end
  local k=scale/a.scale
  local function px(v) return math.floor(v*scale+.5) end
  local function ip(v) return math.floor(v*k+.5) end
  local ol,ot,orr,ob=a.over[1],a.over[2],a.over[3],a.over[4]
  local X,Y=px(x)-ip(ol),px(y)-ip(ot)
  if self.shift then X,Y=X+self.shift[1],Y+self.shift[2] end -- (`shift`: whole device pixels, for drawing the same pixels somewhere else: see face)
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
-- The face of a sprite drawn into x,y,w,h: the device pixels its art really covers. List cells keep transparent margins and rounded
-- corners inside their rectangle, and gfx cannot read an image's alpha back, so the art is drawn at that very size over black and over
-- white in two scratch images (slots far past any theme's art) and the difference read: 1 where it is opaque, 0 where it is clear.
-- Returns {x,y,w,h, rows={{y0,y1,x0,x1},...}} in device pixels from the rectangle's own top left corner (its tallest unbroken run of
-- covered rows, each with the columns it starts and ends at), or nil for art with no face of its own there. Kept per size.
local BLACK,WHITE=1022,1023
function M:face(name,state,x,y,w,h,scale)
  local a=self:get(name,true);if not a then return nil end
  local g=self.g
  local function px(v) return math.floor(v*scale+.5) end
  local k=scale/a.scale
  local function ip(v) return math.floor(v*k+.5) end
  local Wd,Hd=px(x+w)-px(x),px(y+h)-px(y)
  if Wd<=0 or Hd<=0 then return nil end
  local key=name..'|'..(state or 0)..'|'..Wd..'|'..Hd..'|'..scale
  self.faces=self.faces or {}
  local f=self.faces[key]
  if f~=nil then return f or nil end
  self.nfaces=(self.nfaces or 0)+1
  if self.nfaces>96 then self.faces,self.nfaces={},1 end -- (a panel dragged through many widths: start over rather than grow)
  local ol,ot=ip(a.over[1]),ip(a.over[2])
  local bw,bh=Wd+ol+ip(a.over[3]),Hd+ot+ip(a.over[4])
  local dest,gx,gy,mode,clip,alpha=g.dest,g.x,g.y,g.mode,self.clip,self.alpha
  self.clip,self.alpha,self.shift=nil,nil,{ol-px(x),ot-px(y)} -- the art's own top left corner (overhang included) at the scratch image's
  for i,slot in ipairs({BLACK,WHITE}) do
    g.setimgdim(slot,bw,bh);g.dest=slot;g.mode=0;g.set(i-1,i-1,i-1,1);g.rect(0,0,bw,bh,1)
    self:draw(name,state,x,y,w,h,scale,true)
  end
  local function at(X,Y)
    g.x,g.y=X,Y;g.dest=BLACK;local r,gr,b=g.getpixel();g.dest=WHITE;local r2,g2,b2=g.getpixel()
    return 1-((r2+g2+b2)-(r+gr+b))/3
  end
  -- Down the middle: how opaque the face is (stock 7's is half clear) and which rows it takes; then each row's ends, from outside in.
  local cx=bw//2;local col,peak={},0
  for Y=0,bh-1 do col[Y]=at(cx,Y);if col[Y]>peak then peak=col[Y] end end
  f=false
  if peak>=.1 then
    local thr=peak*.5;local y0,y1,run=0,0,nil
    for Y=0,bh do
      local on=Y<bh and col[Y]>=thr
      if on and not run then run=Y elseif not on and run then if Y-run>y1-y0 then y0,y1=run,Y end;run=nil end
    end
    local rows,x0,x1={},bw,0
    for Y=y0,y1-1 do
      local l,r=0,bw
      while l<cx and at(l,Y)<thr do l=l+1 end
      while r-1>cx and at(r-1,Y)<thr do r=r-1 end
      local last=rows[#rows]
      if last and last[3]==l-ol and last[4]==r-ol then last[2]=Y+1-ot else rows[#rows+1]={Y-ot,Y+1-ot,l-ol,r-ol} end
      if l<x0 then x0=l end;if r>x1 then x1=r end
    end
    if y1>y0 and x1>x0 then f={x=x0-ol,y=y0-ot,w=x1-x0,h=y1-y0,rows=rows} end
  end
  g.dest,g.x,g.y,g.mode=dest,gx,gy,mode;g.a=1;self.clip,self.alpha,self.shift=clip,alpha,nil
  self.faces[key]=f;return f or nil
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
function M:tone(name,left,px,py) -- `px,py`: a chosen pixel, counted from the guide-free interior
  local a=self:get(name,true)
  if not a or (left and a.over[1]<4) then return nil end
  local key=px and 'tone_'..px..'_'..py or left and 'tone_left' or 'tone'
  if not a[key] then
    local g=self.g;local dest,gx,gy=g.dest,g.x,g.y
    g.dest,g.x,g.y=a.slot,px and a.x+px or left and a.x+a.over[1]//2 or a.x+a.w//2,px and a.y+py or a.y+a.h//2
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
  if self.faces then self.g.setimgdim(BLACK,0,0);self.g.setimgdim(WHITE,0,0) end
  self.cache={};self.count=0;self.missing={};self.faces,self.nfaces=nil,nil
end
return M
