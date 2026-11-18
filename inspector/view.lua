local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Bitmaps=dofile(here..'bitmaps.lua')
local Model=dofile(here..'model.lua')
local M={};M.__index=M
-- Geometry below is the Reapertips wide mixer strip, in logical points, measured against the
-- native mixer at 200%. It is this theme's layout written out, not a WALTER interpreter.
local STRIP=86                              -- native strip width; wider panels widen the meter first
local FONT='Fira Sans'
local FONTS={main=11.5,list=12,header=14.5,bold=12}   -- gfx sizes that land on the theme's rendered text sizes
local ENV={[0]='mcp_env','mcp_env_read','mcp_env_touch','mcp_env_write','mcp_env_latch','mcp_env_preview'}
local AUTOMODES={'Trim/Read','Read','Touch','Write','Latch','Latch preview'}
local RECMODES={{0,'Record: input'},{1,'Record: output (stereo)'},{2,'Record: disable (input monitoring only)'},
  {7,'Record: MIDI overdub'},{8,'Record: MIDI replace'}}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function inside(h,x,y) return h and x>=h.x and y>=h.y and x<h.x+h.w and y<h.y+h.h end
local function db(g) return g>0 and 20*math.log(g,10) or -150 end
local function gaintext(g) return g<=0 and '-inf' or ('%.2f'):format(db(g)) end
local function luma(c) return .212*c[1]+.701*c[2]+.087*c[3] end
local function mul(c,k) return {c[1]*k,c[2]*k,c[3]*k} end
-- The theme's "tint track name" rule: desaturate the track colour, then lift it to a readable brightness.
local function name_color(c)
  local l=luma(c);local sat=.35
  local t={c[1]*(1-sat)+l*sat,c[2]*(1-sat)+l*sat,c[3]*(1-sat)+l*sat}
  local tl=math.max(1,luma(t));local target=212/tl
  local room=255/math.max(1,t[1],t[2],t[3]);local over=target-room
  t=mul(t,over>0 and room or target)
  if over>0 then local push=clamp(over*tl/255*.8,0,1);for i=1,3 do t[i]=t[i]*(1-push)+255*push end end
  return t
end
function M.new(r,g,model,theme,options)
  local v=setmetatable({r=r,g=g,model=model,theme=theme,options=options or {},hits={},order={},prev_cap=g.mouse_cap or 0,
    mapping=Model.volume_mapping(r),fx_offset=0,send_offset=0,held={0,0},peak=0,last_time=r.time_precise(),
    ox=0,prefix='',choice={}},M)
  v.root=v
  -- The output strip is the same drawing code with its own scroll/meter state, offset and hit prefix.
  v.out=setmetatable({fx_offset=0,send_offset=0,held={-150,-150},peak=0,last_time=r.time_precise(),ox=0,prefix='out:'},{__index=v})
  return v
end
-- Where the inspected track's signal goes next: the send destination last clicked for it, else its
-- parent folder, else the master.
function M:output_target(s)
  local r=self.r
  if s.master or not r.GetMasterTrack then return nil end
  local chosen=self.choice[s.guid]
  if chosen~=nil then
    for _,send in ipairs(s.sends) do if send.kind=='send' and send.dest==chosen then return chosen,send end end
  end
  return s.parent or r.GetMasterTrack(s.project)
end
function M:output_menu(s)
  local m=self.model;local root=self.root
  self:menu({{s.parent and 'Parent send' or 'Master send',function() m:toggle(s,'B_MAINSEND') end,checked=s.B_MAINSEND~=0},{''},
    {'Show output strip',function() if root.options.set_output then root.options.set_output(not root:output_enabled()) end end,checked=root:output_enabled()},
    {'Show track routing window',function() self:show_routing(s) end}})
end
-- REAPER offers scripts no in-place text field, so renaming uses its small input dialog.
function M:rename(s)
  local r=self.r;local current=self.model:track_name(s)
  if current==nil or not r.GetUserInputs then return end
  self.root.drag=nil
  local ok,name=r.GetUserInputs('Rename track',1,'Track name:,extrawidth=220,separator=\n',current)
  if ok and name~=current then self.model:rename(s,name) end
end
function M:output_enabled() return self.options.output_strip~=false end
function M:px(v) return math.floor(v*self.scale+.5) end
function M:pxx(v) return self:px(v+self.ox) end -- horizontal position inside the current strip
-- Edges are snapped to device pixels so neighbouring fills and sprites never leave seams.
function M:rect(x,y,w,h,c)
  local g=self.g;local X,Y=self:pxx(x),self:px(y)
  g.set(c[1]/255,c[2]/255,c[3]/255,(c[4] or 255)/255);g.rect(X,Y,self:pxx(x+w)-X,self:px(y+h)-Y,1);g.a=1
end
-- align: 0 left, 1 centred (falls back to left when the text is too wide), 2 right
function M:text(text,x,y,w,h,c,font,align)
  local g,s=self.g,self.scale;text=tostring(text):gsub('[\r\n\t]',' ')
  g.setfont(font=='list' and 2 or font=='header' and 3 or font=='bold' and 4 or 1)
  local flags=4
  if align==2 then flags=6 elseif align==1 and g.measurestr(text)<=w*s then flags=5 end
  g.set(c[1]/255,c[2]/255,c[3]/255,(c[4] or 255)/255);g.x=self:pxx(x);g.y=self:px(y)
  g.drawstr(text,flags,self:pxx(x+w),self:px(y+h));g.a=1
end
function M:hit(id,x,y,w,h,action,menu)
  id=self.prefix..id -- hits are stored in panel coordinates; strips draw in their own
  local hit={id=id,x=x+self.ox,y=y,w=w,h=h,action=action,menu=menu}
  self.hits[id]=hit;self.order[#self.order+1]=hit;return hit
end
function M:sprite(name,state,x,y,w,h)
  return self.bitmaps and self.bitmaps:draw(name,state,x+self.ox,y,w,h,self.scale)
end
-- Labels and lit colours for controls drawn without theme art.
local PLAIN={mcp_mute_off={'M'},mcp_mute_on={'M',{255,82,82}},mcp_solo_off={'S'},mcp_solo_on={'S',{255,214,64}},
  mcp_recarm_off={'rec'},mcp_recarm_on={'rec',{255,70,70}},
  mcp_monitor_off={'in'},mcp_monitor_on={'in',{120,220,120}},mcp_monitor_auto={'in',{255,190,90}},
  mcp_phase_norm={'ø'},mcp_phase_inv={'ø',{255,190,90}},
  mcp_fx_norm={'FX',{120,220,120}},mcp_fx_dis={'FX',{255,82,82}},mcp_fx_empty={'FX'},
  track_fxon_v={'on',{120,220,120}},track_fxoff_v={'off',{255,82,82}},track_fxempty_v={'on'},
  mcp_recmode_in={'in'},mcp_recmode_out={'out'},mcp_recmode_off={'off'},
  mcp_env={'trim'},mcp_env_read={'read',{120,220,120}},mcp_env_touch={'touch',{255,214,64}},mcp_env_write={'write',{255,82,82}},
  mcp_env_latch={'latch',{190,140,255}},mcp_env_preview={'prev',{110,190,255}}}
for _,n in ipairs({'mcp_io','mcp_io_dis','mcp_io_r','mcp_io_r_dis','mcp_io_s','mcp_io_s_dis','mcp_io_s_r','mcp_io_s_r_dis'}) do PLAIN[n]={'I/O'} end
function M:button(id,name,x,y,w,h,action,menu)
  local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
  local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
  local bm=self.bitmaps
  local drawn
  if bm and bm.theme.layout=='generic' then
    if bm.full_artwork then drawn=bm:draw(name,state,x+self.ox,y,w,h,self.scale,true) end
    if not drawn then drawn=bm:generic_button(name,state,x+self.ox,y,w,h,self.scale) end
  elseif bm and bm.theme.compact6 and (id=='B_MUTE' or id=='B_PHASE') then
    drawn=bm:draw(name,state,x+self.ox,y,w,h,self.scale,true)
    if not drawn then
      local track=name:gsub('^mcp_','track_')
      local base=bm:get(track,true)
      local overlay=bm:get(track..'_ol',true)
      -- PhaseLab's 4x4 base is transparent; its glyph lives in the overlay.
      if base and (base.w>=6 or overlay) then
        bm:draw(track,state,x+self.ox,y,w,h,self.scale,true)
      end
      drawn=overlay and bm:draw(track..'_ol',state,x+self.ox,y,w,h,self.scale,true) or (base and base.w>=6)
    end
  else
    drawn=self:sprite(name,state,x,y,w,h)
    -- Overlay-built themes keep part of a control in a larger "_ol" image (PhaseLab's record-arm
    -- surround, its solo glyph). Only art whose guide lines declare that reach is an overlay.
    local ol=bm and bm.theme.stock6 and bm:get(name..'_ol',true)
    if ol and ol.x==1 and bm:draw(name..'_ol',state,x+self.ox,y,w,h,self.scale,true) then drawn=true end
  end
  if not drawn then -- no usable art for this theme: a plain labelled button
    local p=PLAIN[name] or {''}
    self:rect(x+1,y+1,w-2,h-2,state==2 and {30,30,30} or state==1 and {78,78,78} or {62,62,62})
    self:rect(x+1,y+1,w-2,1,{255,255,255,20})
    self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
  end
  return self:hit(id,x,y,w,h,action,menu)
end
-- items: {text,fn,checked=,sub=}; text '' is a separator. Returns after running the chosen fn.
function M:menu(items)
  local parts,fns={},{}
  local function clean(t) return (tostring(t):gsub('[|\r\n]','/'):gsub('^[!#<>]+','')) end
  local function add(list)
    for i,it in ipairs(list) do
      if it.sub then
        parts[#parts+1]='>'..clean(it[1]);add(it.sub)
      elseif it[1]=='' then parts[#parts+1]=''
      else
        parts[#parts+1]=(i==#list and list~=items and '<' or '')..(it.checked and '!' or '')..(it[2] and '' or '#')..clean(it[1])
        fns[#fns+1]=it[2] or false
      end
    end
  end
  add(items)
  local g=self.g;g.x,g.y=g.mouse_x or 0,g.mouse_y or 0
  self.root.drag=nil
  local choice=g.showmenu(table.concat(parts,'|'))
  local fn=fns[math.floor(choice or 0)]
  if fn then fn() end
end
function M:note(text) self.root.notice={text=text,until_time=self.r.time_precise()+4} end
function M:input_label(v)
  local r=self.r;v=math.floor(v)
  if v<0 then return 'None' end
  if v>=4096 then
    local ch,dev=v&31,(v>>5)&127
    local name=dev==63 and 'All' or dev==62 and 'Virtual keyboard' or nil
    if not name then local ok,n=r.GetMIDIInputName(dev,'');name=n~='' and n or ('Device '..(dev+1)) end
    return 'MIDI: '..name..': '..(ch==0 and 'All channels' or 'Channel '..ch)
  end
  local i=v&1023
  local function ch(n) local name=r.GetInputChannelName and r.GetInputChannelName(n);return name and name~='' and name or ('Input '..(n+1)) end
  return (v&1024)~=0 and (ch(i)..' / '..ch(i+1)) or ch(i)
end
function M:input_menu(s)
  local r,cur=self.r,math.floor(s.I_RECINPUT)
  local function pick(v) return function() self.model:set(s,'I_RECINPUT',v) end end
  local function item(text,v) return {text,pick(v),checked=cur==v} end
  local items={item('None',-1),{''}}
  local n=math.min(r.GetNumAudioInputs and r.GetNumAudioInputs() or 0,64)
  local mono,stereo={},{}
  for i=0,n-1 do mono[#mono+1]=item(self:input_label(i),i) end
  for i=0,n-2 do stereo[#stereo+1]=item(self:input_label(1024+i),1024+i) end
  if #mono>0 then items[#items+1]={'Input: Mono',sub=mono} end
  if #stereo>0 then items[#items+1]={'Input: Stereo',sub=stereo} end
  local midi={item('All MIDI inputs: All channels',4096+(63<<5)),item('Virtual MIDI keyboard: All channels',4096+(62<<5))}
  for d=0,(r.GetNumMIDIInputs and r.GetNumMIDIInputs() or 0)-1 do
    local ok,name=r.GetMIDIInputName(d,'')
    if ok then
      local chans={item('All channels',4096+(d<<5))}
      for c=1,16 do chans[#chans+1]=item('Channel '..c,4096+(d<<5)+c) end
      midi[#midi+1]={name,sub=chans}
    end
  end
  items[#items+1]={'Input: MIDI',sub=midi}
  self:menu(items)
end
-- Mirrors the order of REAPER's own slot menu. Entries REAPER offers no script access to
-- (quick add, FX chains, replace, multi-mono, embedded UI, parameter panel) are left out.
function M:fx_menu(s,fx,row)
  local m,r=self.model,self.r
  local n=#s.fx
  local items={{'Add FX...',function() self:add_fx(s) end},{''},{'Add container',function() m:add_container(s) end}}
  if fx then
    local par=0
    if r.TrackFX_GetNamedConfigParm then local ok,v=r.TrackFX_GetNamedConfigParm(s.track,fx.index,'parallel');par=ok and tonumber(v) or 0 end
    local can=fx.index>0
    items[#items+1]={'Run FX in parallel with previous FX',can and function() m:fx_parallel(s,fx,par==1 and 0 or 1) end,checked=par==1}
    items[#items+1]={'Run FX in parallel with previous FX (merge MIDI)',can and function() m:fx_parallel(s,fx,par==2 and 0 or 2) end,checked=par==2}
  end
  items[#items+1]={''}
  local at=fx and fx.index+1 or n
  items[#items+1]={'Paste FX',m.clip and function() m:fx_paste(s,at) end}
  if fx then
    items[#items+1]={'Copy FX',function() m:fx_copy(s,fx,false) end}
    items[#items+1]={'Cut FX',function() m:fx_copy(s,fx,true) end}
    items[#items+1]={''}
    items[#items+1]={'Float FX configuration',function() m:open_fx(s,fx) end}
  else items[#items+1]={''} end
  items[#items+1]={'Show FX chain',function() m:fx_chain(s,fx) end}
  items[#items+1]={''}
  items[#items+1]={'Bypass chain',function() m:toggle(s,'I_FXEN') end,checked=s.I_FXEN==0}
  if fx then
    items[#items+1]={'Bypass FX',function() m:fx_edit(s,fx,'bypass') end,checked=not fx.enabled}
    items[#items+1]={'Offline FX',function() m:fx_edit(s,fx,'offline') end,checked=fx.offline}
    items[#items+1]={'Delete FX',function() m:fx_edit(s,fx,'delete') end}
    items[#items+1]={'Rename FX instance',function()
      local ok,name=r.GetUserInputs('Rename FX instance',1,'Name (empty = original):,extrawidth=220,separator=\n',fx.label or '')
      if ok then m:fx_rename(s,fx,name) end
    end}
    items[#items+1]={''}
    items[#items+1]={'Bypass FX slot for selected tracks',function() m:fx_slot_bypass(s,fx,false) end}
    items[#items+1]={'Bypass FX slot for all tracks',function() m:fx_slot_bypass(s,fx,true) end}
  end
  self:menu(items)
end
function M:add_fx(s)
  local _,why=self.model:add_fx(s)
  if why=='chain' then self:note('Click this track in REAPER once for the Add FX window') end
end
function M:show_routing(s)
  local ok,why=self.model:routing(s)
  if not ok and why=='touch' then self:note('Click this track in REAPER once, then retry') end
end
function M:send_menu(s,send)
  local m=self.model;local targets={}
  for _,t in ipairs(m:send_targets(s)) do
    targets[#targets+1]={('%d: %s'):format(t.number,t.name),function() m:add_send(s,t.track) end}
  end
  local items={}
  local track_send=send and send.kind=='send'
  if send then
    items={{'Mute send',track_send and function() m:send_edit(s,send,'mute') end,checked=send.mute==true},
      {'Remove send',track_send and function() m:send_edit(s,send,'remove') end},{''},
      {'Mute send slot for selected tracks',track_send and function() m:send_slot_mute(s,send,false) end},
      {'Mute send slot for all tracks',track_send and function() m:send_slot_mute(s,send,true) end},{''}}
  end
  items[#items+1]={'Show track routing window',function() self:show_routing(s) end}
  if send then items[#items+1]={'Go to send destination track',track_send and function() m:goto_send_dest(s,send) end} end
  if #targets>0 then items[#items+1]={''};items[#items+1]={'Add send to',sub=targets} end
  self:menu(items)
end
function M:draw(s)
  local W,H=self.width,self.height;self.hits={};self.order={}
  self.ox=0
  self:rect(0,0,W,H,{38,38,38})
  if not s then
    self.out_snapshot=nil
    self:text('Select a track',4,40,W-8,20,{200,200,200},'main',1)
    self:text('Right-click for options',4,62,W-8,20,{120,120,120},'main',1);return
  end
  -- Two native-width strips need 172 pt; a narrower panel shows only the inspected track.
  local target,via=nil,nil
  if self:output_enabled() and W>=2*STRIP then target,via=self:output_target(s) end
  local o=target and self.model:output_snapshot(s,target) or nil
  self.out_snapshot=o;self.shown_send=o and via or nil;self.shown_main=o~=nil and via==nil
  local W1=o and math.floor(W/2) or W
  self:strip(s,W1,H)
  if o then
    local out=self.out
    if out.last_guid~=o.guid then out.last_guid=o.guid;out.fx_offset=0;out.send_offset=0;out.held={-150,-150};out.peak=0 end
    out.ox=W1;out.hits=self.hits;out.order=self.order
    out.mx=self.mx-W1;out.my=self.my
    out:strip(o,W-W1,H)
    self:rect(W1-.5,0,.5,H,{20,20,20})
  end
  local status=self.options.status
  if (not status or status=='') and self.theme and self.theme.error then status=self.theme.error end
  if self.notice and self.r.time_precise()<self.notice.until_time then status=self.notice.text end
  if status and status~='' then
    self:rect(0,0,W,16,{20,20,20,235});self:text(status,3,0,W-6,16,{233,154,104},'main',0)
  end
end
-- Pan pointer: REAPER draws the knob position itself, the art is only the cap.
function M:pointer(s,kx,ky,size,color,thin,value)
  local g,sc=self.g,self.scale
  size=size or 24;color=color or {178,178,178}
  local ang=clamp(value or s.D_PAN,-1,1)*math.pi*.75-math.pi/2
  local cx,cy=self:pxx(kx+size/2),self:px(ky+size/2)
  local dx,dy=math.cos(ang),math.sin(ang)
  g.set(color[1]/255,color[2]/255,color[3]/255,1)
  local hw=(thin and .45 or 1)*sc
  local r1,r2=(thin and 2.5 or 5.5)*size/24,10*size/24
  local x1,y1,x2,y2=cx+dx*r1*sc,cy+dy*r1*sc,cx+dx*r2*sc,cy+dy*r2*sc
  if g.triangle then
    g.triangle(x1-dy*hw,y1+dx*hw,x1+dy*hw,y1-dx*hw,x2+dy*hw,y2-dx*hw,x2-dy*hw,y2+dx*hw)
  elseif thin then g.line(x1,y1,x2,y2,1)
  else
    for o=-hw+.5,hw-.5 do g.line(x1-dy*o,y1+dx*o,x2-dy*o,y2+dx*o,1) end
  end
  g.a=1
end
local function pan_label(v)
  local pct=math.floor(math.abs(v)*100+.5)
  return pct==0 and 'center' or (pct..'%'..(v<0 and 'L' or 'R'))
end
function M:pan_hit(s,key,x,y,w,h,span)
  local hit=self:hit(key,x,y,w,h)
  hit.kind,hit.token,hit.pan_span=key,s,span
end
function M:pan_cap(name,cx,cy,fallback,last)
  local bm=self.bitmaps
  local w,h
  if bm then w,h=bm:size(name,true) end
  if not w and bm and fallback then name=fallback;w,h=bm:size(name,true) end
  if not w and bm and last then name=last;w,h=bm:size(name,true) end
  if w and h then bm:draw(name,0,cx-w/2+self.ox,cy-h/2,nil,nil,self.scale,true);return w end
  if self.g.circle then
    self.g.set(.2,.2,.2,1);self.g.circle(self:pxx(cx),self:px(cy),self:px(9),1,1)
  end
  return 20
end
-- A theme can supply the pan position as a stack of marker frames; REAPER then draws no line.
function M:pan_marker(cx,cy,value,fit)
  local bm=self.bitmaps;local p=(clamp(value,-1,1)+1)/2
  return bm and (bm:knob_frame('mcp_pan_knob_stack',p,cx+self.ox,cy,self.scale,fit)
    or bm:knob_frame('tcp_pan_knob_stack',p,cx+self.ox,cy,self.scale,fit))
end
function M:pan_knob7(s,cx,cy)
  local size=self:pan_cap('mcp_pan_knob_small',cx,cy,'tcp_pan_knob_small','gen_knob_bg_small')
  if self:pan_marker(cx,cy,s.D_PAN) then return end
  self:pointer(s,cx-size/2,cy-size/2,size,{60,60,60},true)
end
function M:pan_dot(cx,cy,size,value)
  local a=clamp(value,-1,1)*math.pi*.75-math.pi/2
  self.g.set(.15,.15,.15,1)
  if self.g.circle then self.g.circle(self:pxx(cx+size*.32*math.cos(a)),self:px(cy+size*.32*math.sin(a)),self:px(1),1,1) end
end
function M:width_marker(cx,cy,value)
  local bm=self.bitmaps;local p=(value+1)/2
  return bm and (bm:knob_frame('mcp_wid_knob_stack',p,cx+self.ox,cy,self.scale)
    or bm:knob_frame('tcp_wid_knob_stack',p,cx+self.ox,cy,self.scale))
end
function M:width_ring(cx,cy,size,value)
  local g=self.g;local r=size*.48
  local function point(a) return self:pxx(cx+r*math.cos(a)),self:px(cy+r*math.sin(a)) end
  g.set(.93,.72,.22,1)
  local x,y=point(-math.pi/2)
  for i=1,math.ceil(math.abs(clamp(value,-1,1))*24) do
    local f=math.min(i/24,math.abs(value))
    local xx,yy=point(-math.pi/2+f*(value<0 and -1 or 1)*math.pi*1.5)
    g.line(x,y,xx,yy,1);x,y=xx,yy
  end
end
-- The layouts supply the vertical anchors; selected and output strips share controls.
function M:pan_pair(s,W,y,labelY,c,default7)
  local bm=self.bitmaps
  local stock=default7 or (self.theme and self.theme.stock6)
  local generic=not self.theme or self.theme.layout=='generic'
  local function art(name,x,yy,w,h)
    return bm and (not generic or bm.full_artwork) and bm:draw(name,0,x+self.ox,yy,w,h,self.scale,true)
  end
  if s.I_PANMODE==6 then
    local x,w=7,W-14
    for i,key in ipairs({'D_DUALPANL','D_DUALPANR'}) do
      local yy=y+(i-1)*10
      if not art(i==1 and 'mcp_panbg' or 'mcp_widthbg',x,yy,w,9) then
        self:rect(x,yy+3,w,4,{42,42,42})
      end
      local value=clamp(s[key],-1,1);local cx=x+5+(value+1)/2*(w-10)
      if not art(i==1 and 'mcp_panthumb' or 'mcp_widththumb',cx-4,yy,8,9) then
        self:rect(cx-3,yy,6,9,{170,170,170})
      end
      self:pan_hit(s,key,x,yy,w,10,w-10)
      if labelY then self:text(pan_label(value),(i-1)*W/2,labelY,W/2,13,c,'main',1) end
    end
    return
  end
  local backing=default7 and bm and bm:get('mcp_width_knob_small',true)
  -- The left half of the stock pill is yellow-guide overhang, not part of its hit target.
  if backing and backing.w/backing.scale>30 and backing.w>=backing.h*1.75 then
    local offset=(backing.over[1]-backing.over[3])/(2*backing.scale)
    self:pan_cap('mcp_width_knob_small',W/2+offset,y+10)
  else backing=nil end
  for i,key in ipairs({'D_PAN','D_WIDTH'}) do
    local cx=W/2+(i==1 and -1 or 1)*(default7 and 11 or (self.theme and self.theme.stock6 and 15.5 or 14))
    local name=i==1 and 'mcp_pan_knob_small' or 'mcp_width_knob_small'
    if i==1 and default7 then
      self:pan_knob7(s,cx,y+10)
    elseif i==2 and backing then
      if not self:width_marker(cx,y+10,s[key]) then self:pan_dot(cx,y+10,11,s[key]) end
    else
      local size=self:pan_cap(name,cx,y+10,default7 and 'gen_knob_bg_small' or nil)
      local marked
      if i==2 then marked=self:width_marker(cx,y+10,s[key])
      elseif self.theme and self.theme.compact6 then marked=self:pan_marker(cx,y+10,s[key])
      elseif bm and bm.full_artwork then marked=self:pan_marker(cx,y+10,s[key],size) end
      if not marked then
        if i==2 and self.theme and (self.theme.layout=='reapertips2' or self.theme.layout=='reapertips' and not self.theme.stock6) then
          self:width_ring(cx,y+10,size,s[key])
        end
        local color=i==2 and self.theme and self.theme.stock6 and {255,255,255} or stock and {55,55,55} or nil
        self:pointer(s,cx-size/2,y+10-size/2,size,color,stock,s[key])
      end
    end
    local hitW=default7 and 22 or 24
    self:pan_hit(s,key,cx-hitW/2,y-1,hitW,22)
    if labelY then
      local label=i==1 and pan_label(s[key]) or ('%dW'):format(math.floor(s[key]*100+.5))
      self:text(label,(i-1)*W/2,labelY,W/2,13,c,'main',1)
    end
  end
end
-- Reapertips v1.95 strip from the FX button down: the theme's own geometry (rtconfig drawMcp, wide
-- mode, labels on, default Theme Adjuster values) in strip coordinates. `c` carries what the racks computed.
function M:lower2(s,W,H,c)
  local m,T,L,B=self.model,c.T,c.L,c.B
  local w=W-1
  local pad=math.min(7,math.floor(w*.06+.5))
  local colw=21+pad
  -- Panel and footer colour: grey tinted towards the track colour, dimmed, then brightened for a
  -- selected track, by the amounts this theme variant declares.
  local th=self.theme;local grey={130,130,130}
  local function tone(tint,dim,sel)
    local t,d,k=c.custom and th.param(tint,100)/100 or 0,th.param(dim,20)/100,th.param(sel,0)/100
    local out={}
    for i=1,3 do out[i]=((grey[i]*(1-t)+c.base[i]*t)*(1-d))*(1-k)+255*k end
    return out
  end
  local base=c.custom and c.base or grey
  local panel=tone('mcp_tint_sel_strength','mcp_dim_sel_strength','mcp_sel_strength')
  local idx=tone('mcp_idx_tint_strength','mcp_idx_dim_strength','mcp_idx_sel_strength')
  local thres=th.param('text_luma_thres',100)
  local bright,dark=c.custom and {230,230,230} or {220,220,220},{23,23,23}
  local ptext=luma(panel)<=thres and bright or dark
  local itext=luma(idx)<=thres and bright or dark
  local fxbg=th.version>1 and {61,61,61} or {51,51,51}
  local body=th.version>2 and {46,46,46} or {38,38,38}
  -- The theme shows more of the pan/input panel as the strip gets taller.
  local labels=L>=318
  local panh=labels and 46 or 30
  local inh=L<418 and 22 or 42
  local P=T+32;local IN=P+panh;local S=IN+inh;local SH=B-S
  local vp=SH>=360 and 4 or SH>=270 and 3 or 2
  self.layout={T=T,S=S,B=B,L=L,meter=c.meter}

  -- FX button row with the selected-track handle
  self:rect(0,T+.5,W,.5,{255,255,255,26})
  self:rect(0,T+1,W,31,fxbg)
  self:rect(0,T+2,W,4,mul(base,c.custom and .7 or .75));self:rect(0,T+2,W,1,{255,255,255,75});self:rect(0,T+5,W,1,{0,0,0,110})
  local fxon=s.I_FXEN~=0
  self:button('FX',#s.fx==0 and 'mcp_fx_empty' or fxon and 'mcp_fx_norm' or 'mcp_fx_dis',pad,T+9,w-3*pad-13,20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  self:button('I_FXEN',#s.fx==0 and 'track_fxempty_v' or fxon and 'track_fxon_v' or 'track_fxoff_v',w-13-2*pad,T+9,13+pad,20,
    function() m:toggle(s,'I_FXEN') end)

  -- Pan and input panel
  self:rect(0,P,W,S-P,panel)
  self:sprite('custom_mcp_sel_gradient',0,0,P,W,50)
  self:rect(0,P,W,1,{255,255,255,22});self:rect(W-1,P+1,1,S-P-1,{255,255,255,22})
  local kx,ky=w/2-12,P+(labels and 18 or 16)-12
  if s.I_PANMODE==5 or s.I_PANMODE==6 then
    self:pan_pair(s,W,ky+2,labels and ky+23 or nil,ptext)
  else
    self:sprite('mcp_pan_knob_large',0,kx,ky,24,24)
    self:pointer(s,kx,ky)
    if labels then self:text(pan_label(s.D_PAN),0,ky+24,w,18,ptext,'main',1) end
    self:pan_hit(s,'D_PAN',kx-2,ky-2,28,labels and 40 or 28)
  end
  local function dropdown(x,y,dw)
    self:sprite('custom_mcp_dropdown_bg',0,x,y,dw,15)
    if dw>=40 then self:sprite('custom_mcp_dropdown_arrow',0,x+dw-12,y+3,8,8) end
  end
  if not s.master then
    local rm=math.floor(s.I_RECMODE)
    local mw=w-colw-13                                    -- the short box beside the record-arm notch
    local ix,iy,iw=5,S-19,mw
    if inh>=42 then
      ix,iy,iw=5,IN+2,w-10
      dropdown(5,S-20,mw)
      self:sprite(rm==2 and 'mcp_recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'mcp_recmode_in' or 'mcp_recmode_out',0,5,S-20)
      self:hit('I_RECMODE',5,S-20,mw,15,function()
        local items={}
        for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
        self:menu(items)
      end)
    end
    -- On shorter strips the theme keeps only the input box, in the record-mode position.
    dropdown(ix,iy,iw)
    self:text(self:input_label(s.I_RECINPUT),ix+4,iy,iw-(iw>=40 and 19 or 7),15,{225,225,225},'main',0)
    self:hit('I_RECINPUT',ix,iy,iw,15,function() self:input_menu(s) end)
  end

  -- Fader section: volume readout, meter, fader, button column
  self:rect(0,S,W,H-S,body)
  local col=w-colw
  local rest=w-colw-21-pad
  local meter=rest>=14
  local fxl=meter and rest or math.max(2,(col-21)/2)
  local ftop,fbot=S+23,B
  self:text(gaintext(s.D_VOL),fxl-14,S+3,49,20,th.version>1 and {200,200,200} or {100,100,100},'main',1)
  if meter then
    local mp=math.floor(math.min((rest-2)*.09,pad))
    self:meter(s,{x=1+mp,y=ftop,w=rest-2-2*mp,h=SH-23},c.colors)
  end
  self:sprite('mcp_volbg',0,fxl,ftop,21,fbot-ftop)
  local top,bottom=ftop+21.5,fbot-21.5
  local fy=bottom-self.mapping.to_position(s.D_VOL)*(bottom-top)
  self:sprite('mcp_volthumb',0,fxl-1,fy-25.5)
  local hit=self:hit('D_VOL',fxl-2,ftop-4,25,fbot-ftop+8)
  hit.kind,hit.token='D_VOL',s
  hit.top,hit.bottom,hit.fader_y=top,bottom,fy
  local y=S+3+vp
  if not s.master then
    self:sprite('custom_mcp_recarm_bg',0,col-4,S-17,math.min(29,W-(col-4)),23)
    self:button('I_RECARM',s.I_RECARM~=0 and 'mcp_recarm_on' or 'mcp_recarm_off',col,S-15,21,21,function() m:toggle(s,'I_RECARM') end)
    self:button('I_RECMON',s.I_RECMON==2 and 'mcp_monitor_auto' or s.I_RECMON==1 and 'mcp_monitor_on' or 'mcp_monitor_off',col,y,21,20,function() m:toggle(s,'I_RECMON') end)
  end
  y=y+19+vp
  self:button('B_MUTE',s.B_MUTE~=0 and 'mcp_mute_on' or 'mcp_mute_off',col,y,21,20,function() m:toggle(s,'B_MUTE') end)
  y=y+21+vp
  if not s.master then self:button('I_SOLO',s.I_SOLO~=0 and 'mcp_solo_on' or 'mcp_solo_off',col,y,21,20,function() m:toggle(s,'I_SOLO') end) end
  -- The theme drops routing, polarity and envelope in that order as the strip gets shorter.
  if SH>=106 then
    local io='mcp_io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
    self:button('IO',io,col-1,y+23+vp,23,30,function() self:show_routing(s) end,function() self:send_menu(s) end)
  end
  if SH>=123 and not s.master then
    self:button('B_PHASE',s.B_PHASE~=0 and 'mcp_phase_inv' or 'mcp_phase_norm',col+3,B-17,16,18,function() m:toggle(s,'B_PHASE') end)
  end
  if SH>=142 then
    local mode=math.floor(s.I_AUTOMODE)
    self:button('I_AUTOMODE',ENV[mode] or 'mcp_env',col+1,B-17-19-vp,20,20,function()
      local items={}
      for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
      self:menu(items)
    end)
  end

  -- Name, selected-track bar and track number
  self:text(s.name,2.5,B+.5,W-7,26,{235,235,235},'header',1)
  if not s.master then self:hit('name',0,B,W,26).double=function() self:rename(s) end end
  self:rect(0,B+26,W,21,idx)
  self:rect(0,B+26,W,1,{255,255,255,22})
  self:rect(0,B+22,w,4,body);self:rect(0,B+23,w,2,{234,234,234})
  self:text(s.master and '' or ('%d'):format(s.IP_TRACKNUMBER),0,B+26,W-2,20,itext,'main',1)
end
-- REAPER Default 7 strip from the input box down: the theme's "normal width" mixer form (rtconfig
-- drawMcp, layout A) in strip coordinates, using the Theme Adjuster values in force.
function M:lower3(s,W,H,c)
  local m,th,bm,T,L=self.model,self.theme,self.bitmaps,c.T,c.L
  local function P(name,fallback) return th.param(name,fallback) end
  local verbose=P('LayoutA-verboseMcp',0)~=0
  local tb=P('textBrightness',100)/100
  local function grey(v) v=math.min(255,v*tb);return {v,v,v} end
  -- Strip colour: theme grey, tinted by a custom track colour, lightened for the selected track.
  local bg={P('mcpBgColR',129),P('mcpBgColG',137),P('mcpBgColB',137)}
  local ratio=c.custom and P('customColorDepthParam',30)/100 or 0
  local sel=P('selectStrength',25)/100
  local main={}
  for i=1,3 do main[i]=(c.base[i]*ratio+bg[i]*(1-ratio))*(1-sel)+255*sel end
  local bright=(main[1]*299+main[2]*587+main[3]*114)/1000
  local dark={38,38,38}
  -- The theme compares these two thresholds with the strip height in device pixels, whatever the display scale.
  local topH=(L*self.scale>P('LayoutA-mcpNormalShowSecIn',300)) and 50 or 0
  local panH=L*self.scale<P('LayoutA-mcpNormalShowSecPan',200) and 0 or (verbose and 46 or 30)
  local Y1=T+topH;local D=Y1+panH;local B=H-44
  local bw=32                                             -- button column
  self.layout={T=T,S=D,B=B,L=L,meter=true}
  local function art(name,state,x,y,w,h,crop)             -- a control's image plus its overlay, if the theme has one
    local ok=bm and bm:draw(name,state,x+self.ox,y,w,h,self.scale,true,crop)
    if bm and bm:draw(name..'_ol',state,x+self.ox,y,w,h,self.scale,true,crop) then ok=true end
    return ok
  end
  local function button(id,name,x,y,w,h,action,menu,crop)
    local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
    local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h,crop) then
      local p=PLAIN[name] or PLAIN[name:gsub('^track_','mcp_')] or {''}
      self:rect(x+1,y+1,w-2,h-2,state==1 and {78,78,78} or {62,62,62});self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end

  self:rect(0,T,W,L,main)
  self:rect(0,D,W-bw,B-D,dark)
  if P('LayoutA-mcpNormalDarkButtons',1)~=0 then self:rect(W-bw,D,bw,B-D,dark) end

  -- Input section
  if topH>0 and not s.master then
    art('dropdownBg_h',0,6,T+6,W-12,20);art('mcp_recinput',0,6,T+6,W-12,20)
    self:text(self:input_label(s.I_RECINPUT),10,T+7,W-36,19,grey(235),'main',0)
    self:hit('I_RECINPUT',6,T+6,W-12,20,function() self:input_menu(s) end)
    local rm=math.floor(s.I_RECMODE)
    art('dropdownBg_h',0,6,T+30,40,20)
    button('I_RECMODE',rm==2 and 'mcp_recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'mcp_recmode_in' or 'mcp_recmode_out',6,T+30,40,20,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    button('INFX',(s.recfx or 0)>0 and 'track_fx_in_norm' or 'track_fx_in_empty',W-26,T+30,20,20,function() m:open_input_fx(s) end)
  end

  -- Pan section
  if panH>0 then
    local ptext=grey(bright<150 and 220 or 38)
    local ky=Y1+(verbose and 18 or 4);local kx=W/2-10
    if s.I_PANMODE==5 or s.I_PANMODE==6 then
      self:pan_pair(s,W,ky,verbose and Y1+2 or nil,ptext,true)
    else
      if verbose then self:text(pan_label(s.D_PAN),6,Y1+2,W-12,16,ptext,'main',1) end
      self:pan_knob7(s,W/2,ky+10)
      self:pan_hit(s,'D_PAN',kx-2,ky-2,24,24)
    end
  end

  -- Meter, fader, record arm and monitor
  local lab=verbose and 20 or 0
  local dw=W-bw
  if verbose then self:text((s.D_VOL>0 and db(s.D_VOL)>=0 and '+' or '')..gaintext(s.D_VOL)..'dB',0,D+6,dw,14,grey(150),'main',1) end
  local my,mh=D+6+lab,(B-D)-36-lab
  local mw=dw-32
  local showvals=(s.I_RECARM~=0 and P('LayoutA-mcpMeterValsRecarm',1) or P('LayoutA-mcpMeterValsSel',0))~=0
  if mw>=10 then self:meter(s,{x=4,y=my,w=mw,h=mh,labels=showvals,readout=P('LayoutA-mcpMeterReadout',1)~=0},c.colors) end
  local vx=dw-26
  art('mcp_volbg',0,vx,my,25,mh)
  local top,bottom=my+21.5,my+mh-21.5
  local fy=bottom-self.mapping.to_position(s.D_VOL)*(bottom-top)
  if not art('mcp_volthumb',0,vx+1,fy-25.5) then self:rect(vx+3,fy-15,19,30,{150,150,150}) end
  local hit=self:hit('D_VOL',vx,my-4,25,mh+8)
  hit.kind,hit.token='D_VOL',s
  hit.top,hit.bottom,hit.fader_y=top,bottom,fy
  if not s.master then
    button('I_RECARM',s.I_RECARM~=0 and 'track_recarm_on' or 'track_recarm_off',vx+.5,my+mh+4,24,20,function() m:toggle(s,'I_RECARM') end)
    if mw>=10 then
      button('I_RECMON',s.I_RECMON==2 and 'mcp_monitor_auto' or s.I_RECMON==1 and 'mcp_monitor_on' or 'mcp_monitor_off',4+mw/2-10,my+mh+4,20,20,function() m:toggle(s,'I_RECMON') end)
    end
  end

  -- Button column: each control follows the one above; whatever would pass the bottom is left out, as in the mixer.
  local bx,y=W-bw+6,D+6
  local function place(h,gap,draw)
    if gap then y=y+6 end
    if y+h+(gap and 6 or 0)<=B then draw(y) end
    y=y+h
  end
  place(20,false,function(py) button('B_MUTE',s.B_MUTE~=0 and 'track_mute_on' or 'track_mute_off',bx,py,20,20,function() m:toggle(s,'B_MUTE') end) end)
  place(20,false,function(py) if not s.master then button('I_SOLO',s.I_SOLO~=0 and 'track_solo_on' or 'track_solo_off',bx,py,20,20,function() m:toggle(s,'I_SOLO') end) end end)
  local tall=verbose and 32 or 22
  if P('LayoutA-mcpNormalShowRoute',1)~=0 then place(tall,true,function(py)
    local io='mcp_io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
    button('IO',io,bx,py,20,tall,function() self:show_routing(s) end,function() self:send_menu(s) end,not verbose and 22 or nil)
  end) end
  if P('LayoutA-mcpNormalShowSecFx',1)~=0 then place(36,true,function(py)
    local fxon=s.I_FXEN~=0
    button('FX',#s.fx==0 and 'mcp_fx_empty' or fxon and 'mcp_fx_norm' or 'mcp_fx_dis',bx,py,20,20,
      function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
    button('I_FXEN',#s.fx==0 and 'track_fxempty_v' or fxon and 'track_fxon_v' or 'track_fxoff_v',bx,py+20,20,16,function() m:toggle(s,'I_FXEN') end)
  end) end
  if P('LayoutA-mcpNormalShowEnv',1)~=0 then place(tall,true,function(py)
    local mode=math.floor(s.I_AUTOMODE)
    button('I_AUTOMODE',ENV[mode] or 'mcp_env',bx,py,20,tall,function()
      local items={}
      for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
      self:menu(items)
    end,nil,not verbose and 22 or nil)
  end) end
  if P('LayoutA-mcpNormalShowPhase',1)~=0 then place(16,true,function(py)
    if not s.master then button('B_PHASE',s.B_PHASE~=0 and 'mcp_phase_inv' or 'mcp_phase_norm',bx,py,20,16,function() m:toggle(s,'B_PHASE') end) end
  end) end

  -- Name and number
  local invert=P('selInvertLabels',1)~=0
  local armed=s.I_RECARM~=0
  local namebg=dark
  if invert then namebg={};for i=1,3 do namebg[i]=main[i]+(255-main[i])*100/255 end end
  self:rect(0,B,W,24,namebg)
  local ntext=invert and (armed and {180,0,10} or {38,38,38}) or armed and {255,80,100}
    or (c.custom and P('colorTrackLabels',1)~=0) and name_color(c.base) or grey(200)
  self:text(s.name,4,B,W-8,24,ntext,'header',1)
  if not s.master then self:hit('name',0,B,W,24).double=function() self:rename(s) end end
  local idx=c.custom and c.base or bg
  self:rect(0,B+24,W,20,idx)
  local ib=(idx[1]*299+idx[2]*587+idx[3]*114)/1000
  self:text(s.master and '' or ('%d'):format(s.IP_TRACKNUMBER),0,B+24,W,20,(c.custom and ib>128) and grey(50) or grey(230),'main',1)
  if P('selDot',1)~=0 then art('tcp_selectionDot_sel',0,W/2-4,B+20,8,8) end
  self:rect(0,T,.5,L,{0,0,0,P('mcpDivOpacity',80)})
end
-- 80gray strip from the FX button down: the theme's own rows (rtconfig, standard form, default
-- Theme Adjuster values) in strip coordinates. Its controls keep their size and move with the
-- strip width, as the theme's own width setting does. `c` carries what the racks computed.
function M:lower80(s,W,H,c)
  local m,th,bm,T=self.model,self.theme,self.bitmaps,c.T
  local G=th.gray80
  local d=W-46                                            -- the theme's "manual stretch" over its 46 pt base
  local bar=clamp(th.param('p_mcp_indicator_width',3),0,5);if bar>0 then bar=bar+1 end
  local dia=s.master and 0 or clamp(th.param('p_mcp_diagram_height',16),0,64) -- the master has no routing-diagram row
  local top=T+1;local RS=top+43;local IDX=H-dia-16;local BAR=IDX-bar;local RB=BAR-16;local SH=RB-RS
  self.layout={T=T,S=RS,B=RB,L=H-T,meter=true}
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  -- Mixer controls fall back to the track panel's images, as in REAPER.
  local function art(name,state,x,y,w,h)
    return bm and (bm:draw('mcp_'..name,state,x+self.ox,y,w,h,self.scale,true)
      or bm:draw('track_'..name,state,x+self.ox,y,w,h,self.scale,true))
  end
  local function button(id,name,x,y,w,h,action,menu)
    local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
    local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local p=PLAIN['mcp_'..name] or {''}
      self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end

  -- Backgrounds: body, selection bar, number cell (the track's colour when it has one)
  self:rect(0,T,W,IDX-T,c.selected and G.bg_sel or G.bg or {45,45,45})
  self:rect(0,IDX,W,16,c.custom and c.base or c.selected and G.bg_sel or G.bg or {45,45,45})
  if dia>0 and not image('mcp_diagram_bg',0,H-dia,W,dia) then self:rect(0,H-dia,W,dia,{30,30,30}) end
  if bar>0 then self:rect(0,BAR-1,W,bar+1,c.selected and G.bar_sel or G.bar or {38,38,38}) end
  local itext=c.selected and G.idx_sel or G.idx or {160,159,147}
  if c.custom then
    local l=math.sqrt(c.base[1]^2*.299+c.base[2]^2*.587+c.base[3]^2*.114)
    itext=l>=140 and (G.on_light or {45,45,45}) or (G.on_dark or {242,240,236})
  end
  if s.master then -- the master's name sits in the number row; its name row holds the mixer's Menu art (not a control here)
    self:text(s.name,0,IDX+1,W,15,itext,'main',1)
    local a,sx,sy,sw,sh
    if bm then a,sx,sy,sw,sh=bm:frame('mixer_menu',0,true) end
    if a then -- wider than the strip: only the part inside it is shown, as in the mixer
      local x0=-54+d/2;local cut=math.max(0,-x0);local shown=math.min(sw/a.scale-cut,W-math.max(0,x0))
      local X=self:pxx(x0+cut)
      bm:blit(a,sx+math.floor(cut*a.scale+.5),sy,math.floor(shown*a.scale+.5),sh,X,self:px(RB),self:pxx(x0+cut+shown)-X,self:px(RB+sh/a.scale)-self:px(RB),true)
    end
  else
    self:text(('%d'):format(s.IP_TRACKNUMBER),0,IDX+1,W,15,itext,'main',1)
    self:text(s.name,2,RB,W-5,16,G.label or {211,208,200},'main',1)
    self:hit('name',0,RB,W,16).double=function() self:rename(s) end
  end

  -- Record arm, monitor and input FX climb from the bottom of the fader row
  local cx=28+d
  if not s.master then
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',cx,RB-14,14,14,function() m:toggle(s,'I_RECARM') end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',cx,RB-29,14,14,function() m:toggle(s,'I_RECMON') end)
    button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',cx,RB-44,14,14,function() m:open_input_fx(s) end)
  end

  -- Fader: the thumb's own image marks how far it may overhang the ends of its slot
  image('mcp_volbg',2,RS,16,SH)
  local thumb=bm and bm:get('mcp_volthumb',true)
  -- Its guide marks let it pass the slot's ends by 4 pt at the top and 3 pt at the bottom.
  local ftop,fbottom=RS+15.5,RB-16.5
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  local zero=fbottom-self.mapping.to_position(1)*(fbottom-ftop)
  self:rect(3,zero-.5,14,1,{30,30,30,133})
  if thumb then
    local tw,th_h=thumb.w/thumb.scale,thumb.h/thumb.scale
    bm:blit(thumb,thumb.x,thumb.y,thumb.w,thumb.h,self:pxx(10-tw/2+.5),self:px(fy-th_h/2+.5),self:px(tw),self:px(th_h),true)
  else self:rect(4,fy-15,12,30,{211,208,200}) end
  local hit=self:hit('D_VOL',2,RS,16,SH)
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy

  -- Meter in its own frame
  local mw=6+d
  image('mcp_custom_meter_bg',20,RS,mw,SH)
  self:meter(s,{x=23,y=RS+1,w=mw-6,h=SH-2,labels=false,readout_y=8.5,readout_color=G.readout,loudness_color=G.loudness},c.colors)

  -- Pan: one slider, or two small knobs in the stereo and dual pan modes
  local py=top+23
  if s.I_PANMODE>=5 then
    local dual=s.I_PANMODE==6
    for i,key in ipairs(dual and {'D_DUALPANL','D_DUALPANR'} or {'D_PAN','D_WIDTH'}) do
      local kx=i==1 and -3+d/3 or 12+d*.66
      local value=clamp(s[key],-1,1)
      if not (bm and bm:knob_frame('mcp_pan_knob_stack',(value+1)/2,kx+8.5+self.ox,py+8.5,self.scale)) then
        self:pointer(s,kx,py,17,nil,true,value)
      end
      self:pan_hit(s,key,kx,py,17,17)
    end
  else
    local pw=W-22
    image('mcp_panbg',2,py,pw,14)
    self:rect(2+pw/2-.5,py+2,1,10,{30,30,30,133})
    local pt=bm and bm:get('mcp_panthumb',true)
    -- Thumb travel stops 7.5 pt inside each end of the slot (measured in the mixer at hard left).
    local px=2+7.5+(clamp(s.D_PAN,-1,1)+1)/2*(pw-15)
    if pt then
      local tw,thh=pt.w/pt.scale,pt.h/pt.scale
      bm:blit(pt,pt.x,pt.y,pt.w,pt.h,self:pxx(px-tw/2-.5),self:px(py+7-thh/2+.5),self:px(tw),self:px(thh),true)
    else self:rect(px-4,py+2,8,10,{211,208,200}) end
    self:pan_hit(s,'D_PAN',2,py,pw,14,pw-15)
  end

  -- Mute, solo and routing down the right of the fader row
  local bx=26+d
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',bx,RS,18,18,function() m:toggle(s,'B_MUTE') end)
  -- This theme gives the master a solo button too.
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',bx,RS+18,18,18,function() m:toggle(s,'I_SOLO') end)
  -- The routing button is declared wider than the strip; REAPER shows the part that fits.
  local io='mcp_io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  local iw=W-bx
  local hover=inside({x=bx,y=RS+37,w=iw,h=20},self.mx,self.my)
  local a,sx,sy,sw,sh
  if bm then a,sx,sy,sw,sh=bm:frame(io,hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0,true) end
  if a then
    local X=self:pxx(bx);local shown=math.min(sw,math.floor(iw*a.scale+.5))
    bm:blit(a,sx,sy,shown,sh,X,self:px(RS+37),self:pxx(bx+shown/a.scale)-X,self:px(RS+37+sh/a.scale)-self:px(RS+37))
  else self:text('I/O',bx,RS+37,iw,20,{150,150,150},'main',1) end
  self:hit('IO',bx,RS+37,iw,20,function() self:show_routing(s) end,function() self:send_menu(s) end)

  -- Top row
  local fxon=s.I_FXEN~=0
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',-5+d/2,top+2,22,18,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',17+d/2,top+2,13,18,function() m:toggle(s,'I_FXEN') end)
  local mode=math.floor(s.I_AUTOMODE)
  button('I_AUTOMODE',(ENV[mode] or 'mcp_env'):gsub('^mcp_',''),23+d,top+3,22,18,function()
    local items={}
    for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
    self:menu(items)
  end)
  if not s.master then button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',29+d,top+22,13,18,function() m:toggle(s,'B_PHASE') end)
  else button('MONO',s.mono and 'mono' or 'stereo',26+d,top+22,18,18,function() m:master_mono(s) end) end

  -- Divider lines, then the routing diagram row (drawn for a track outside any folder)
  local sel=c.selected and '_sel' or ''
  image('track_divider_r'..sel,0,T,W,H-dia-T);image('track_divider_t'..sel,0,T,W,H-dia-T)
  image('track_divider_b_out'..sel,0,T,W,H-dia-T)
  image('track_divider_t_out'..sel,0,IDX,W,2)
  if bar>0 then image('track_divider_t_out'..sel,0,BAR,W,2) end
  if dia>0 then
    self:rect(0,H-dia+math.floor(dia/2),W,1,G.line or {213,208,200})
    image('mcp_diagram_dot',W/2-2.5,H-dia+math.floor(dia/2)-2,5,5)
  end
end
-- One mixer strip, drawn in its own coordinates (self.ox places it in the panel).
function M:strip(s,W,H)
  local bm=self.bitmaps
  local colors=self.theme and self.theme.colors or {}
  local function col(k,fallback) return colors[k] or fallback end
  -- Panel colours follow the theme's rules for a selected track: the track's own colour when it
  -- has one, the theme's neutral grey otherwise, each dimmed by the theme's default amounts.
  local custom=s.color and s.color~=0
  local v2=self.theme and self.theme.layout=='reapertips2'
  local v3=self.theme and self.theme.layout=='default7'
  local g80=self.theme and self.theme.layout=='gray80'
  local stock6=self.theme and self.theme.stock6
  local compact6=stock6 and self.theme.compact6
  local base=v2 and {130,130,130} or {152,152,152}
  if custom then local r,g,b=self.r.ColorFromNative(math.floor(s.color)&0xFFFFFF);base={r,g,b} end
  local tips=self.theme and self.theme.layout=='reapertips' and not stock6
  local panel,idx=mul(base,.8),mul(base,.75)
  if custom and not (tips or stock6 or v2 or v3) then panel,idx=base,base end
  if stock6 and custom then
    -- Stock 6 uses a lighter selected treatment than Reapertips' dimmed track tint.
    panel,idx={},{}
    for i=1,3 do panel[i]=base[i]*.65+255*.35;idx[i]=base[i]*.35+255*.65 end
  end
  local bright,dark=custom and {230,230,230} or {220,220,220},{23,23,23}
  local ptext=luma(panel)<=100 and bright or dark
  local itext=luma({idx[1]*.5+127.5,idx[2]*.5+127.5,idx[3]*.5+127.5})<=100 and bright or dark
  local ntext=custom and tips and name_color(base) or {235,235,235}
  -- Vertical sections, bottom-anchored like a mixer strip. The theme hides the input row on short strips.
  -- v1.95 needs a taller strip before it shows its full input panel; the racks keep at least ~200 pt.
  local L=v2 and clamp(H-200,300,430) or v3 and clamp(H-200,260,340) or g80 and clamp(H-200,260,450) or clamp(H-57,300,stock6 and 446 or 380)
  local showInFX=stock6 and L>=400
  local inh=showInFX and 54 or L>=350 and 42 or 22
  local label_h=stock6 and self.theme.label_h or 26
  local T=H-L;local IN=T+(stock6 and (L>=320 and 81 or 61) or 83);local S=IN+inh;local B=H-21-label_h;local SH=B-S
  local pad=SH<250 and 2 or SH<350 and 3 or 4
  local meter=W>=STRIP
  local extra=meter and clamp((W-STRIP)/2,0,20) or 0
  local mid=math.floor((W-2)/2)
  self.layout={T=T,S=S,B=B,L=L,meter=meter}

  -- FX and send racks
  local row=self.theme and self.theme.row_height or 17
  local selected=not s.owner
  local themed=bm and (stock6 or v3 or g80 or bm.full_artwork)
  local srow=self.theme and self.theme.send_row_height or row -- 80gray's send rows are taller than its inserts
  if themed and not s.master and self.r.IsTrackSelected then selected=self.r.IsTrackSelected(s.track) end
  -- What REAPER puts under translucent mixer art: the track's colour, else the theme's panel colour.
  local under=custom and base or colors[selected and 'col_seltrack' or 'col_seltrack2'] or {73,75,78}
  self:rect(0,0,W,T+1,bm and bm.full_artwork and under or v3 and {38,38,38} or {61,61,61})
  if themed then
    local function backing(name) return bm:draw(name,0,self.ox,0,W,T+1,self.scale,true) end
    if not (selected and backing('mcp_extmixbgsel')) then backing('mcp_extmixbg') end
  end
  local n=math.max(0,math.floor((T-6)/row))
  local sendrows=n>=4 and math.max(1,math.floor(n*.25+.5)) or n>=2 and 1 or 0
  -- The last send-rack row is pinned to the track's own output (master/parent send); the master has none.
  local outrow=not s.master and self.r.GetMasterTrack~=nil
  if outrow and n>=3 then sendrows=math.max(2,sendrows) end
  local fxrows=n-sendrows
  if srow~=row then fxrows=math.max(0,math.floor((T-6-sendrows*srow)/row)) end
  if outrow and sendrows>0 then sendrows=sendrows-1 else outrow=false end
  if s.master then sendrows=0;fxrows=n end -- the master strip shows inserts only
  -- A full rack scrolls one row past its last entry, so an empty slot to add into is always reachable.
  local function overflow(count,rows) return rows>0 and count>=rows and count-rows+1 or 0 end
  self.fx_offset=clamp(self.fx_offset,0,overflow(#s.fx,fxrows))
  self.send_offset=clamp(self.send_offset,0,overflow(#s.sends,sendrows))
  -- Scrollbar in the rack's right margin, shown only while the rack is full.
  local function scrollbar(id,count,rows,offset,y,row)
    local over=overflow(count,rows);if over==0 then self[id]=nil;return end
    local c=col('mcp_list_scrollbar',{140,140,140});local h=rows*row-2;local total=count+1
    local th=math.max(8,h*rows/total)
    self:rect(W-3.5,y+1+(h-th)*offset/over,2.5,th,{c[1],c[2],c[3],160})
    self[id]={count=count,rows=rows}
  end
  local m=self.model
  -- Each list has its own background image under its cells (PhaseLab darkens only the inserts).
  -- Stock art is only a divider where the Inspector already draws one, so it is left out there.
  local listbg=bm and (compact6 or bm.full_artwork)
  if listbg and fxrows>0 then bm:draw('mcp_fxlist_bg',0,self.ox,1,W,fxrows*row,self.scale,true) end
  for i=1,fxrows do
    local fx=s.fx[i+self.fx_offset];local y=1+(i-1)*row
    local art=fx and (fx.offline and 'mcp_fxlist_off' or fx.enabled and 'mcp_fxlist_norm' or 'mcp_fxlist_byp') or 'mcp_fxlist_empty'
    local hover=inside({x=0,y=y,w=W,h=row},self.mx,self.my)
    self:sprite(art,hover and 1 or 0,-1,y,W-2,row)
    if fx then
      local c=fx.offline and col('mcp_fx_offlined',{156,58,58}) or fx.enabled and col('mcp_fx_normal',{216,216,216}) or col('mcp_fx_bypassed',{160,126,59})
      self:text(fx.label or fx.name,7.5,y-.5,W-19.5,row,c,'list',1)
      self:hit('fx'..i,0,y,W,row,function(cap)
        -- same modifiers as the mixer: Shift bypass, Alt delete, Cmd chain, Shift+Cmd offline, Alt+Shift(+Cmd) slot on selected (all) tracks
        local shift,cmd,alt=(cap&8)~=0,(cap&4)~=0,(cap&16)~=0
        if alt and shift then m:fx_slot_bypass(s,fx,cmd)
        elseif alt then m:fx_edit(s,fx,'delete')
        elseif shift and cmd then m:fx_edit(s,fx,'offline')
        elseif shift then m:fx_edit(s,fx,'bypass')
        elseif cmd then m:fx_chain(s,fx)
        else m:open_fx(s,fx) end
      end,function() self:fx_menu(s,fx) end)
    else
      self:hit('fxadd'..i,0,y,W,row,function() self:add_fx(s) end,function() self:fx_menu(s) end)
    end
  end
  self.fx_box={x=0,y=1,w=W,h=fxrows*row,rows=fxrows}
  scrollbar('fx_bar',#s.fx,fxrows,self.fx_offset,1,row)
  local sep=1+fxrows*row+.5
  if n>0 and not s.master then self:rect(0,sep,W,1,{255,255,255,26}) end
  local sy=sep+3.5
  if listbg and sendrows>0 then bm:draw('mcp_sendlist_bg',0,self.ox,sy,W,sendrows*srow,self.scale,true) end
  for i=1,sendrows do
    local send=s.sends[i+self.send_offset];local y=sy+(i-1)*srow
    local art=not send and 'mcp_sendlist_empty' or send.kind=='midi' and 'mcp_sendlist_midihw' or send.mute and 'mcp_sendlist_mute' or 'mcp_sendlist_norm'
    local hover=inside({x=0,y=y,w=W,h=srow},self.mx,self.my)
    self:sprite(art,hover and 1 or 0,-1,y,W-3,srow)
    if send then
      local c=send.kind=='midi' and col('mcp_send_midihw',{70,185,254}) or send.mute and col('mcp_sends_muted',{228,94,101}) or col('mcp_sends_normal',{254,207,103})
      local knob=send.kind~='midi' and bm and bm:get('mcp_send_knob_stack')
      self:text(send.name,6,y-.5,W-14-(knob and 15 or 0),srow,c,'list',0)
      if knob then
        -- One square frame per level; resized smoothly because the rack row is smaller than a frame.
        local frames=math.max(1,math.floor(knob.h/knob.w))
        local f=clamp(math.floor(self.mapping.to_position(send.volume)*(frames-1)+.5),0,frames-1)
        bm:blit(knob,knob.x,knob.y+f*knob.w,knob.w,knob.w,self:pxx(W-21),self:px(y+1.5+(srow-row)/2),self:px(14),self:px(14),true)
      end
      self:hit('send'..i,0,y,W,srow,function(cap)
        local shift,cmd,alt=(cap&8)~=0,(cap&4)~=0,(cap&16)~=0
        if alt and shift then m:send_slot_mute(s,send,cmd)
        elseif alt then m:send_edit(s,send,'remove')
        elseif shift then m:send_edit(s,send,'mute')
        elseif send.kind=='send' and not s.owner and self.root:output_enabled() and self.root.width>=2*STRIP then
          self.root.choice[s.guid]=send.dest -- show this send's destination in the output strip
        else self:show_routing(s) end
      end,function() self:send_menu(s,send) end)
      if not s.owner and self.root.shown_send and self.root.shown_send.index==send.index and send.kind=='send' then
        self:rect(2.5,y+2,1.5,srow-4,c) -- marks the send whose destination the output strip shows
      end
    else
      self:hit('sendadd'..i,0,y,W,srow,function() self:show_routing(s) end,function() self:send_menu(s) end)
    end
  end
  self.send_box={x=0,y=sy,w=W,h=sendrows*srow,rows=sendrows}
  if outrow then -- set apart from the sends: its own divider, centred neutral text, never scrolls
    local y=sy+sendrows*srow+2;local on=s.B_MAINSEND~=0
    self:rect(0,y-1.5,W,1,{255,255,255,40})
    local hover=inside({x=0,y=y,w=W,h=srow},self.mx,self.my)
    self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,-1,y,W-2,srow)
    local c=on and col('mcp_fx_normal',{216,216,216}) or col('mcp_sends_muted',{228,94,101})
    self:text(s.parent and 'Parent send' or 'Master send',7.5,y-.5,W-19.5,srow,c,'list',1)
    if not s.owner and self.root.shown_main then self:rect(2.5,y+2,1.5,srow-4,c) end
    self:hit('output',0,y,W,srow,function() if not s.owner then self.root.choice[s.guid]=nil end end,function() self:output_menu(s) end)
  end
  scrollbar('send_bar',#s.sends,sendrows,self.send_offset,sy,srow)

  if v3 then return self:lower3(s,W,H,{T=T,L=L,base=base,custom=custom,colors=colors}) end
  if g80 then return self:lower80(s,W,H,{T=T,base=base,custom=custom,colors=colors,selected=selected}) end
  if v2 then return self:lower2(s,W,H,{T=T,L=L,B=B,base=base,custom=custom,colors=colors,meter=meter}) end

  -- Shared 6-style lower strip (also supplies the generic control arrangement).
  -- Stock 6's section heights/anchors differ from Custom2's; both draw through the same bitmap adapter.
  -- "Colour bar" themes (PhaseLab) paint the whole lower strip from the number tile's art, whose
  -- guides make it overhang upward. As in the mixer it goes behind every control, over the mixer
  -- background and the track's colour; the name bar and fader panel then cover their own areas.
  local cover=false
  if stock6 and bm then
    local idxArt=selected and bm:get('mcp_idxbg_sel',true) and 'mcp_idxbg_sel' or 'mcp_idxbg'
    local a=bm:get(idxArt,true)
    if a and a.over[2]/a.scale>=H-21-T then
      self:rect(0,T,W,H-T,under)
      bm:draw(selected and bm:get('mcp_bgsel',true) and 'mcp_bgsel' or 'mcp_bg',0,self.ox,T,W,H-T,self.scale,true)
      cover=bm:rise(idxArt,self.ox,T,H-21,20,W,self.scale)
    end
  end
  -- What actually ended up on screen decides whether text over it is light or dark.
  local function shade(x,y)
    local g=self.g;local dest,gx,gy=g.dest,g.x,g.y
    g.dest,g.x,g.y=-1,self:pxx(x),self:px(y)
    local r,gg,b=g.getpixel()
    g.dest,g.x,g.y=dest,gx,gy
    return luma({r*255,gg*255,b*255})<=100 and bright or dark
  end
  if cover then
    ptext,itext=shade(2,S-2),shade(2,H-10)
    local label,panel_tone=bm:tone('mcp_vol_label'),bm:tone('mcp_volbg',true)
    if panel_tone then self:rect(0,S,W,B-S,panel_tone) end
    if label then self:rect(0,S,W,23,label) end
    self:sprite('mcp_namebg',0,0,B,W,label_h)
  elseif bm and bm.full_artwork then
    -- The fader art is a strip-wide panel in these themes; its colour belongs behind the whole section.
    local panel_tone=bm:tone('mcp_volbg',true)
    if panel_tone then self:rect(0,S,W,B+label_h-S,panel_tone) end
  end
  self:rect(0,T+.5,W,.5,{255,255,255,26})
  if not cover then
    self:rect(0,T+1,W,31,{51,51,51})
    local handle=stock6 and {160,160,160} or mul(idx,.94)
    self:rect(0,T+1,W,4,handle);self:rect(0,T+1,W,1,{255,255,255,75});self:rect(0,T+4,W,1,{0,0,0,110})
  end
  local fxon=s.I_FXEN~=0
  self:button('FX',#s.fx==0 and 'mcp_fx_empty' or fxon and 'mcp_fx_norm' or 'mcp_fx_dis',6,T+8,W-(compact6 and 44 or 43),20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  self:button('I_FXEN',#s.fx==0 and 'track_fxempty_v' or fxon and 'track_fxon_v' or 'track_fxoff_v',W-37,T+8,29,20,
    function() m:toggle(s,'I_FXEN') end)

  -- Pan and input panel
  if not cover then
    self:rect(0,T+32,W,S-T-32,panel)
    if stock6 and bm and not s.master then
      local shade=bm:pan_background(selected,32,S-T,self.ox,T+32,W,self.scale)
      if shade then ptext=luma(shade)<=100 and bright or dark end
    end
    self:rect(0,T+32,W,1,{255,255,255,22});self:rect(W-1,T+33,1,S-T-33,{255,255,255,22})
  end
  local panArt=stock6 and 'mcp_pan_knob_small' or 'mcp_pan_knob_large'
  if bm and bm.full_artwork and not bm:get(panArt,true) then panArt='mcp_pan_knob_small' end
  local kw,kh
  if stock6 and bm then kw,kh=bm:size(panArt) end
  kw,kh=kw or (stock6 and 20 or 24),kh or (stock6 and 20 or 24)
  local kx,ky=mid-kw/2,T+(stock6 and (L>=320 and 40 or 37) or 39)
  if s.I_PANMODE==5 or s.I_PANMODE==6 then
    self:pan_pair(s,W,ky,(not stock6 or L>=320) and T+66 or nil,ptext)
  else
    if not self:sprite(panArt,0,kx,ky,kw,kh) and self.g.circle then
      self.g.set(.13,.13,.13,1);self.g.circle(self:pxx(kx+kw/2),self:px(ky+kh/2),self:px(kw/2-1),1,1);self.g.a=1
    end
    -- PhaseLab's marker dot and (in the artwork experiment) CSIX's whole knob face are stack frames.
    -- The experiment has no native knob size to go by, so it fits the frame to the cap it draws.
    if not ((compact6 or bm and bm.full_artwork) and self:pan_marker(kx+kw/2,ky+kh/2,s.D_PAN,not compact6 and kw or nil)) then
      self:pointer(s,kx,ky+(kh-kw)/2,kw,stock6 and {75,75,75} or nil,stock6)
    end
    if not stock6 or L>=320 then self:text(pan_label(s.D_PAN),mid-30,T+66,60,12,ptext,'main',1) end
    self:pan_hit(s,'D_PAN',kx-2,ky-2,kw+4,stock6 and math.min(IN-ky+2,40) or 40)
  end
  local ry=IN
  if inh>=42 and not s.master then
    if not self:sprite('mcp_recinput',0,5,IN,W-11,16) then self:rect(5,IN,W-11,16,{28,28,28,150}) end
    self:text(self:input_label(s.I_RECINPUT),9,IN,W-30,16,{225,225,225},'main',0)
    self:hit('I_RECINPUT',5,IN,W-11,16,function() self:input_menu(s) end)
    ry=IN+20
    if showInFX then
      local art=(s.recfx or 0)>0 and 'mcp_fx_in_norm' or 'mcp_fx_in_empty'
      local x,y,w,h=5,IN+16,W-11,12
      local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
      local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
      self:sprite(art,state,x,y,w,h)
      -- Stock 6 uses a transparent base and a separate caption overlay (falling back to its 150% art at 200%).
      self:sprite(art..'_ol',state,x,y,w,h)
      self:hit('INFX',x,y,w,h,function() m:open_input_fx(s) end)
      ry=IN+32
    end
  end
  local rm=math.floor(s.I_RECMODE)
  if not s.master then self:button('I_RECMODE',rm==2 and 'mcp_recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'mcp_recmode_in' or 'mcp_recmode_out',5,ry,compact6 and 40 or 42,16,function()
    local items={}
    for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
    self:menu(items)
  end) end

  -- Fader section: meter, volume readout, fader, button column
  local fxl=meter and 29+extra or 4          -- fader left edge
  local fw=compact6 and 20 or 21
  local ftop,fbot=S+23,B
  if SH<=70 then
    self:text('Increase height',2,S+4,W-4,16,{120,120,120},'main',1)
  else
    self:text(gaintext(s.D_VOL),meter and fxl-29 or 0,S+4,meter and 48 or fxl+25,19,{100,100,100},'main',1)
    if meter then self:meter(s,{x=3,y=ftop,w=25+extra,h=SH-24},colors) end
    local bg=bm and bm:get('mcp_volbg')
    if bg then -- groove: the art's end caps keep their size, the slot between them stretches
      local k=self.scale/bg.scale
      local sx,sw=bg.x+bg.over[1],bg.w-bg.over[1]-bg.over[3]
      local cap_t,cap_b=math.floor(10*bg.scale+.5),math.floor(9*bg.scale+.5)
      if stock6 or bm.full_artwork then -- the art's own guides: the track can live only in the stretch rows
        cap_t=clamp(bg.margin[2],1,bg.h-2);cap_b=clamp(bg.margin[4],1,bg.h-cap_t-1)
      end
      local X,Wd,Y0,Y1=self:pxx(fxl),self:pxx(fxl+fw)-self:pxx(fxl),self:px(ftop),self:px(fbot)
      local dt,dbm=math.floor(cap_t*k+.5),math.floor(cap_b*k+.5)
      bm:blit(bg,sx,bg.y,sw,cap_t,X,Y0,Wd,dt)
      bm:blit(bg,sx,bg.y+cap_t,sw,bg.h-cap_t-cap_b,X,Y0+dt,Wd,Y1-Y0-dt-dbm)
      bm:blit(bg,sx,bg.y+bg.h-cap_b,sw,cap_b,X,Y1-dbm,Wd,dbm)
    else self:rect(fxl+9,ftop,3,fbot-ftop,{16,16,16}) end
    -- Use the stock cap's measured size; preserve the existing v1.90 travel and art anchor.
    local tw,th
    if stock6 and bm then tw,th=bm:size('mcp_volthumb') end
    local half=th and math.max(0,th/2-4) or 21.5
    local top,bottom=ftop+half,fbot-half
    local fy=bottom-self.mapping.to_position(s.D_VOL)*(bottom-top)
    if not self:sprite('mcp_volthumb',0,tw and fxl+(fw-tw)/2 or fxl-1,th and fy-th/2 or fy-25.5) then
      self:rect(fxl+1,fy-15,19,30,{150,150,150});self:rect(fxl+1,fy-15,19,1,{215,215,215});self:rect(fxl+1,fy-.5,19,1,{30,30,30})
    end
    local hit=self:hit('D_VOL',fxl-2,ftop-4,fw+4,fbot-ftop+8)
    hit.kind,hit.token='D_VOL',s
    hit.top,hit.bottom,hit.fader_y=top,bottom,fy
    local bx=W-29;local y=S-17
    if not s.master then self:button('I_RECARM',s.I_RECARM~=0 and 'mcp_recarm_on' or 'mcp_recarm_off',compact6 and bx or W-36,y+(stock6 and self.theme.recarm_y or 0),compact6 and 20 or 36,compact6 and 20 or 24,function() m:toggle(s,'I_RECARM') end) end
    y=y+20+pad
    if not s.master then self:button('I_RECMON',s.I_RECMON==2 and 'mcp_monitor_auto' or s.I_RECMON==1 and 'mcp_monitor_on' or 'mcp_monitor_off',bx,y,21,20,function() m:toggle(s,'I_RECMON') end) end
    y=y+19+pad
    self:button('B_MUTE',s.B_MUTE~=0 and 'mcp_mute_on' or 'mcp_mute_off',bx,y,compact6 and 20 or 21,20,function() m:toggle(s,'B_MUTE') end)
    y=y+21+pad
    if not s.master then self:button('I_SOLO',s.I_SOLO~=0 and 'mcp_solo_on' or 'mcp_solo_off',bx,y,compact6 and 20 or 21,20,function() m:toggle(s,'I_SOLO') end) end
    -- The theme drops routing, envelope and polarity in that order as the strip gets shorter.
    if SH>=106 then
      local io='mcp_io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
      self:button('IO',io,W-30,y+23+pad,23,30,function() self:show_routing(s) end,function() self:send_menu(s) end)
    end
    if SH>=141 then
      local mode=math.floor(s.I_AUTOMODE)
      self:button('I_AUTOMODE',ENV[mode] or 'mcp_env',bx,B-30,21,30,function()
        local items={}
        for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
        self:menu(items)
      end)
    end
    if SH>=162 and not s.master then
      self:button('B_PHASE',s.B_PHASE~=0 and 'mcp_phase_inv' or 'mcp_phase_norm',W-26,B-48-pad,16,18,function() m:toggle(s,'B_PHASE') end)
    end
  end

  -- Name and track number
  self:text(s.name,2.5,B+.5,W-7,label_h,ntext,'header',1)
  if not s.master then self:hit('name',0,B,W,label_h).double=function() self:rename(s) end end
  if not cover then
    self:rect(0,B+label_h,W,21,idx)
    -- A full-strip layer in the footer image belongs behind the controls (the colour bar above);
    -- it must never be composited here, after they have been drawn.
    local footer=bm and (compact6 or bm.full_artwork) and bm:get('mcp_idxbg_sel',true)
    if not footer or footer.over[2]/footer.scale<=label_h then
      self:sprite('mcp_idxbg_sel',0,0,B+label_h,W,21)
    end
    self:rect(0,B+label_h,W,1,{255,255,255,22})
  end
  self:text(s.master and '' or ('%d'):format(s.IP_TRACKNUMBER),0,B+label_h,W-2,20,itext,'main',1)
end
-- Stereo peak meter on the theme's scale (+6 to -62 dB), with its dB marks and peak readout.
function M:meter(s,m,colors)
  local now=self.r.time_precise();local dt=clamp(now-self.last_time,0,.2);self.last_time=now
  local function ydb(d) return m.y+(6-clamp(d,-62,6))/68*m.h end
  local bot=colors.col_vubot or {42,102,190};local midc=colors.col_vumid or {70,185,254}
  local top=colors.col_vutop or midc;local clip=colors.col_vuclip or {255,33,69}
  local bw=(m.w-.5)/2;local lit=m.y+m.h
  if self.peak==0 or not self.chpeak then self.chpeak={0,0} end
  for c=1,2 do
    self.chpeak[c]=math.max(self.chpeak[c],math.max(0,s.peaks[c] or 0))
    local x=m.x+(c-1)*(bw+.5);local peak=math.max(0,s.peaks[c] or 0);local d=db(peak)
    self.peak=math.max(self.peak,peak)
    self.held[c]=math.max(d,self.held[c]-dt*30)
    if d>-62 then
      local y0=ydb(d);lit=math.min(lit,y0)
      local bands=math.max(8,math.floor(m.h/2));local y1=m.y+m.h
      for b=0,bands-1 do -- bottom-to-top colour ramp in bands
        local ya,yb=y1-(b+1)*m.h/bands,y1-b*m.h/bands
        if yb>y0 then
          local t=(b+.5)/bands;local a,z,u=bot,midc,t*2
          if t>.5 then a,z,u=midc,top,(t-.5)*2 end
          local cc=ya<ydb(0) and clip or {a[1]+(z[1]-a[1])*u,a[2]+(z[2]-a[2])*u,a[3]+(z[3]-a[3])*u}
          self:rect(x,math.max(ya,y0),bw,yb-math.max(ya,y0),cc)
        end
      end
    end
    if self.held[c]>-62 then self:rect(x,ydb(self.held[c]),bw,.5,{200,225,255}) end
  end
  local armed=s.I_RECARM~=0
  for d=6,(m.labels==false) and 0 or 54,12 do -- the theme prints bare numbers between two small ticks
    local y=ydb(-d);local label=tostring(d)
    local c=y>lit and {0,0,0,170} or armed and {255,64,0} or {255,255,255,60}
    self.g.setfont(4);local tw=self.g.measurestr(label)/self.scale
    local cx=m.x+m.w/2
    self:text(label,m.x,y-7,m.w,14,c,'bold',1)
    if m.w>=tw+9 then
      local tick={c[1],c[2],c[3],(c[4] or 255)*.5}
      self:rect(cx-tw/2-4,y-.5,2.5,1,tick);self:rect(cx+tw/2+1.5,y-.5,2.5,1,tick)
    end
  end
  local over=self.peak>1
  local text=self.peak<=0 and '-inf' or ('%.1f'):format(db(self.peak))
  local rc=m.readout_color or {100,100,100}
  local function peaktext(v) return v<=0 and '-inf' or ('%.1f'):format(db(v)) end
  local ry=m.y+(m.readout_y or 1.5)
  self.g.setfont(4)
  local function fits(t,w) return self.g.measurestr(t)/self.scale<=w end
  local l,r_=peaktext(self.chpeak[1]),peaktext(self.chpeak[2])
  if m.readout==false then
  elseif s.master and fits(l,m.w/2-2) and fits(r_,m.w/2-2) then
    -- The master meter reads each channel's peak separately, and its loudness at the bottom.
    self:text(l,m.x,ry,m.w/2,13,self.chpeak[1]>1 and {255,183,171} or rc,'bold',1)
    self:text(r_,m.x+m.w/2,ry,m.w/2,13,self.chpeak[2]>1 and {255,183,171} or rc,'bold',1)
  else self:text(text,m.x,ry,m.w,13,over and {255,183,171} or rc,'bold',1) end
  if s.master and m.readout~=false and s.loudness and m.h>=80 then
    local mode=math.floor(s.vumode or 0)&30
    local label=(mode==12 and 'LUFS-M' or mode>=16 and 'LUFS-S' or 'RMS')..'  '..peaktext(s.loudness)
    if fits(label,m.w-2) then self:text(label,m.x,m.y+m.h-14,m.w,13,m.loudness_color or rc,'bold',1) end
  end
  self:hit('meter',m.x,m.y,m.w,m.h,function() self.peak=0 end)
end
function M:input(s)
  local g=self.g
  local cap=g.mouse_cap or 0;local pressed=(cap&1)~=0 and (self.prev_cap&1)==0
  if self.drag and not self.model:valid(self.drag.token) then self.drag=nil end
  local function target()
    for i=#self.order,1,-1 do if inside(self.order[i],self.mx,self.my) then return self.order[i] end end
  end
  if (cap&2)~=0 and (self.prev_cap&2)==0 then
    self.drag=nil
    local hit=target()
    g.x,g.y=g.mouse_x or 0,g.mouse_y or 0 -- menus open at the pointer
    if hit and hit.menu then hit.menu() elseif self.options.menu then self.options.menu() end
  elseif pressed then
    local hit=target()
    if hit then
      local id=hit.id;local now=self.r.time_precise()
      local double=self.last_click and self.last_click.id==id and now-self.last_click.time<.35
      self.last_click={id=id,time=now}
      local kind,tok=hit.kind,hit.token -- faders and pan knobs carry the track they belong to
      if kind and tok then
        if double then
          local reset=({D_VOL=1,D_WIDTH=1,D_DUALPANL=-1,D_DUALPANR=1})[kind] or 0
          self.model:set(tok,kind,reset)
        else
          self.drag={kind=kind,token=tok,hit=hit,x=self.mx,y=self.my,initial=tok[kind],
            offset=kind=='D_VOL' and math.abs(self.my-hit.fader_y)<22 and self.my-hit.fader_y or 0}
        end
      elseif double and hit.double then self.last_click=nil;hit.double()
      elseif hit.action then hit.action(cap) end
    end
  end
  if (cap&1)~=0 and self.drag then
    local d=self.drag;local fine=(cap&8)~=0 and .1 or 1;local value
    if d.hit.pan_span then value=d.initial+(self.mx-d.x)*2/d.hit.pan_span*fine
    elseif d.kind~='D_VOL' then value=d.initial+((self.mx-d.x)-(self.my-d.y))/50*fine
    elseif fine<1 then value=self.mapping.to_gain(self.mapping.to_position(d.initial)+(d.y-self.my)/(d.hit.bottom-d.hit.top)*fine)
    else value=self.mapping.to_gain((d.hit.bottom-self.my+d.offset)/(d.hit.bottom-d.hit.top)) end
    if not self.model:set(d.token,d.kind,value) then self.drag=nil end
  end
  if (cap&1)==0 then self.drag=nil end
  local wheel=g.mouse_wheel or 0
  if wheel~=0 then
    for _,v in ipairs({self,self.out_snapshot and self.out or nil}) do -- each strip scrolls its own racks
      if inside(v.fx_box,v.mx,v.my) then v.fx_offset=v.fx_offset-(wheel>0 and 1 or -1)
      elseif inside(v.send_box,v.mx,v.my) then v.send_offset=v.send_offset-(wheel>0 and 1 or -1) end
    end
    g.mouse_wheel=0
  end
  self.prev_cap=cap
end
function M:frame()
  local g=self.g;local density=math.max(1,g.ext_retina or 1)
  local os=self.r.GetOS()
  local mac=os:match('^OSX') or os:match('^macOS')
  local scale=mac and density or 1
  local font=self.theme and self.theme.font or FONT
  if scale~=self.scale or font~=self.font then
    self.scale,self.font=scale,font
    for i,role in ipairs({'main','list','header','bold'}) do g.setfont(i,font,math.floor(FONTS[role]*scale+.5),role=='bold' and 98 or 0) end
  end
  self.width=g.w/self.scale;self.height=g.h/self.scale
  self.mx=(g.mouse_x or 0)/self.scale;self.my=(g.mouse_y or 0)/self.scale
  local full=self.theme and self.theme.layout=='generic' and (self.options.full_theme_artwork==true or self.theme.full_art==true)
  if self.theme and (not self.bitmaps or self.bitmaps.density~=density or self.bitmaps.theme~=self.theme or self.bitmaps.full_artwork~=full) then
    if self.bitmaps then self.bitmaps:clear() end
    self.bitmaps=Bitmaps.new(g,self.theme,density,full)
  end
  local s=self.model:snapshot()
  if (s and s.guid)~=self.last_guid or (s and s.project)~=self.last_project then
    self.held={-150,-150};self.peak=0;self.fx_offset=0;self.send_offset=0
    self.last_guid=s and s.guid;self.last_project=s and s.project
  end
  self.snapshot=s;g.dest=-1;self:draw(s);self:input(s);g.update();return s
end
return M
