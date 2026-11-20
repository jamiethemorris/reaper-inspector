local here=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './'
local Bitmaps=dofile(here..'bitmaps.lua')
local Model=dofile(here..'model.lua')
local M={};M.__index=M
-- Geometry below is the Reapertips wide mixer strip, in logical points, measured against the
-- native mixer at 200%. It is this theme's layout written out, not a WALTER interpreter.
local STRIP=86                              -- native strip width; wider panels widen the meter first
local FONT='Fira Sans'
local FONTS={main=11.5,list=12,header=14.5,bold=12,sends=12}   -- gfx sizes that land on the theme's rendered text sizes
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
  g.setfont(font=='list' and 2 or font=='header' and 3 or font=='bold' and 4 or font=='sends' and 5 or 1)
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
  -- REAPER sometimes answers with no name for a moment; keep the last name it gave for that channel.
  local known=self.root.input_names or {};self.root.input_names=known
  local function ch(n)
    local name=r.GetInputChannelName and r.GetInputChannelName(n)
    if name and name~='' then known[n]=name end
    return known[n] or ('Input '..(n+1))
  end
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
-- theFRXST strip: name bar on top, racks inside the strip, and the theme's rounded control panel
-- anchored to the bottom (rtconfig rectangles, tall form). The theme's strip is a fixed 124 pt; here the
-- meter and the right-hand controls give up or take the difference. `c` carries what the racks computed.
function M:lowerfx(s,W,H,c)
  local m,bm=self.model,self.bitmaps
  local d=W-124
  local function Y(v) return H-343+v end                  -- the script's bottom-anchored rows (1 pt lower in the mixer)
  self.layout={T=c.T,S=Y(145),B=Y(336),L=H-c.T,meter=38+d>=10}
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    if not bm then return false end
    for _,prefix in ipairs({'mcp_','track_','tcp_'}) do
      if bm:draw(prefix..name,state,x+self.ox,y,w,h,self.scale,true) then return true end
    end
    return false
  end
  local function button(id,name,x,y,w,h,action,menu)
    local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
    local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local p=PLAIN['mcp_'..name] or {''}
      self:rect(x+1,y+1,w-2,h-2,{62,62,62});self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end
  local grey={160,160,160}
  local sel=c.selected

  -- Name bar
  -- (the mixer shows this bar 3 pt higher than the script's numbers)
  if c.custom then self:rect(4,3,12,12,c.base) end
  image('custom_mcp_label',3,2,15,15)
  self:text(s.name,21,-1,100+d,20,(sel or c.custom) and {255,255,255} or {214,214,214},'header',0)
  self:rect(28,9,90+d,3,{255,255,255,38})
  if not s.master then self:hit('name',17,0,107+d,19).double=function() self:rename(s) end end

  -- Panel: colour line, body, bottom shadow, corners
  local line=c.custom and c.base or {0,0,0}              -- the track's colour; nothing for an uncoloured track
  self:rect(4,Y(334),116+d,9,sel and {38,38,38} or {27,27,27})
  self:rect(4,Y(54),116+d,287,sel and {64,64,64} or {38,38,38})
  self:rect(4,Y(51),116+d,4,line)
  local v2=sel and '2' or ''
  image('custom_mcp_paneltopleft'..v2,3,Y(50),7,7);image('custom_mcp_paneltopright'..v2,114+d,Y(50),7,7)
  image('custom_mcp_panelbotleft'..v2,3,Y(338),7,6);image('custom_mcp_panelbotright'..v2,114+d,Y(338),7,6)

  -- Top rows
  local fxon=s.I_FXEN~=0;local mx=s.master and -1 or 0     -- the master's left column sits 1 pt further left
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',7+mx,Y(59),25,25,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',30+mx,Y(61),20,21,function() m:toggle(s,'I_FXEN') end)
  local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  button('IO',io,94+d-mx,Y(59),22,25,function() self:show_routing(s) end,function() self:send_menu(s) end)
  local function readout(text,x,y,w,h,bg)
    if bg then image(bg,x,y,w,h) end
    self:text(text,x,y,w,h,grey,'main',1)
  end
  local voltext=gaintext(s.D_VOL)
  if s.master then
    readout(voltext,6,Y(87),45,21,'mcp_vol_label')
    button('MONO',s.mono and 'mono' or 'stereo',12,Y(138),35,25,function() m:master_mono(s) end)
  else
    art('recinput',0,7,Y(84),80+d,25)
    self:text(self:input_label(s.I_RECINPUT),14,Y(86),80+d-24,23,{157,157,157},'main',0)
    self:hit('I_RECINPUT',7,Y(84),80+d,25,function() self:input_menu(s) end)
    button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',87+d,Y(84),30,25,function() m:open_input_fx(s) end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',9,Y(109),106+d,25,function() m:toggle(s,'I_RECMON') end)
    readout(voltext,7,Y(144),44,21,'mcp_vol_label')
  end

  -- Pan and width: a text readout over a bar-shaped frame stack
  local kx=13+mx;local ky=s.master and -1 or 0              -- the master's bars sit 1 pt higher too
  local function bar(key,stack,y,labely,label,live,fixed)
    y,labely=y+ky,labely+ky
    local value=fixed or clamp(s[key] or 0,-1,1)
    if not (bm and (bm:stack('mcp_'..stack,(value+1)/2,kx+self.ox,y,36,21,self.scale) or bm:stack('tcp_'..stack,(value+1)/2,kx+self.ox,y,36,21,self.scale))) then
      self:rect(kx,y+15,36,3,{0,0,0});self:rect(kx+17+value*16,y+13,2,7,{110,170,170})
    end
    self:text(label,kx-1,labely+5,38,14,grey,'main',1)
    if live then self:pan_hit(s,key,kx,y,36,21,36) end
  end
  local function wtext(v) return ('%dW'):format(math.floor(v*100+.5)) end
  if s.I_PANMODE==6 then
    bar('D_DUALPANL','pan_knob_stack',Y(169),Y(167),pan_label(s.D_DUALPANL),true)
    bar('D_DUALPANR','wid_knob_stack',Y(194),Y(193),pan_label(s.D_DUALPANR),true)
  else
    bar('D_PAN','pan_knob_stack',Y(169),Y(167),pan_label(s.D_PAN),true)
    -- The width bar is always shown; it only does something in stereo pan mode.
    if s.I_PANMODE==5 then bar('D_WIDTH','wid_knob_stack',Y(194),Y(193),wtext(s.D_WIDTH),true)
    else bar('D_WIDTH','wid_knob_stack',Y(194),Y(193),'100W',false,1) end
  end

  -- Left column
  local mode=math.floor(s.I_AUTOMODE)
  button('I_AUTOMODE',(ENV[mode] or 'mcp_env'):gsub('^mcp_',''),s.master and 18 or 7,Y(226),25,25,function()
    local items={}
    for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
    self:menu(items)
  end)
  if not s.master then button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',32,Y(226),22,25,function() m:toggle(s,'B_PHASE') end) end
  -- The unmuted button is blank art: a track prints its number on it, the master an M.
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',kx,Y(262),36,25,function() m:toggle(s,'B_MUTE') end)
  if s.B_MUTE~=0 then -- the lit art carries its own M
  elseif not s.master then self:text(('%d'):format(s.IP_TRACKNUMBER),kx,Y(264),36,20,grey,'header',1)
  else self:text('M',kx,Y(264),36,20,grey,'header',1) end
  if s.master then image('mixer_menu',kx,Y(312),36,25) end -- the mixer's Menu button; not a control here
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',kx,Y(287),36,25,function() m:toggle(s,'I_SOLO') end)
  if not s.master then
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',13,Y(312),36,25,function() m:toggle(s,'I_RECARM') end)
  end

  -- Fader and meter
  local fx,fy0,fh=52,Y(145),191
  local mxx,mw=76,38+d
  if s.master then fx,fy0,fh,mxx,mw=49,Y(88),249,71,45+d end
  image('mcp_volbg',fx,fy0,22,fh)
  local thumb=bm and bm:get('mcp_volthumb',true)
  local th=thumb and thumb.h/thumb.scale or 26
  local ftop,fbottom=fy0+th/2,fy0+fh-th/2
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  if thumb then
    local tw=thumb.w/thumb.scale
    bm:blit(thumb,thumb.x,thumb.y,thumb.w,thumb.h,self:pxx(fx+11-tw/2),self:px(fy-th/2),self:px(tw),self:px(th),true)
  else self:rect(fx+2,fy-12,18,24,{110,110,112}) end
  local hit=self:hit('D_VOL',fx,fy0,22,fh)
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy
  if mw>=10 then
    self:rect(mxx,fy0,mw,fh,{0,0,0})
    local roomy=mw>=24                                    -- a squeezed meter keeps its bars and drops its text
    local muted=s.B_MUTE~=0 and roomy                     -- a muted track's readout is replaced by the theme's M tile
    self:meter(s,{x=mxx+1,y=fy0+1,w=mw-2,h=fh-2,labels=roomy,readout=roomy and not muted,readout_color={255,255,255},scale_color={150,150,150}},c.colors)
    if muted then image('meter_mute',mxx+(mw-16)/2,fy0,16,16) end
  end
end
-- Mydaw strip (Ableton-style): FX row, input rows and routing hang from the top of the panel; the pan
-- knob, button column and name hang from the bottom; the fader's triangle rides the right edge of a
-- thin meter. Rectangles are the theme script's, which sizes everything from the strip's width.
function M:lowermd(s,W,H,c)
  local m,bm,T=self.model,self.bitmaps,c.T
  local up=s.master and 8 or 0                            -- the master's bottom rows sit one folder step higher
  local function B(v) return H-380-up+v end               -- the script's bottom-anchored rows
  local dark={30,30,30}
  local d=s.master and W-120 or 0                         -- the master is written for a fixed 120 pt
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    return bm and (bm:draw('mcp_'..name,state,x+self.ox,y,w,h,self.scale,true)
      or bm:draw('track_'..name,state,x+self.ox,y,w,h,self.scale,true))
  end
  local function button(id,name,x,y,w,h,action,menu)
    local hover=inside({x=x,y=y,w=w,h=h},self.mx,self.my)
    local state=hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local p=PLAIN['mcp_'..name] or {''}
      self:rect(x,y,w,h,{78,78,78});self:rect(x+1,y+1,w-2,h-2,{200,200,200});self:text(p[1],x,y,w,h,dark,'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end
  if not image(c.selected and 'mcp_bgsel' or 'mcp_bg',0,T,W,H-T) then self:rect(0,T,W,H-T,c.selected and {168,168,168} or {141,141,141}) end

  -- FX row: button, bypass, and the blank holder that joins them
  local fxon=s.I_FXEN~=0
  image('track_fxholder',26,T+4,W-52,15)
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',4,T+4,24,15,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',W-29,T+4,24,15,function() m:toggle(s,'I_FXEN') end)

  -- Input, input FX / monitor / record mode, routing
  local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  -- The input and routing fields are drawn for a 72 pt control, lettering included. At other widths only
  -- the blank stretch between the lettering and the arrow gives; a field too narrow for that squeezes its left part.
  local function field(name,x,y,w)
    local hover=inside({x=x,y=y,w=w,h=15},self.mx,self.my)
    local a,sx,sy,sw,sh
    if bm then a,sx,sy,sw,sh=bm:frame(name,hover and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0,true) end
    if not a then return false end
    if a.margin[1]>0 or a.margin[3]>0 then return bm:draw(name,0,x+self.ox,y,w,15,self.scale,true) end -- guided art stretches itself
    local k=sw/72;local c1,c2=math.floor(41*k+.5),math.floor(60*k+.5)
    local left=math.min(41,w-12)
    local X0,X1,X2,X3=self:pxx(x),self:pxx(x+left),self:pxx(x+w-12),self:pxx(x+w)
    local Y,Hd=self:px(y),self:px(y+15)-self:px(y)
    bm:blit(a,sx,sy,c1,sh,X0,Y,X1-X0,Hd,true)
    bm:blit(a,sx+c1,sy,c2-c1,sh,X1,Y,X2-X1,Hd,true)
    bm:blit(a,sx+c2,sy,sw-c2,sh,X2,Y,X3-X2,Hd,true)
    return true
  end
  local function routing(x,y,w)
    if not field('mcp_'..io,x,y,w) then self:rect(x,y,w,15,{78,78,78});self:rect(x+1,y+1,w-2,13,{213,213,213});self:text('I/O',x,y,w,15,dark,'main',1) end
    self:hit('IO',x,y,w,15,function() self:show_routing(s) end,function() self:send_menu(s) end)
  end
  if s.master then
    image('mixer_menu',4,T+31,16,15);image('render',W-20,T+31,16,15) -- the mixer's Menu and Render buttons; not controls here
    local iw=math.min(72,W-44);routing((W-iw)/2,T+31,iw)
  else
    if not field('mcp_recinput',4,T+31,W-8) then art('recinput',0,4,T+31,W-8,15) end
    self:text(self:input_label(s.I_RECINPUT),7,T+31,W-24,15,dark,'header',0)
    self:hit('I_RECINPUT',4,T+31,W-8,15,function() self:input_menu(s) end)
    button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',4,T+50,15,15,function() m:open_input_fx(s) end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',W/2-10,T+50,21,15,function() m:toggle(s,'I_RECMON') end)
    local rm=math.floor(s.I_RECMODE)
    button('I_RECMODE',rm==2 and 'recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'recmode_in' or 'recmode_out',W-19,T+50,15,15,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    routing(4,T+69,W-8)
  end

  -- Meter, with the fader's slot over its right-hand side
  local roomy=W>74
  local mw=s.master and 53+d or roomy and 15 or 11
  local mx=s.master and 50 or W*.66-6
  local vx=s.master and 99+d or mx+(roomy and 11 or 7)
  local my,mh=T+110,B(356)-(T+110)
  self.layout={T=T,S=my,B=my+mh,L=H-T,meter=mw>=6}
  if mw>=6 then
    self:rect(mx,my,mw,mh,{36,36,36})
    -- The theme numbers every 6 dB, even on its 15 pt meter.
    self:meter(s,{x=mx,y=my,w=mw,h=mh,first=0,last=60,step=6,readout_y=4,gap={89,89,89},loudness_bg={142,142,142},
      readout_color={255,255,255},scale_color={255,255,255,155}},c.colors)
  end
  local thumb=bm and bm:get('mcp_volthumb',true)
  local tw,th=13,18
  if thumb then tw,th=thumb.w/thumb.scale,thumb.h/thumb.scale end
  local ftop,fbottom=T+103+th/2,T+103+mh-th/2
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  if thumb then bm:blit(thumb,thumb.x,thumb.y,thumb.w,thumb.h,self:pxx(vx+11-tw/2),self:px(fy-th/2),self:px(tw),self:px(th),true)
  else self:rect(vx+5,fy-1,12,2,dark) end
  local hit=self:hit('D_VOL',vx,T+103,22,mh)
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy

  -- Left column: volume readout on top; pan, mute (with the track's number), polarity, solo, arm from the bottom
  local x0=s.master and 13 or math.floor(W*.33*self.scale)/self.scale-12 -- REAPER drops the fraction of a pixel
  local lx=s.master and 10.5 or W*.33-14.5
  image('mcp_vol_label',lx,T+110,30,16)
  self:text(gaintext(s.D_VOL),lx,T+110,30,16,dark,'main',1)
  local function bar(key,stack,y)
    local a=bm and bm:get(stack,true)                     -- frames are 15 image pixels tall at any display scale
    if not (a and bm:stack(stack,(clamp(s[key] or 0,-1,1)+1)/2,x0+self.ox,y,25,17,self.scale,15/a.scale)) then
      self:rect(x0,y,25,17,{78,78,78});self:rect(x0+1,y+1,23,15,{200,200,200})
      self:rect(x0+12+clamp(s[key] or 0,-1,1)*10,y+2,1.5,13,dark)
    end
    self:pan_hit(s,key,x0,y,25,17,25)
  end
  if s.I_PANMODE>=5 then
    local dual=s.I_PANMODE==6
    bar(dual and 'D_DUALPANL' or 'D_PAN','mcp_pan_knob_stack_2',B(235))
    bar(dual and 'D_DUALPANR' or 'D_WIDTH','mcp_wid_knob_stack_2',B(254))
  elseif roomy or s.master then
    local kx,ky=x0-7,B(227)
    if not (bm and bm:knob_frame('mcp_pan_knob_stack_1',(clamp(s.D_PAN,-1,1)+1)/2,kx+19+self.ox,ky+19,self.scale,38)) then
      self:pointer(s,kx+7,ky+7,24,dark,true)
    end
    self:pan_hit(s,'D_PAN',kx,ky,38,38)
  else bar('D_PAN','mcp_pan_knob_stack_2',B(235)) end
  -- The lit (amber) art is the unmuted state, as the theme names it.
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',x0,B(274),25,25,function() m:toggle(s,'B_MUTE') end)
  if not s.master then
    self:text(('%d'):format(s.IP_TRACKNUMBER),x0,B(274),25,25,dark,'main',1)
    button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',x0,B(303),25,15,function() m:toggle(s,'B_PHASE') end)
  end
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',x0,B(322),25,15,function() m:toggle(s,'I_SOLO') end)
  if s.master then button('MONO',s.mono and 'mono' or 'stereo',x0,B(341),25,15,function() m:master_mono(s) end)
  else button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',x0,B(341),25,15,function() m:toggle(s,'I_RECARM') end) end

  -- Name: on a band of the track's colour blended into the panel, or the master's own band
  if s.master then image('mcp_main_namebg',0,B(359),W,21)
  elseif c.custom then
    local g=c.selected and 168 or 141
    self:rect(0,B(359),W-1,21,{c.base[1]*.59+g*.41,c.base[2]*.59+g*.41,c.base[3]*.59+g*.41})
  end
  self:text(s.name,5,B(359),W-9,21,{1,1,1},'main',s.master and 1 or 0)
  if not s.master then self:hit('name',0,B(359),W,21).double=function() self:rename(s) end end
end
-- CSIX AE-Narrow / SX strip: the shared mixer macro's wide form with its default Theme Adjuster values (labels,
-- input, record and envelope sections on). The panel hangs from the bottom of the strip: FX, pan and input
-- sections from its top, name and number from its bottom. `d` is the script's nchan_offs: a stereo strip is 76 pt
-- and the meter takes every point beyond that, the fader and buttons keeping their distance to it. Rectangles are
-- the script's [x y w h], y from the panel top.
function M:lowercsix(s,W,H,c)
  local m,bm,T,L=self.model,self.bitmaps,c.T,c.L
  local cs=self.theme.csix or {}
  local sel,mt=c.selected,s.master
  local d=math.max(W-76,-12)
  local function Y(v) return T+v end
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  -- The script's text_over_mcp for pan and width labels: dark on a light track colour when selected
  local ink={230,230,230}
  if sel then ink=c.custom and .299*c.base[1]+.587*c.base[2]+.114*c.base[3]>140 and {0,0,0} or {255,255,255} end
  local function label(text,x,y,w,h) self:text(text,x,y,w,h,ink,'main',1) end

  -- Layers as REAPER stacks them: the wash colour, the mixer's own background below the input section, the
  -- panel art (opaque but for its top margin and stretch row), then a part-transparent wash over the top section.
  local tint=c.tint
  self:rect(0,T,W,L,tint)
  image(sel and 'mcp_bgsel' or 'mcp_bg',0,T,W,L)
  self:rect(0,T,W,134.5,{tint[1],tint[2],tint[3],sel and 128 or 102})
  -- The body goes over the panel art: that art's stretch row would otherwise show as a box between the top
  -- section and where the name bar's art starts, on any strip taller or shorter than the theme's own.
  self:rect(0,Y(134.5),W,L-181.5,bm and bm:tone('mcp_namebg') or c.colors.col_mixerbg or {25,27,31})
  -- Name and number bars are part of the background: their art reaches up behind the meter and fader
  image('mcp_namebg',0,Y(L-46),W,28.5)
  image(sel and 'mcp_idxbg_sel' or 'mcp_idxbg',0,Y(L-17.5),W,17.5)

  -- FX row
  local fxon,fw=s.I_FXEN~=0,37+d*2/3
  self:button('FX',#s.fx==0 and 'mcp_fx_empty' or fxon and 'mcp_fx_norm' or 'mcp_fx_dis',5,Y(8),fw,20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  self:button('I_FXEN',#s.fx==0 and 'track_fxempty_v' or fxon and 'track_fxon_v' or 'track_fxoff_v',5+fw,Y(8),29+d/3,20,
    function() m:toggle(s,'I_FXEN') end)

  -- Pan: balance is one knob, stereo pan adds width, dual pan is two bars (left value above, right below)
  local pm=s.I_PANMODE
  local function knob(key,cap,stack,x,value)
    -- REAPER lays the cap down first (its colour ring shows through the stack frame's cut-outs), then the frame
    local capped=image('mcp_'..cap..'_knob_large',x,Y(35),26,26) or image('mcp_'..cap..'_knob_small',x,Y(35),26,26)
    if not (bm and bm:knob_frame('mcp_'..stack,(clamp(value,-1,1)+1)/2,x+13+self.ox,Y(48),self.scale,26)) then
      if not capped then self:pan_cap('mcp_pan_knob_large',x+13,Y(48)) end
      self:pointer(s,x,Y(35),26,{60,60,60},true,value)
    end
    self:pan_hit(s,key,x,Y(35),26,26)
  end
  if pm==6 then
    for i,key in ipairs({'D_DUALPANL','D_DUALPANR'}) do
      local x,y,w=7+d/2,Y(35+10*i),63
      local bg,thumb=i==1 and 'mcp_panbg' or 'mcp_widthbg',i==1 and 'mcp_panthumb' or 'mcp_widththumb'
      if not image(bg,x,y,w,9) then self:rect(x,y+3,w,4,{42,42,42}) end
      local tw,th=11,9
      if bm then tw,th=bm:size(thumb,true) end
      local cx=x+tw/2+(clamp(s[key],-1,1)+1)/2*(w-tw)
      if not (bm and bm:draw(thumb,0,cx-tw/2+self.ox,y+4.5-th/2,nil,nil,self.scale,true)) then self:rect(cx-3,y,6,9,{170,170,170}) end
      self:pan_hit(s,key,x,y-1,w,10,w-tw)
    end
    label(pan_label(s.D_DUALPANL),19+d/2,Y(34),40,9);label(pan_label(s.D_DUALPANR),7,Y(66),63+d,9)
  elseif pm==5 then
    knob('D_PAN','pan','pan_knob_stack',10+d/2,s.D_PAN);knob('D_WIDTH','width','wid_knob_stack',43+d/2,s.D_WIDTH)
    label(pan_label(s.D_PAN),5+d/2,Y(63),35,10);label(('%dW'):format(math.floor(s.D_WIDTH*100+.5)),43+d/2,Y(64),30,9)
  else
    knob('D_PAN','pan','pan_knob_stack',26+d/2,s.D_PAN);label(pan_label(s.D_PAN),21+d/2,Y(63),35,10)
  end

  -- Input rows; the master has none, and its mono/stereo switch takes their place
  if mt then
    self:button('MONO',s.mono and 'mcp_mono' or 'mcp_stereo',6,Y(82),25,22,function() m:master_mono(s) end)
  else
    image('mcp_recinput',6,Y(77),65+d,16)
    self:text(self:input_label(s.I_RECINPUT),10,Y(77),46+d,16,sel and {225,225,225} or {200,200,200},'main',0)
    self:hit('I_RECINPUT',6,Y(77),65+d,16,function() self:input_menu(s) end)
    local name=(s.recfx or 0)>0 and 'mcp_fx_in_norm' or 'mcp_fx_in_empty'
    self:button('INFX',name,6,Y(93),30,12,function() m:open_input_fx(s) end)
    self:sprite(name..'_ol',inside({x=6,y=Y(93),w=30,h=12},self.mx,self.my) and 1 or 0,6,Y(93),30,12) -- its lettering
    local rm=math.floor(s.I_RECMODE)
    self:button('I_RECMODE',rm==2 and 'mcp_recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'mcp_recmode_in' or 'mcp_recmode_out',6,Y(105),41,16,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    self.hits[self.prefix..'I_RECMODE'].w=29                -- the polarity button covers its right end
    self:button('B_PHASE',s.B_PHASE~=0 and 'mcp_phase_inv' or 'mcp_phase_norm',35,Y(105),16,17,function() m:toggle(s,'B_PHASE') end)
  end

  -- Meter: its scale runs +6 to -62 dB over the whole rectangle, the lanes start at 0 dB with the peak readout above
  local mw,mh=21+d,L-208
  self.layout={T=T,S=Y(134),B=Y(L-47),L=L,meter=mw>=6}
  image('mcp_vol_label',1,Y(134),47+d,20)
  self:text(gaintext(s.D_VOL),1,Y(134),33+d,20,sel and cs.vol_sel or cs.vol or {210,210,210},'bold',2)
  if mw>=6 then
    local y0=Y(157)
    self:rect(6,y0+mh*6/68,mw,mh*62/68,{255,255,255,5})
    local roomy=mw>=20                                    -- a squeezed meter keeps its bars and drops its text
    self:meter(s,{x=6,y=y0,w=mw,h=mh,labels=roomy,readout=roomy,readout_y=-2,readout_color=cs.readout,scale_color=cs.scale},c.colors)
  end

  -- Fader: the groove, and a cap that travels between its ends
  local fx,fy0,fh=30+d,Y(155),L-206
  image('mcp_volbg',fx,fy0,22,fh)
  local thumb=bm and bm:get('mcp_volthumb',true)
  local tw,th=22,51
  if thumb then tw,th=thumb.w/thumb.scale,thumb.h/thumb.scale end
  local ftop,fbottom=fy0+th/2-2.5,fy0+fh-th/2 -- the cap's centre reaches 2.5 pt above the groove's top
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  if thumb then bm:blit(thumb,thumb.x,thumb.y,thumb.w,thumb.h,self:pxx(fx+11-tw/2),self:px(fy-th/2),self:px(tw),self:px(th),true)
  else self:rect(fx+2,fy-12,18,24,{110,110,112}) end
  local hit=self:hit('D_VOL',fx,fy0,21,fh)               -- a point short, to stay clear of the routing button
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy

  -- Button column right of the fader. The arm tab is 36 pt wide: REAPER clips what a 76 pt strip cannot hold.
  if not mt then
    local ax=44+d;local vis=math.min(36,W-ax)
    local name=s.I_RECARM~=0 and 'mcp_recarm_on' or 'mcp_recarm_off'
    local state=inside({x=ax,y=Y(117),w=vis,h=24},self.mx,self.my) and 1 or 0
    local a,sx,sy,sw,sh;if bm then a,sx,sy,sw,sh=bm:frame(name,state,true) end
    if a then bm:blit(a,sx,sy,math.floor(sw*vis/36+.5),sh,self:pxx(ax),self:px(Y(117)),self:pxx(ax+vis)-self:pxx(ax),self:px(Y(141))-self:px(Y(117)),true)
    else self:rect(ax+1,Y(118),vis-2,22,{62,62,62}) end
    local hx=math.max(ax,52)                              -- its ends lie under the polarity and monitor buttons
    self:hit('I_RECARM',hx,Y(117),vis-(hx-ax),22,function() m:toggle(s,'I_RECARM') end)
    self:button('I_RECMON',s.I_RECMON==2 and 'mcp_monitor_auto' or s.I_RECMON==1 and 'mcp_monitor_on' or 'mcp_monitor_off',53+d,Y(139),21,20,function() m:toggle(s,'I_RECMON') end)
  end
  self:button('B_MUTE',s.B_MUTE~=0 and 'mcp_mute_on' or 'mcp_mute_off',52+d,Y(161),21,20,function() m:toggle(s,'B_MUTE') end)
  self:button('I_SOLO',s.I_SOLO~=0 and 'mcp_solo_on' or 'mcp_solo_off',52+d,Y(184),21,20,function() m:toggle(s,'I_SOLO') end)
  local io='mcp_io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  self:button('IO',io,51+d,Y(213),23,22,function() self:show_routing(s) end,function() self:send_menu(s) end)
  if L>=317 then -- the envelope button drops out of a short strip
    local mode=math.floor(s.I_AUTOMODE)
    self:button('I_AUTOMODE',ENV[mode] or 'mcp_env',53+d,Y(L-77),21,24,function()
      local items={}
      for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
      self:menu(items)
    end)
  end

  -- Name and track number
  local ntext=sel and cs.name_sel or cs.name or {235,235,235}
  self:text(s.name,4,Y(L-44.5),W-8,18,ntext,'header',1)
  if not mt then self:hit('name',0,Y(L-47),W,27).double=function() self:rename(s) end end
  if not mt then self:text(('%d'):format(s.IP_TRACKNUMBER),0,Y(L-19),W,20,sel and cs.idx_sel or cs.idx or {200,200,200},'bold',1) end
end
-- Flat Madness (CI/SI, Bright/Dark): the macro's rectangles, [x y w h] in points. Rows hang from the panel top (`T+y`) or, like
-- the script's `0 1 0 1` ones, from its bottom (`B(y)`, the script being 320 pt tall). The theme's three strip widths (80, 94, 114)
-- move the right-hand columns; beyond the nearest one the meter takes the difference. Panel art is two translucent cards.
function M:lowerfm(s,W,H,c)
  local m,bm,T,L=self.model,self.bitmaps,c.T,c.L
  local th,sel,mt=self.theme,c.selected,s.master
  local F=W>=114 and 114 or W>=94 and 94 or 80
  local d=math.max(W-F,-8)
  local ax,mw,vx,lx=52,23,32,14 -- column anchor, meter width, fader x and readout x of the 80 pt form
  if F==94 then ax,mw,vx,lx=66,35,46,28 elseif F==114 then ax,mw,vx,lx=86,55,66,48 end
  local function B(v) return T+L-320+v end
  self.ox,self.mx=self.ox-1,self.mx+1                    -- the mixer draws its panel one point left of the strip's own edge
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    if not bm then return false end
    for _,p in ipairs({'mcp_','track_','tcp_'}) do if bm:draw(p..name,state,x+self.ox,y,w,h,self.scale,true) then return true end end
  end
  -- `hx,hw`: a narrower hit box where the art of two buttons overlaps
  local function button(id,name,x,y,w,h,action,menu,hx,hw)
    local state=inside({x=hx or x,y=y,w=hw or w,h=h},self.mx,self.my) and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local p=PLAIN['mcp_'..name] or PLAIN['track_'..name] or {''}
      self:rect(x,y,w,h,{78,78,78});self:rect(x+1,y+1,w-2,h-2,{62,62,62});self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
    end
    return self:hit(id,hx or x,y,hw or w,h,action,menu)
  end

  -- Cards: the strip's grey (the Theme Adjuster's 'MCP background brightness', brighter when selected) shows through the top
  -- card's translucent lower part; the track's colour is only the bar between the cards.
  local P=th.param
  local grey=P('saturncmcp',80)+(sel and P('tcp_saturn_identmcp',10) or 0)
  self:rect(1,T,W,L,bm and bm:tone('mcp_adjust_bg',false,1,100) or {35,35,35})
  self:rect(1,T,W-2,150,{grey,grey,grey,P('saturnalphamcp',255)})
  self:rect(3,T+152,W-8,8,c.under)
  image(sel and 'mcp_adjust_bgsel' or 'mcp_adjust_bg',0,T,W,L)
  image(sel and 'mcp_idxbg_sel' or 'mcp_idxbg',0,B(300),W,20)   -- the footer's art reaches up to round the lower card's corners

  -- Top card: arm, record mode and monitor; automation; input; name; FX; pan
  if not mt then
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',8,T+8,20,20,function() m:toggle(s,'I_RECARM') end,nil,8,18)
    local rm=math.floor(s.I_RECMODE)
    button('I_RECMODE',rm==2 and 'recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'recmode_in' or 'recmode_out',26,T+8,20,20,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',50,T+8,22,20,function() m:toggle(s,'I_RECMON') end)
  end
  local mode=math.floor(s.I_AUTOMODE)
  local envn={[0]='env','env_read','env_touch','env_write','env_latch','env_preview'}
  button('I_AUTOMODE',envn[mode] or 'env',8,T+31,64,20,function()
    local items={}
    for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
    self:menu(items)
  end)
  if not mt then
    if not art('recinput',0,8,T+54,64,20) then self:rect(8,T+54,64,20,{35,35,35}) end
    self:text(self:input_label(s.I_RECINPUT),9.5,T+54,61-11,20,th.bright and {120,120,120} or {80,80,80},'main',1)
    self:hit('I_RECINPUT',8,T+54,64,20,function() self:input_menu(s) end)
  end
  self:text(s.name,0,T+78,W,18,sel and {220,220,220} or {80,80,80},'header',1)
  if not mt then self:hit('name',1,T+78,W,18).double=function() self:rename(s) end end
  local fxon=s.I_FXEN~=0
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',7,T+102,22,20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',29,T+102,18,20,function() m:toggle(s,'I_FXEN') end)
  if not mt then button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',46,T+102,27,20,function() m:open_input_fx(s) end,nil,47,26) end

  -- Pan: balance is one knob with a readout, stereo pan and dual pan are two bars
  local pm=s.I_PANMODE
  local function bar(key,stack,y,pos)
    local name='tcp_'..stack                              -- the mixer falls back to the TCP's art
    if not (bm and bm:get(name,true)) then name='mcp_'..stack end
    if not (bm and bm:stack(name,(clamp(pos,-1,1)+1)/2,7+self.ox,y,68,10,self.scale)) then
      self:rect(7,y+3,68,4,{40,40,40});self:rect(7+(clamp(pos,-1,1)+1)/2*66,y,2,10,{150,150,150})
    end
    self:pan_hit(s,key,7,y,68,10,68)
  end
  if pm>=5 then
    local dual=pm==6
    bar(dual and 'D_DUALPANL' or 'D_PAN','pan_knob_stack_2',T+124,dual and s.D_DUALPANL or s.D_PAN)
    bar(dual and 'D_DUALPANR' or 'D_WIDTH','wid_knob_stack_2',T+136,dual and s.D_DUALPANR or s.D_WIDTH)
  else
    local p=(clamp(s.D_PAN,-1,1)+1)/2
    if not (bm and (bm:knob_frame('mcp_pan_knob_stack',p,17+self.ox,T+134,self.scale) or bm:knob_frame('tcp_pan_knob_stack',p,17+self.ox,T+134,self.scale))) then
      self:pointer(s,7,T+124,20,{60,60,60},true,s.D_PAN)
    end
    self:pan_hit(s,'D_PAN',7,T+124,20,20)
    if not art('pan_labelbg',0,29,T+124,44,20) then self:rect(29,T+124,44,20,{45,45,45}) end
    self:text(pan_label(s.D_PAN),29,T+124,44,20,{150,150,150},'main',1)
  end

  -- Lower card: meter (the scale only, until there is signal), fader on its groove, volume readout
  local mh=L-208
  self.layout={T=T,S=T+168,B=T+168+mh,L=L,meter=true}
  self:meter(s,{x=5,y=T+168,w=mw+d,h=mh,font='main',scale_color={100,100,100},readout_color={160,160,160},readout_y=-1.5,first=6,last=54,step=12},c.colors)
  local fx0=vx+d
  image('mcp_volbg',fx0,T+168,19,mh)                     -- squeezed to the fader's width, as the mixer does
  local thumb=bm and bm:get('mcp_volthumb',true)
  local ftop,fbottom=T+168+12,T+168+mh-12                -- the 24 pt cap stays inside the groove
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  if thumb then
    -- One tall image: the cap sits in its middle rows and the coloured fill runs on down from it, so from the cap's top the
    -- picture is drawn as far as the groove goes (the guide column on its right is left out).
    local k=self.scale/thumb.scale
    local cap=thumb.height/2-24*thumb.scale/2            -- first row of the cap, in image rows
    local x0=self:pxx(fx0+9.5)-math.floor((thumb.width-1)*k/2+.5)
    local y0=self:px(fy)-math.floor(24*self.scale/2+.5)
    local hh=math.min(self:px(T+168+mh)-y0,math.floor((thumb.height-cap)*k))
    if hh>0 then bm:blit(thumb,0,cap,thumb.width-1,math.floor(hh/k+.5),x0,y0,math.floor((thumb.width-1)*k+.5),hh,k~=1) end
  else self:rect(fx0+2,fy-12,15,24,{213,213,213}) end
  image('mcp_main_fadercover',fx0,B(278),19,22)
  local hit=self:hit('D_VOL',fx0,T+168,19,mh)
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy
  self:text(gaintext(s.D_VOL),lx+d,B(278)+1,32,22,{180,180,180},'main',2)

  -- Button column: mute over solo, polarity (the master's mono switch instead), routing
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',ax+3+d,T+166,20,18,function() m:toggle(s,'B_MUTE') end)
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',ax+3+d,T+184,20,18,function() m:toggle(s,'I_SOLO') end)
  if mt then button('MONO',s.mono and 'mono' or 'stereo',ax+3+d,B(220),20,50,function() m:master_mono(s) end)
  else button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',ax+5+d,B(252),17,17,function() m:toggle(s,'B_PHASE') end) end
  local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  button('IO',io,ax+3+d,B(274),20,22,function() self:show_routing(s) end,function() self:send_menu(s) end)

  -- The Theme Adjuster's gloss: a faint highlight over the button groups, drawn last
  if P('gloss',1)==1 then
    local pan=pm<5
    for _,g in ipairs({{8,T+31,64,20},{7,T+102,40,20},{ax+3+d,T+166,20,36},not mt and {8,T+8,38,20} or false,not mt and {50,T+8,22,20} or false,pan and {29,T+124,44,20} or false}) do
      if g then image('gloss',g[1],g[2],g[3],g[4]) end
    end
  end

  -- Track number on the footer: orange while armed
  if not mt then
    local rec=s.I_RECARM~=0
    self:text(('%d'):format(s.IP_TRACKNUMBER),-2.5,B(300),W,20,rec and {255,128,64} or sel and {255,255,255} or {160,160,160},'header',1)
  end
  self.ox,self.mx=self.ox+1,self.mx-1
end
-- iconEX (Dark, Hybrid, Light): the macro's fixed 80 pt strip, rows hung from the 300 pt panel's top and bottom; the track's colour shows
-- only through a slot in the panel art, a light cap marks the selected strip. Width beyond 80 pt goes to the meter and the right-hand columns.
function M:lowerix(s,W,H,c)
  local m,bm,T,L=self.model,self.bitmaps,c.T,c.L
  local th,sel,mt=self.theme,c.selected,s.master
  local d=math.max(W-80,-8)
  local function B(v) return T+L-319+v end              -- measured: the lower controls sit a point below the script's 300 pt frame
  self.ox,self.mx=self.ox-1,self.mx+1                    -- the mixer draws its panel one point left of the strip's own edge
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    if not bm then return false end
    for _,p in ipairs({'mcp_','track_','tcp_'}) do if bm:draw(p..name,state,x+self.ox,y,w,h,self.scale,true) then return true end end
  end
  -- `hx,hw`: a narrower hit box where the art of two buttons overlaps
  local function button(id,name,x,y,w,h,action,menu,hx,hw)
    local state=inside({x=hx or x,y=y,w=hw or w,h=h},self.mx,self.my) and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local p=PLAIN['mcp_'..name] or PLAIN['track_'..name] or {''}
      self:rect(x,y,w,h,{78,78,78});self:rect(x+1,y+1,w-2,h-2,{62,62,62});self:text(p[1],x,y,w,h,p[2] or {150,150,150},'main',1)
    end
    return self:hit(id,hx or x,y,hw or w,h,action,menu)
  end

  -- Panel: the track's colour (the theme's selected grey without one) under the top 160 pt, the art's own grey under the rest, then the
  -- art, whose slot at 150 pt is the only place the colour shows. 'MCP Layout' 2 and 3 swap the art; 1 is the default.
  local lt=clamp(th.param('mcp_solid_color_Df',1),1,3)
  local back=lt==3 and 'mcp_adjust_bg' or lt==2 and 'mcp_sol1_bg' or 'mcp_color_bg'
  self:rect(1,T,W,L+1,bm and bm:tone(back,false,90,20) or {45,45,45}) -- (the art's panel is a point taller than the 300 pt frame)
  self:rect(1,T,W,160,c.custom and c.base or c.colors.col_seltrack or {68,68,68})
  image(back,0,T,W,L+1)
  if sel then image(lt==3 and 'mcp_adjust_bgsel' or 'mcp_sol1_bgsel',0,T,W,L+1) end

  -- Top rows: arm, record mode and monitor; automation; input; name; FX
  if not mt then
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',8,T+8,20,20,function() m:toggle(s,'I_RECARM') end,nil,8,18)
    local rm=math.floor(s.I_RECMODE)
    button('I_RECMODE',rm==2 and 'recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'recmode_in' or 'recmode_out',26,T+8,20,20,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',50,T+8,22,20,function() m:toggle(s,'I_RECMON') end)
  end
  local mode=math.floor(s.I_AUTOMODE)
  local envn={[0]='env','env_read','env_touch','env_write','env_latch','env_preview'}
  button('I_AUTOMODE',envn[mode] or 'env',8,T+31,64,20,function()
    local items={}
    for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
    self:menu(items)
  end)
  if not mt then -- the input is bare text on the panel
    self:text(self:input_label(s.I_RECINPUT),9,T+54,63,20,{120,120,120},'main',0)
    self:hit('I_RECINPUT',8,T+54,64,20,function() self:input_menu(s) end)
  end
  local ix,lb=th.ix,th.param('mcplabelbrightness_Df',175)
  self:text(s.name,7,T+78,W-14,18,sel and ix.name_sel or {lb,lb,lb},'header',1)
  if not mt then self:hit('name',1,T+78,W,18).double=function() self:rename(s) end end
  local fxon=s.I_FXEN~=0
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',6,T+102,22,20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',28,T+102,18,20,function() m:toggle(s,'I_FXEN') end)
  if not mt then button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',46,T+102,27,20,function() m:open_input_fx(s) end,nil,47,26) end

  -- Pan: balance is one knob with a readout, stereo pan and dual pan are two bars
  local pm=s.I_PANMODE
  local function bar(key,stack,y,pos)
    local name='tcp_'..stack                              -- the mixer falls back to the TCP's art
    if not (bm and bm:get(name,true)) then name='mcp_'..stack end
    if not (bm and bm:stack(name,(clamp(pos,-1,1)+1)/2,6+self.ox,y,68,10,self.scale)) then
      self:rect(6,y+3,68,4,{40,40,40});self:rect(6+(clamp(pos,-1,1)+1)/2*66,y,2,10,{150,150,150})
    end
    self:pan_hit(s,key,6,y,68,10,68)
  end
  if pm>=5 then
    local dual=pm==6
    bar(dual and 'D_DUALPANL' or 'D_PAN','pan_knob_stack_2',T+124,dual and s.D_DUALPANL or s.D_PAN)
    bar(dual and 'D_DUALPANR' or 'D_WIDTH','wid_knob_stack_2',T+136,dual and s.D_DUALPANR or s.D_WIDTH)
  else
    local p=(clamp(s.D_PAN,-1,1)+1)/2
    if not (bm and (bm:knob_frame('mcp_pan_knob_stack',p,17+self.ox,T+134,self.scale) or bm:knob_frame('tcp_pan_knob_stack',p,17+self.ox,T+134,self.scale))) then
      self:pointer(s,7,T+124,20,{60,60,60},true,s.D_PAN)
    end
    self:pan_hit(s,'D_PAN',7,T+124,20,20)
    self:text(pan_label(s.D_PAN),29,T+124,44,20,{120,120,120},'main',1)
  end

  -- Meter (the scale only, until there is signal), fader on its groove, volume readout
  local mh=L-214
  self.layout={T=T,S=T+168,B=T+168+mh,L=L,meter=true}
  self:meter(s,{x=8,y=T+166,w=18+d,h=mh+4,font='main',scale_color={100,100,100},readout_color={160,160,160},readout_y=-2,first=6,last=54,step=12,
    labels=th.param('mcpdbscales_Df',1)~=0},c.colors)
  local fx0=30+d
  image('mcp_volbg',fx0+4,T+168,11,mh)                   -- the groove is as wide as the thumb's coloured part
  local thumb=bm and bm:get('mcp_volthumb',true)
  local ftop,fbottom=T+168+10,T+168+mh-10                -- the cap's centre travels inside a 10 pt margin
  local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
  if thumb then
    -- One tall image: the cap is the top of the coloured fill, which runs on down from it, so from the cap's top the picture
    -- is drawn as far as the groove goes (the guide column on its right is left out).
    local k=self.scale/thumb.scale
    local cap=thumb.height/2                             -- first row of the cap, in image rows
    local x0=self:pxx(fx0)
    local y0=self:px(fy-7.5)
    local hh=math.min(self:px(T+168+mh)-y0,math.floor((thumb.height-cap)*k))
    if hh>0 then bm:blit(thumb,0,cap,thumb.width-1,math.floor(hh/k+.5),x0,y0,math.floor((thumb.width-1)*k+.5),hh,k~=1) end
  else self:rect(fx0+2,fy-7.5,15,15,{127,191,255}) end
  local hit=self:hit('D_VOL',fx0,T+168,19,mh)
  hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy
  self:text(gaintext(s.D_VOL),6+d,B(279)+.5,44,18,c.colors.col_tcp_text or {170,170,170},'header',1)

  -- Button column: mute over solo, polarity (the master's mono switch instead), routing
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',55+d,T+166,20,18,function() m:toggle(s,'B_MUTE') end)
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',55+d,T+184,20,18,function() m:toggle(s,'I_SOLO') end)
  if mt then button('MONO',s.mono and 'mono' or 'stereo',55+d,B(222),20,48,function() m:master_mono(s) end) -- the script's 50 pt would touch solo at 300 pt
  else button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',57+d,B(256),17,17,function() m:toggle(s,'B_PHASE') end) end
  local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  button('IO',io,55+d,B(279),20,18,function() self:show_routing(s) end,function() self:send_menu(s) end)

  -- Track number on the footer: orange while armed
  if not mt then
    local rec=s.I_RECARM~=0
    self:text(('%d'):format(s.IP_TRACKNUMBER),-2.5,B(300),W,20,rec and {255,128,64} or sel and ix.idx_sel or ix.idx,'header',1)
  end
  self.ox,self.mx=self.ox+1,self.mx-1
end
-- nvk_THEME (Dark and Light): the script's rows hang from the top (recording input, the racks' box, routing, automation, pan) over the fader and
-- meter, which take what the chain leaves above the bottom-anchored rows (record row, mute row, name, number). Its own rule drops routing,
-- automation and pan on short strips. The track's colour shows only in the number pill; a selected strip is a lighter wash over everything.
-- Assumed Theme Adjuster state: 'Limited' colour mode, default padding/insert height unless the adjuster says otherwise.
function M:nvkrows(s,H,W)
  local P,mt=self.theme.param,s.master
  local p=P(mt and 'master_mcp_mPaddingSize_param' or 'mcp_PaddingSize_param',3)
  local ms=P(mt and 'master_mcp_MeterSize_param' or 'mcp_MeterSize_param',100)/100
  local g={p=p,xs=mt and p-1 or p,iw=W-2-2*p,rw=W-(mt and 3 or 2)} -- measured: the master's panel sits a point left of a track's
  g.ey=p+24+p                                                      -- the racks' box (the script's mcp.extmixer.position)
  -- The theme drops the box on strips of 420 pt or less; the Inspector exists for the racks, so there it keeps a fifth of the height, never under 3 rows (and their divider).
  g.eh=H>420 and H/((mt and 3 or H>792 and 3 or 5)*ms) or math.max(3*self.theme.row_height+5,H/5)
  g.io=g.ey+g.eh+p;g.env=g.io+24+p;g.pan=g.env+24+p
  g.pill=H-p-22;g.name=g.pill-24-p;g.mute=g.name-24-p;g.fxin=g.mute-24-p -- the bottom-anchored rows: number pill, name (the master's mode buttons), mute row, record row
  local limit=g.mute-128                                          -- yLimit: a row this close to the mute row is dropped
  g.ofx,g.oenv,g.opan=g.io>=limit,g.env>=limit,g.pan>=limit
  g.dual=s.I_PANMODE==6
  local above=g.ofx and g.ey+g.eh or g.oenv and g.io+24 or g.opan and g.env+24 or g.pan+(g.dual and 16+p+16 or 36)
  g.vy=above+p;g.vh=(mt and g.mute or g.fxin)-above-2*p
  return g
end
function M:lowernvk(s,W,H,c)
  local m,bm,th,sel,mt,g=self.model,self.bitmaps,self.theme,c.selected,s.master,c.g
  local P=th.param
  local p,x1=g.p,g.xs
  local r=x1+g.iw                                                 -- right edge of the content
  local x3=r-24;local x2=(x1+x3)/2                                -- the three-button columns: left, middle, right
  local function image(name,x,y,w,h) return bm and bm:draw(name,0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    if not bm then return false end
    for _,pre in ipairs({'mcp_','track_','tcp_'}) do if bm:draw(pre..name,state,x+self.ox,y,w,h,self.scale,true) then return true end end
  end
  local function button(id,name,x,y,w,h,action,menu)
    local state=inside({x=x,y=y,w=w,h=h},self.mx,self.my) and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if not art(name,state,x,y,w,h) then
      local pl=PLAIN['mcp_'..name] or PLAIN['track_'..name] or {''}
      self:rect(x,y,w,h,{78,78,78});self:rect(x+1,y+1,w-2,h-2,{62,62,62});self:text(pl[1],x,y,w,h,pl[2] or {150,150,150},'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end
  local function inert(name,x,y,w,h) if not art(name,0,x,y,w,h) then self:rect(x,y,w,h,{62,62,62}) end end -- the theme's custom-action buttons: drawn, not run
  local ink=P('color_picker_DefaultTextColor_r_param',200)
  ink={ink,P('color_picker_DefaultTextColor_g_param',200),P('color_picker_DefaultTextColor_b_param',200)}
  local dark={28,28,28}

  -- Number pill (the track's colour, else the theme's grey) and the name bar, drawn first: the controls sit on them
  local py=g.pill
  local depth=P('color_ColorDepth_param',100)
  if mt then self:rect(x1,py,g.iw,22,sel and {160,160,160} or {20,20,20})
  elseif c.custom then
    local b=c.base;self:rect(x1,py,g.iw,22,{b[1],b[2],b[3],depth==0 and 1 or depth*2.55})
  else local v=sel and 150 or 100;self:rect(x1,py,g.iw,22,{v,v,v}) end
  image(sel and 'mcp_custom_idxBG_sel' or 'mcp_custom_idxBG',x1,py,g.iw,22)
  local tc=ink
  if mt then tc=sel and {0,0,0} or ink
  elseif c.custom then
    local b=c.base                                                -- 'brightness threshold for auto-coloured text': luma scaled so white reads 300
    tc=(.299*b[1]+.587*b[2]+.114*b[3])*300/255>P('color_TextColorThresh_param',233) and dark or ink
  elseif sel then tc=dark end
  local num=mt and s.name or ('%d'):format(s.IP_TRACKNUMBER)
  self:text(num,x1,py,g.iw,22,tc,(not mt and s.IP_TRACKNUMBER>=10) and 'bold' or 'header',1) -- two digits take the smaller value font
  if not mt then
    local ny=g.name
    image(sel and 'mcp_custom_namebg_sel' or 'mcp_custom_namebg',x1,ny,g.iw,24)
    self:text(s.name,x1+4,ny,g.iw-8,24,sel and dark or ink,'header',0) -- left-aligned, a 4 pt margin
    self:hit('name',x1,ny,g.iw,24).double=function() self:rename(s) end
  else -- the master's row of channel-mode buttons: custom actions, drawn only
    inert('custom_stereo_off',x1,g.name,24,24);inert('custom_quad_off',x2,g.name,24,24);inert('custom_surround_off',x3,g.name,24,24)
  end

  -- Mute row (the master's pair is centred) and, for tracks, the record row above it
  local mx=mt and (x1+r)/2-1-24 or x1 -- (measured: the native pair's gap is centred a half point right of the content)
  local sx=mt and mx+27 or x2
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',mx,g.mute,24,24,function() m:toggle(s,'B_MUTE') end)
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',sx,g.mute,24,24,function() m:toggle(s,'I_SOLO') end)
  if not mt then
    button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',x3,g.mute,24,24,function() m:toggle(s,'B_PHASE') end)
    local y=g.fxin
    button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',x1,y,24,24,function() m:open_input_fx(s) end)
    image('mcp_custom_recarm_bg',x2,y,r-x2,24)
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',x2,y,24,24,function() m:toggle(s,'I_RECARM') end)
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',x3,y,24,24,function() m:toggle(s,'I_RECMON') end)
    -- Top row: record mode, then the input field (its art carries the arrow, its text the input's name)
    local rm=math.floor(s.I_RECMODE)
    button('I_RECMODE',rm==2 and 'recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'recmode_in' or 'recmode_out',x1,p,24,24,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
    local ix=x1+24
    if not art('recinput',0,ix,p,r-ix,24) then self:rect(ix,p,r-ix,24,{28,28,28}) end
    self:text(self:input_label(s.I_RECINPUT),ix+4,p,r-ix-28,24,ink,'header',0)
    self:hit('I_RECINPUT',ix,p,r-ix,24,function() self:input_menu(s) end)
  end

  -- Routing, FX, automation (and the master's mono switch), pan
  if not g.ofx then
    local y=g.io
    local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
    button('IO',io,x1,y,24,24,function() self:show_routing(s) end,function() self:send_menu(s) end)
    local bx=x1+27;local bw=math.max(r-bx,48) -- the FX button and its bypass need 48 pt: a strip under 83 pt lets them reach the frame's edge
    image('tcp_custom_fx_BG',bx,y,bw,24)
    local fxon=s.I_FXEN~=0
    button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',bx,y,24,24,
      function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
    button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',bx+bw-24,y,24,24,function() m:toggle(s,'I_FXEN') end)
  end
  if not g.oenv then
    local y=g.env
    local mode=math.floor(s.I_AUTOMODE)
    local envn={[0]='env','env_read','env_touch','env_write','env_latch','env_preview'}
    button('I_AUTOMODE',envn[mode] or 'env',x1,y,24,24,function()
      local items={}
      for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
      self:menu(items)
    end)
    if mt then button('MONO',s.mono and 'mono' or 'stereo',x1+27,y,r-x1-27,24,function() m:master_mono(s) end)
    elseif not g.ofx then inert('custom_customFX',x2,y,24,24);inert('custom_customFX2',x3,y,24,24) end
  end
  if not g.opan then
    local y,pm=g.pan,s.I_PANMODE
    if g.dual then
      for i,key in ipairs({'D_DUALPANL','D_DUALPANR'}) do
        local yy=y+(i-1)*(16+p)
        image('mcp_panbg',x1,yy,g.iw,16)
        local v=clamp(s[key],-1,1)
        local tw=bm and bm:size('mcp_panthumb',true) or 16
        image('mcp_panthumb',x1+(v+1)/2*(g.iw-tw),yy,nil,nil)
        self:pan_hit(s,key,x1,yy,g.iw,16,g.iw-tw)
      end
    else
      local function knob(key,stack,x)
        local v=clamp(s[key],-1,1)
        image('mcp_custom_Pan_Knob_BG',x,y,36,36)
        local pos=(v+1)/2
        if not (bm and (bm:knob_frame(stack,pos,x+18+self.ox,y+18,self.scale) or bm:knob_frame('tcp_'..stack:sub(5),pos,x+18+self.ox,y+18,self.scale))) then
          self:pointer(s,x,y,36,{200,200,200},true,v)
        end
        self:pan_hit(s,key,x,y,36,36)
      end
      knob('D_PAN','mcp_pan_knob_stack',x1)
      if pm==5 then knob('D_WIDTH','mcp_wid_knob_stack',r-36) end
    end
  end

  -- Fader on its groove, then the meter on a flat panel
  local vy,vh=g.vy,g.vh
  if vh>=24 then
    self.layout={T=g.ey,S=vy,B=vy+vh,L=H-g.ey,meter=true}
    image('mcp_custom_VolFader_BG',x1,vy,24,vh)
    local ftop,fbottom=vy+14,vy+vh-14                             -- the 28 pt cap stays inside the groove
    local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
    if not image('mcp_volthumb',x1,fy-14,nil,nil) then self:rect(x1+2,fy-12,20,24,{20,132,108}) end
    local hit=self:hit('D_VOL',x1,vy,24,vh)
    hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy
    self:rect(x1+27,vy,r-x1-27,vh,{38,38,38})
    self:meter(s,{x=x1+27,y=vy,w=r-x1-27,h=vh,font='main',scale_color={255,255,255},scale_fade=function(d) return math.max(.3,1-(d-6)*.0133) end,readout_color={255,255,255},first=vh<122 and 18 or 6,last=(mt and vh<178) and 42 or 54,step=12},c.colors) -- (the peak readout needs the first label's place, the master's loudness readout the last one's)
  end
  -- The strip's rounded corners: only the art's four arcs. Its straight bands (2 px at the sides, 4 px below) are the gap between
  -- strips, which the mixer shows outside the frame, so they are left out and the gap is the mixer's colour.
  local a=bm and bm:get('mcp_custom_TrackCorners',true)
  if a and a.w==40 and a.h==40 then
    local k=self.scale/a.scale;local function q(v) return math.floor(v*k+.5) end
    local X,Y,R,B=self:pxx(0),self:px(0),self:pxx(g.rw),self:px(H)
    local function corner(sx,sy,sw,sh,dx,dy) bm:blit(a,a.x+sx,a.y+sy,sw,sh,dx,dy,q(sw),q(sh),k~=1) end
    corner(0,0,17,9,X,Y);corner(23,0,17,9,R-q(17),Y);corner(0,29,17,7,X,B-q(7));corner(23,29,17,7,R-q(17),B-q(7))
  end
end
-- Horizon (Dark and Light): the script's rows in points (its 200% pixels halved). The lists hang from the top, the IO, pan and value rows
-- from the lists, the input, button, name and number rows from the bottom; the meter and fader take what is left, and give up the input
-- row, then the record row, then the polarity row once under 104 pt. The master uses the same rectangles with no input or record rows.
-- Assumed Theme Adjuster state: its defaults (Default layout A, values shown, list elements 1, brightness 1, track type Audio).
function M:hzrows(s,H,W)
  local P,mt=self.theme.param,s.master
  local sw,sh,row=P('mcp_space_w',2),P('mcp_space_h',2),self.theme.row_height
  local cell=row-1                                                  -- a list cell is a point shorter than its pitch
  local g={sw=sw,sh=sh,cell=cell,row=row,vals=P('mcp_values_parm',1)~=0}
  g.tx,g.tw=sw,W-1-2*sw                                             -- the panel art behind it, and the input and name rows
  g.cx,g.cw=sw+2,g.tw-4                                             -- the column of lists, IO, pan, meter and fader
  g.y0=sh+2+cell+.5                                                 -- first list row, under the FX header
  local ext=P('mcp_ext_size',50)/100*(H-sh-(16+20+sw+2*sh))-(4+40+4*cell+5*sh) -- the lists' share of the strip
  g.ext=math.max(ext,5*row+11)                                      -- the theme drops them under 100 pt; the Inspector keeps five rows
  g.io=g.y0+g.ext+2;g.pan=g.io+cell+2;g.pv=g.pan+22;g.vm=g.vals and g.pv+cell+2 or g.pan+22
  g.idx,g.name,g.mute,g.rec,g.ph=H-16,H-38,H-60,H-82,H-104
  g.in1,g.in2=H-138,H-122
  local tb=H-140.5                                                  -- bottom of the panel art
  local function short() return tb-(g.vals and 12 or 3)-g.vm<104 end
  g.h1=mt or short();if g.h1 then tb=tb+34 end
  g.h2=mt or short();if g.h2 then tb=tb+22 end
  g.h3=short();if g.h3 then tb=tb+22 end
  g.tb=tb;g.vl=tb-cell-1.5;g.vmb=tb-(g.vals and 2+cell+1 or 3);g.vmh=g.vmb-g.vm
  return g
end
-- Strip, panel art and divider. The track's colour (darkened or lightened by the script's adaptive tone) lies under a 75% wash of the
-- theme's grey, brighter when selected; the panel art goes over both.
function M:hzback(s,H,W,g,c)
  local th,bm=self.theme,self.bitmaps
  local function tone(i,d) return th.tone and th.tone[i] or d end
  local lv=clamp(th.param('mcp_brightness',1),1,3)
  local under=tone(9,{86,92,93})
  if c.custom then
    local b=c.base;local t=.35*b[1]+.46*b[2]+.19*b[3]
    local a=math.min(255,1+math.abs(t-90))/255;local mix=t<90 and 255 or 0
    under={b[1]+(mix-b[1])*a,b[2]+(mix-b[2])*a,b[3]+(mix-b[3])*a}
  end
  c.under=under
  local w=c.selected and tone(({9,11,13})[lv],{86,92,93}) or tone(({2,4,5})[lv],{37,38,39})
  self:rect(0,0,W,H,tone(1,{30,30,31}))                             -- the 1 pt divider and the strip's top edge
  -- (measured against the native strips: an unselected strip's wash is 88% opaque, a selected coloured strip's 75% over the track colour
  -- darkened to about 0.35 of itself; the name bar's fill keeps the script's own darkening)
  local su=c.custom and c.selected and {under[1]*.63,under[2]*.63,under[3]*.63} or under
  self:rect(0,1,W-1,H-1,su);self:rect(0,1,W-1,H-1,{w[1],w[2],w[3],c.selected and 191 or 225})
  if bm then bm:draw(({'mcp_top3_bg','mcp_top2_bg','mcp_top_bg'})[lv]..(c.selected and 'sel' or ''),0,g.tx+self.ox,g.sh,g.tw,g.tb-g.sh,self.scale,true) end
end
function M:lowerhz(s,W,H,c)
  local m,bm,th,sel,mt,g=self.model,self.bitmaps,self.theme,c.selected,s.master,c.g
  local P=th.param
  local lv=clamp(P('mcp_brightness',1),1,3)
  local function tone(i,d) return th.tone and th.tone[i] or d end
  local ink,sh,cx,cw,cell=tone(15,{222,222,222}),g.sh,g.cx,g.cw,g.cell
  local function image(name,x,y,w,h,state) return bm and bm:draw(name,state or 0,x+self.ox,y,w,h,self.scale,true) end
  local function art(name,state,x,y,w,h)
    if not bm then return false end
    for _,pre in ipairs({'mcp_','track_','tcp_'}) do if bm:draw(pre..name,state,x+self.ox,y,w,h,self.scale,true) then return true end end
  end
  -- A button is a background image (left, right or plain; lighter when the strip is selected) under the control's own three-state sheet.
  local bgname=({'track_button3','track_button2','track_button'})[lv]
  local function button(id,name,x,y,w,h,action,menu,bg)
    local state=inside({x=x,y=y,w=w,h=h},self.mx,self.my) and ((self.g.mouse_cap&1)~=0 and 2 or 1) or 0
    if bg then image(bgname..(bg~='' and '_'..bg or '')..'_bg'..(sel and 'sel' or ''),x,y,w,h) end
    if not art(name,state,x,y,w,h) then
      local pl=PLAIN['mcp_'..name] or PLAIN['track_'..name] or {''}
      if not bg then self:rect(x,y,w,h,{62,62,62}) end
      self:text(pl[1],x,y,w,h,pl[2] or {150,150,150},'main',1)
    end
    return self:hit(id,x,y,w,h,action,menu)
  end
  local function white(a) return {255,255,255,a or 255} end

  -- FX header (its bypass light at the right) and the IO row, each a cell of the list column
  local fxon=s.I_FXEN~=0
  button('FX',#s.fx==0 and 'fx_empty' or fxon and 'fx_norm' or 'fx_dis',cx,sh+2,cw,cell,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  self:text('FX',cx+3,sh+1.5,cw-14,cell,ink,'list',0)
  button('I_FXEN',#s.fx==0 and 'fxempty_v' or fxon and 'fxon_v' or 'fxoff_v',cx+cw-8,sh+2,8,cell,function() m:toggle(s,'I_FXEN') end)
  local io='io'..(#s.sends>0 and '_s' or '')..((s.receives or 0)>0 and '_r' or '')..(s.B_MAINSEND==0 and '_dis' or '')
  button('IO',io,cx,g.io,cw,cell,function() self:show_routing(s) end,function() self:send_menu(s) end)
  self:text('IO',cx+3,g.io-.5,cw-30,cell,ink,'list',0)

  -- Pan: a knob (stereo pan adds the width knob beside it; dual pan is two bars). The frames of the stack are windows over colour
  -- rectangles, so the colour shows only on the side the knob is turned to.
  local pm=s.I_PANMODE
  local kc=(W-.5)/2
  local function colour(param,d) local n=P(param,d);return n==0 and tone(14,{195,198,197}) or th.palette and th.palette[n] or {200,200,200} end
  local function knob(key,stack,x,y,windows)
    local v=clamp(s[key],-1,1)
    for _,w in ipairs(windows) do self:rect(x+w[1],y+3,w[2],14,w[3]) end
    image('tcp_knob_bg',x,y,20,20)
    local pos=(v+1)/2
    if not (bm and bm:knob_frame('tcp_'..stack,pos,x+10+self.ox,y+10,self.scale)) then self:pointer(s,x,y,20,{200,200,200},true,v) end
    self:pan_hit(s,key,x,y,20,20)
  end
  local pl,pr,wc=colour('panL_color',4),colour('panR_color',1),colour('width_color',8)
  if pm==6 then
    for i,key in ipairs({'D_DUALPANL','D_DUALPANR'}) do
      local y=g.pan+(i-1)*10;local v=clamp(s[key],-1,1);local bx=kc-20
      image('tcp_value_bg',bx,y,40,10)
      local mid=bx+20;local px=mid+v*18
      self:rect(math.min(mid,px),y+2,math.abs(px-mid),6,i==1 and pl or pr)
      self:rect(px-.5,y+1,1,8,ink)
      self:pan_hit(s,key,bx,y,40,10,36)
    end
  else
    local two=pm==5
    knob('D_PAN','pan_knob_stack',kc-(two and 20 or 10),g.pan,{{3,7,pl},{10,7,pr}})
    if two then knob('D_WIDTH','wid_knob_stack',kc,g.pan,{{3,14,wc}}) end
  end
  if g.vals then
    image('tcp_value_bg',cx,g.pv,cw,cell)
    local dim=white(128)
    if pm==6 or pm==5 then
      local a,b=pm==6 and s.D_DUALPANL or s.D_PAN,pm==6 and s.D_DUALPANR or s.D_WIDTH
      self:text(pan_label(a),cx,g.pv,cw/2,cell,dim,'main',1)
      self:text(pm==6 and pan_label(b) or ('%dW'):format(math.floor(b*100+.5)),cx+cw/2,g.pv,cw/2,cell,dim,'main',1)
    else self:text(pan_label(s.D_PAN),cx,g.pv,cw,cell,dim,'main',1) end
  end

  -- Meter and fader: the meter on its dark panel in the left half of the block, the fader's cap and lane in the right half; the cap's
  -- centre travels 19 pt inside the block, and the script's faint level lines run from the lane's left edge to its middle.
  local vh=g.vmh
  self.layout={T=g.io,S=g.vm,B=g.vmb,L=H-g.io,meter=true}
  if vh>=44 then
    local mx,mw=cx+2,cw/2-4
    image('meter_bg_mcp',mx,g.vm+2,mw,vh-4)
    self:meter(s,{x=mx+.5,y=g.vm+2.5,w=mw-1,h=vh-5,font='main',scale_color={106,113,113},scale_fade=function(d) return 1-.85*(d-6)/48 end,readout_color={106,113,113},readout_y=-.5,first=6,last=54,step=12},c.colors) -- (the script's scale colours: tone10 at the top, tone8 at a quarter opacity at the bottom)
    local vx,vw=cx+cw/2,cw/2
    local bx,by,bw,bh=vx+1,g.vm+16,vw-1.5,vh-32
    self:rect(bx+bw/2-.5,by,1,bh,tone(1,{30,30,31}))
    local top=bh*.281
    local function line(y,wd,a) self:rect(bx+(wd<.4 and bw/4 or 0),y,bw*wd,1,{222,222,222,a}) end -- the short lines start a quarter of the way in
    local function lines(y0,h,list) for _,l in ipairs(list) do line(y0+l[1]*h,l[2],l[3]) end end
    line(by,1,52);lines(by,top,{{.27,.25,52},{.52,.5,40},{.77,.25,40}})
    lines(by+top,bh-top,{{.09,.25,40},{.175,.5,40},{.278,.25,40},{.395,.5,40},{.456,.25,40},{.51,.5,40},{.564,.25,40},{.605,.5,26},
      {.652,.25,26},{.71,.5,26},{.763,.25,26},{.825,.5,13},{.9025,.25,13}})
    line(by+bh-1,1,13)
    local ftop,fbottom=g.vm+19,g.vmb-19
    local fy=fbottom-self.mapping.to_position(s.D_VOL)*(fbottom-ftop)
    local cap=mt and 'mcp_master_volthumb' or 'mcp_volthumb'
    local tw,th2;if bm then tw,th2=bm:size(cap,true) end
    if tw then bm:draw(cap,0,vx+vw/2-tw/2+.5+self.ox,fy-th2/2-1,nil,nil,self.scale,true) -- (measured: the native cap sits a point higher and half a point right of the block's centre)
    else self:rect(vx+vw/2-8,fy-8,16,16,{170,170,170}) end
    local hit=self:hit('D_VOL',vx,g.vm,vw,vh)
    hit.kind,hit.token,hit.top,hit.bottom,hit.fader_y='D_VOL',s,ftop,fbottom,fy
  end
  if g.vals then
    image('tcp_value_bg',cx,g.vl,cw,cell)
    self:text(s.D_VOL>0 and gaintext(s.D_VOL)..'dB' or '-inf',cx,g.vl,cw,cell,white(128),'main',1)
  end

  -- Input block: the input's name over a second row of input FX capsule and record mode (tracks only, and only while the fader has room)
  local ix,iw=g.tx,g.tw
  if not g.h1 then
    image('tcp_recinput',ix,g.in1,iw,32)
    self:text(self:input_label(s.I_RECINPUT),ix+4,g.in1,iw-21,16,ink,'main',0)
    self:hit('I_RECINPUT',ix,g.in1,iw,16,function() self:input_menu(s) end)
    button('INFX',(s.recfx or 0)>0 and 'fx_in_norm' or 'fx_in_empty',ix,g.in2,12,16,function() m:open_input_fx(s) end)
    local rm=math.floor(s.I_RECMODE)
    button('I_RECMODE',rm==2 and 'recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'recmode_in' or 'recmode_out',ix+10,g.in2,iw-10,16,function()
      local items={}
      for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
      self:menu(items)
    end)
  end

  -- Buttons: a centred pair of columns, rows hanging from the name bar (polarity and automation, record arm and monitor, mute and solo)
  local bx=W/2-21;local bx2=bx+21
  button('B_MUTE',s.B_MUTE~=0 and 'mute_on' or 'mute_off',bx,g.mute,21,20,function() m:toggle(s,'B_MUTE') end,nil,'left')
  button('I_SOLO',s.I_SOLO~=0 and 'solo_on' or 'solo_off',bx2,g.mute,21,20,function() m:toggle(s,'I_SOLO') end,nil,'right')
  if not mt and not g.h2 then
    button('I_RECARM',s.I_RECARM~=0 and 'recarm_on' or 'recarm_off',bx,g.rec,21,20,function() m:toggle(s,'I_RECARM') end,nil,'left')
    button('I_RECMON',s.I_RECMON==2 and 'monitor_auto' or s.I_RECMON==1 and 'monitor_on' or 'monitor_off',bx2,g.rec,21,20,function() m:toggle(s,'I_RECMON') end,nil,'right')
  end
  if not g.h3 then
    local y=g.h2 and g.rec or g.ph                                  -- the polarity row drops into the record row's place when that is hidden
    if mt then button('MONO',s.mono and 'mono' or 'stereo',bx,y,20,20,function() m:master_mono(s) end,nil,'')
    else button('B_PHASE',s.B_PHASE~=0 and 'phase_inv' or 'phase_norm',bx,y,20,20,function() m:toggle(s,'B_PHASE') end,nil,'') end
    local mode=math.floor(s.I_AUTOMODE)
    local envn={[0]='env','env_read','env_touch','env_write','env_latch','env_preview'}
    button('I_AUTOMODE',envn[mode] or 'env',bx+22,y,20,20,function()
      local items={}
      for i,label in ipairs(AUTOMODES) do items[#items+1]={label,function() m:set(s,'I_AUTOMODE',i-1) end,checked=mode==i-1} end
      self:menu(items)
    end,nil,'')
  end

  -- Name bar (the track's colour fills its inner rectangle) and the number footer (the track's colour, else the theme's grey)
  if c.custom then self:rect(g.tx+2,g.name+2,g.tw-4,16,c.under) end
  image('tcp_namebg_custom',g.tx,g.name,g.tw,20)
  self:text(mt and 'Master' or s.name,g.tx+4.5,g.name+1.75,g.tw-10,16,white(),'header',0)
  if not mt then self:hit('name',g.tx,g.name,g.tw,20).double=function() self:rename(s) end end
  local foot=c.custom and c.base or tone(9,{86,92,93})
  local lum=c.custom and .35*c.base[1]+.46*c.base[2]+.19*c.base[3] or 0
  local dark=lum>=110
  self:rect(0,g.idx,W-1,16,foot)
  local num=mt and 0 or s.IP_TRACKNUMBER
  local nsz,tsz=16,8                                                -- where the number sits and how far the icon leaves it
  if num>=10000 then nsz,tsz=19,15 elseif num>=1000 then nsz,tsz=18,13 elseif num>=10 then nsz,tsz=18,10 end
  local icon='layout_type_'..(dark and 'ad_' or '')..(mt and 'master' or 'audio')
  image('track_'..icon,(W-20)/2-tsz,g.idx-2,20,20)
  self:text(('%d'):format(num),nsz,g.idx-.5,W-nsz-1,16,dark and {0,0,0} or {255,255,255},'bold',1)
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
  local frx=self.theme and self.theme.layout=='frxst'
  local md=self.theme and self.theme.layout=='mydaw'
  local cx=self.theme and self.theme.layout=='csixsx'
  local ix=self.theme and self.theme.layout=='iconex'
  local nv=self.theme and self.theme.layout=='nvk'
  local hz=self.theme and self.theme.layout=='horizon'
  local fm=ix or self.theme and self.theme.layout=='flatmadness' -- iconEX's racks are the same kind of list cells and handles
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
  local L=v2 and clamp(H-200,300,430) or v3 and clamp(H-200,260,340) or g80 and clamp(H-200,260,450) or frx and math.min(292,H-72) or md and clamp(H-200,300,380) or cx and clamp(H-250,290,371) or ix and clamp(H-220,300,320) or fm and clamp(H-250,300,380) or clamp(H-57,300,stock6 and 446 or 380)
  local ng=nv and self:nvkrows(s,H,W)
  if nv then L=H-ng.ey-ng.eh end -- the racks' box ends where the script's routing row begins (the rack code keeps 5 pt for its divider)
  local hg=hz and self:hzrows(s,H,W)
  if hz then L=H-(hg.y0+hg.ext-3) end -- the lists' room: their share of the strip, less the divider and the pinned row
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
  local themed=bm and (stock6 or v3 or g80 or frx or md or cx or fm or nv or hz or bm.full_artwork)
  local srow=self.theme and self.theme.send_row_height or row -- 80gray's send rows are taller than its inserts
  if themed and not s.master and self.r.IsTrackSelected then selected=self.r.IsTrackSelected(s.track) end
  -- CSIX writes its own text colours (selected, other) into each edition's mixer script. Its master
  -- strip is laid out differently from the track strip, so it keeps the plain generic treatment.
  local csix=bm and bm.full_artwork and not s.master and self.theme.csix
  local function pick(sel,other) if selected then return sel end return other end
  if csix then
    ntext=pick(csix.name_sel,csix.name) or ntext
    itext=pick(csix.idx_sel,csix.idx) or itext
  end
  -- What REAPER puts under translucent mixer art: the track's colour, else the theme's panel colour.
  local under=custom and base or colors[selected and 'col_seltrack' or 'col_seltrack2'] or {73,75,78}
  -- CSIX AE/SX: the panel's wash is the track's colour when selected (the theme's selected grey without one), the
  -- theme's unselected grey otherwise; the racks see the track's colour a quarter dimmer.
  local tint=cx and (selected and (custom and base or colors.col_seltrack) or colors.col_seltrack2) or nil
  if cx and custom then under=mul(base,.75) end
  local hc={g=hg,base=base,custom=custom,colors=colors,selected=selected}
  if hz then self:hzback(s,H,W,hg,hc)
  elseif nv then -- the mixer's colour, the strip's grey, and a white wash over a selected strip (alpha 28%)
    self:rect(0,0,W,H,colors.col_mixerbg or {40,40,40});self:rect(0,0,ng.rw,H,{64,64,64})
    if selected then self:rect(0,0,ng.rw,H,{255,255,255,self.theme.param('color_SelectionOpacity_param',28)*2.55}) end
  else self:rect(0,0,W,T+1,fm and (bm and (ix and bm:tone('mcp_fxlist_bg') or bm:tone('mcp_adjust_bg',false,1,100)) or {35,35,35}) or bm and (bm.full_artwork or md or cx) and under or v3 and {38,38,38} or {61,61,61}) end
  -- theFRXST keeps its racks inside the strip: below the name bar, inset from the edges.
  local Y0,RX,fullW=md and 0 or 1,0,W
  if frx then
    Y0,RX=23,5
    -- The strip is the track's colour seen through the theme's translucent background art,
    -- plus a 10% wash of that colour over the racks of the selected track.
    self:rect(0,0,W,H,under)
    if bm and not (selected and bm:draw('mcp_bgsel',0,self.ox,-3,W,H+3,self.scale,true)) then bm:draw('mcp_bg',0,self.ox,-3,W,H+3,self.scale,true) end
    if selected and custom then self:rect(4,23,W-8,H-115,{base[1],base[2],base[3],25}) end
    W=W-6;self.ox=self.ox+RX;self.mx=self.mx-RX
  elseif nv then Y0,RX=ng.ey,ng.xs;W=ng.iw;self.ox=self.ox+RX;self.mx=self.mx-RX -- the racks' box
  elseif hz then Y0,RX=hg.y0,hg.cx-1;W=hg.cw+.5;self.ox=self.ox+RX;self.mx=self.mx-RX -- the lists' column
  elseif themed and not fm then -- (Flat Madness ships this art but its mixer does not draw it)
    local function backing(name) return bm:draw(name,0,self.ox,0,W,T+1,self.scale,true) end
    if not (selected and backing('mcp_extmixbgsel')) then backing('mcp_extmixbg') end
  end
  local n=math.max(0,math.floor((T-(fm and 10 or 5)-Y0)/row)) -- Flat Madness's list backdrops end in 3 pt handles
  local sendrows=n>=4 and math.max(1,math.floor(n*.25+.5)) or n>=2 and 1 or 0
  -- The last send-rack row is pinned to the track's own output (master/parent send); the master has none.
  local outrow=not s.master and self.r.GetMasterTrack~=nil
  if outrow and n>=3 then sendrows=math.max(2,sendrows) end
  local fxrows=n-sendrows
  if srow~=row then fxrows=math.max(0,math.floor((T-5-Y0-(frx and 3 or 0)-sendrows*srow)/row)) end -- theFRXST's racks end above its panel
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
  local listbg=bm and (compact6 or md or cx or fm or bm.full_artwork)
  -- Mydaw's lists stop short of the strip's right edge, where the backdrop shows as a thin line.
  local edge=md and 1.5 or 0
  if nv and ng.eh>0 then bm:draw('mcp_fxlist_bg',0,self.ox,Y0,W,ng.eh-1,self.scale,true) end -- one backdrop under inserts and sends
  if listbg and fxrows>0 then
    if fm then bm:draw('mcp_fxlist_bg',0,-1+self.ox,0,W-2,Y0+fxrows*row,self.scale,true) -- the art's overhang is the handle below it
    else bm:draw('mcp_fxlist_bg',0,self.ox,Y0,W-edge,fxrows*row,self.scale,true) end
  end
  for i=1,fxrows do
    local fx=s.fx[i+self.fx_offset];local y=Y0+(i-1)*row
    local art=fx and (fx.offline and 'mcp_fxlist_off' or fx.enabled and 'mcp_fxlist_norm' or 'mcp_fxlist_byp') or 'mcp_fxlist_empty'
    local hover=inside({x=0,y=y,w=W,h=row},self.mx,self.my)
    if nv then if fx then self:sprite(art,hover and 1 or 0,0,y,W,row) end -- the art's own transparent edges make the cell's inset; an empty slot draws none
    elseif hz then self:sprite(art,hover and 1 or 0,0,y,W,row) -- the art's own overhang and transparent edges make the 9 pt cell and its gap
    elseif fm then self:sprite(art,hover and 1 or 0,-1.5,y-1,W-1,row) -- the art's own transparent edges make the 13 pt slots and their gaps
    else self:sprite(art,hover and 1 or 0,md and .5 or -1,y,W-(md and 2.5 or 2),row) end
    if fx then
      local c=fx.offline and col('mcp_fx_offlined',{156,58,58}) or fx.enabled and col('mcp_fx_normal',{216,216,216}) or col('mcp_fx_bypassed',{160,126,59})
      local left=nv and 1 or md and 4 or cx and 3 or fm and (ix and 4 or 5) or hz and 1.5 -- these themes align insert names left, as their mixers do
      self:text(fx.label or fx.name,left or 7.5,y+(nv and .5 or -.5),W-(left and left+5 or 19.5),row,c,'list',left and 0 or 1)
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
  self.fx_box={x=RX,y=Y0,w=W,h=fxrows*row,rows=fxrows}
  scrollbar('fx_bar',#s.fx,fxrows,self.fx_offset,Y0,row)
  local sep=Y0+fxrows*row+(fm and 0 or hz and 3 or .5)
  if n>0 and not s.master then self:rect(0,sep,W,1,{255,255,255,26}) end
  local sy=sep+(fm and 4.5 or hz and 4 or 3.5)
  if listbg and sendrows>0 then
    if fm then bm:draw('mcp_sendlist_bg',0,-1+self.ox,sy-.5,W-2,sendrows*srow+(outrow and srow+2 or 0)+.5,self.scale,true)
    else bm:draw('mcp_sendlist_bg',0,self.ox,sy,W,sendrows*srow,self.scale,true) end
  end
  for i=1,sendrows do
    local send=s.sends[i+self.send_offset];local y=sy+(i-1)*srow
    local art=not send and 'mcp_sendlist_empty' or send.kind=='midi' and (nv and 'mcp_sendlist_norm' or 'mcp_sendlist_midihw') or send.mute and 'mcp_sendlist_mute' or 'mcp_sendlist_norm'
    local hover=inside({x=0,y=y,w=W,h=srow},self.mx,self.my)
    if nv then if send then self:sprite(art,hover and 1 or 0,0,y,W,srow) end elseif hz then self:sprite(art,hover and 1 or 0,0,y,W,srow) elseif fm then self:sprite(art,hover and 1 or 0,-2,y-1,W-1.5,srow) else self:sprite(art,hover and 1 or 0,-1,y,W-3,srow) end
    if send then
      local c=send.kind=='midi' and col('mcp_send_midihw',{70,185,254}) or send.mute and col('mcp_sends_muted',{228,94,101}) or col('mcp_sends_normal',{254,207,103})
      local knob=send.kind~='midi' and not hz and bm and bm:get('mcp_send_knob_stack')
      self:text(send.name,nv and 1 or hz and 1.5 or fm and 5 or 6,y+(nv and .5 or -.5),W-14-(knob and 15 or 0),srow,c,'sends',0)
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
  self.send_box={x=RX,y=sy,w=W,h=sendrows*srow,rows=sendrows}
  if outrow then -- set apart from the sends: its own divider, centred neutral text, never scrolls
    local y=sy+sendrows*srow+2;local on=s.B_MAINSEND~=0
    self:rect(0,y-1.5,W,1,{255,255,255,40})
    local hover=inside({x=0,y=y,w=W,h=srow},self.mx,self.my)
    if nv then self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,0,y,W,srow) elseif hz then self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,0,y,W,srow) elseif fm then self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,-1.5,y-1,W-1,srow) else self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,-1,y,W-2,srow) end
    local c=on and col('mcp_fx_normal',{216,216,216}) or col('mcp_sends_muted',{228,94,101})
    self:text(s.parent and 'Parent send' or 'Master send',hz and 1.5 or 7.5,y-.5,hz and W-3 or W-19.5,srow,c,'list',hz and 0 or 1)
    if not s.owner and self.root.shown_main then self:rect(2.5,y+2,1.5,srow-4,c) end
    self:hit('output',0,y,W,srow,function() if not s.owner then self.root.choice[s.guid]=nil end end,function() self:output_menu(s) end)
  end
  scrollbar('send_bar',#s.sends,sendrows,self.send_offset,sy,srow)

  if frx or nv or hz then W=fullW;self.ox=self.ox-RX;self.mx=self.mx+RX end
  if nv then return self:lowernvk(s,W,H,{g=ng,base=base,custom=custom,colors=colors,selected=selected}) end
  if hz then return self:lowerhz(s,W,H,hc) end
  if frx then return self:lowerfx(s,W,H,{T=T,base=base,custom=custom,colors=colors,selected=selected}) end
  if v3 then return self:lower3(s,W,H,{T=T,L=L,base=base,custom=custom,colors=colors}) end
  if md then return self:lowermd(s,W,H,{T=T,base=base,custom=custom,colors=colors,selected=selected}) end
  if ix then return self:lowerix(s,W,H,{T=T,L=L,base=base,custom=custom,colors=colors,selected=selected}) end
  if fm then return self:lowerfm(s,W,H,{T=T,L=L,base=base,custom=custom,colors=colors,selected=selected,under=under}) end
  if cx then return self:lowercsix(s,W,H,{T=T,L=L,base=base,custom=custom,colors=colors,selected=selected,tint=tint or {150,150,150}}) end
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
    -- The name bar's art ends in a transparent band, and the number tile's art starts with one: the
    -- track's colour shows through both, so everything below the panel is laid in that colour first.
    local panel_tone=bm:tone('mcp_volbg',true)
    if csix then
      self:rect(0,B,W,H-B,under)
      if panel_tone then self:rect(0,S,W,B-S,panel_tone) end
      self:sprite('mcp_namebg',0,0,B,W,label_h)
      -- A name bar that shows the track's colour (DM editions) has no fixed text colour: go by what is on screen.
      if not pick(csix.name_sel,csix.name) then ntext=shade(2,B+6) end
    elseif panel_tone then self:rect(0,S,W,B+label_h-S,panel_tone) end
  end
  self:rect(0,T+.5,W,.5,{255,255,255,26})
  if not cover and csix then
    self:rect(0,T+1,W,31,under) -- translucent button art over the track's colour, as in the mixer
  elseif not cover then
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
    -- CSIX's volume readout sits on its own box, as wide as the meter and fader, up to the record tab.
    if csix then self:sprite('mcp_vol_label',0,1,S,W-32,20) end
    self:text(gaintext(s.D_VOL),meter and fxl-29 or 0,S+4,meter and 48 or fxl+25,19,csix and pick(csix.vol_sel,csix.vol) or {100,100,100},'main',1)
    if meter then self:meter(s,{x=3,y=ftop,w=25+extra,h=SH-24,readout_color=csix and csix.readout},colors) end
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
    -- CSIX's cell is 36 pt wide but its art ends 2 pt short of it; the mixer's 76 pt strip clips that margin.
    if not s.master then self:button('I_RECARM',s.I_RECARM~=0 and 'mcp_recarm_on' or 'mcp_recarm_off',compact6 and bx or W-(csix and 34 or 36),y+(stock6 and self.theme.recarm_y or 0),compact6 and 20 or 36,compact6 and 20 or 24,function() m:toggle(s,'I_RECARM') end) end
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
    local idxart=csix and not selected and 'mcp_idxbg' or 'mcp_idxbg_sel' -- CSIX draws other tracks' footers dark
    local footer=bm and (compact6 or bm.full_artwork) and bm:get(idxart,true)
    if not footer or footer.over[2]/footer.scale<=label_h then
      self:sprite(idxart,0,0,B+label_h,W,21)
    end
    self:rect(0,B+label_h,W,1,{255,255,255,22})
  end
  self:text(s.master and '' or ('%d'):format(s.IP_TRACKNUMBER),0,B+label_h,W-2,20,itext,'main',1)
end
-- Stereo peak meter on the theme's scale (+6 to -62 dB), with its dB marks and peak readout.
function M:meter(s,m,colors)
  local mf=m.font or 'bold';local mi=({main=1,list=2,header=3,bold=4,sends=5})[mf]
  local now=self.r.time_precise();local dt=clamp(now-self.last_time,0,.2);self.last_time=now
  local function ydb(d) return m.y+(6-clamp(d,-62,6))/68*m.h end
  local bot=colors.col_vubot or {42,102,190};local midc=colors.col_vumid or {70,185,254}
  local top=colors.col_vutop or midc;local clip=colors.col_vuclip or {255,33,69}
  local bw=(m.w-.5)/2;local lit=m.y+m.h
  if m.gap then self:rect(m.x+m.w/2-.5,m.y,1,m.h,m.gap) end -- a visible line between the two channels
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
  for d=m.first or 6,(m.labels==false) and -1 or m.last or 54,m.step or 12 do -- the theme prints bare numbers between two small ticks
    local y=ydb(-d);local label=tostring(d)
    local c=y>lit and {0,0,0,170} or armed and {255,64,0} or m.scale_color or {255,255,255,60}
    if m.scale_fade and c==m.scale_color then c={c[1],c[2],c[3],(c[4] or 255)*m.scale_fade(d)} end -- a theme that dims the scale towards the bottom
    self.g.setfont(mi);local tw=self.g.measurestr(label)/self.scale
    local cx=m.x+m.w/2
    self:text(label,m.x,y-7,m.w,14,c,mf,1)
    if m.w>=tw+9 then
      local tick={c[1],c[2],c[3],(c[4] or 255)*.5}
      self:rect(cx-tw/2-4,y-.5,2.5,1,tick);self:rect(cx+tw/2+1.5,y-.5,2.5,1,tick)
    end
  end
  local over=self.peak>1
  local text=db(self.peak)<=-150 and '-inf' or ('%.1f'):format(db(self.peak)) -- REAPER's meters bottom out at -150 dB
  local rc=m.readout_color or {100,100,100}
  local function peaktext(v) return db(v)<=-150 and '-inf' or ('%.1f'):format(db(v)) end
  local ry=m.y+(m.readout_y or 1.5)
  self.g.setfont(mi)
  local function fits(t,w) return self.g.measurestr(t)/self.scale<=w end
  local l,r_=peaktext(self.chpeak[1]),peaktext(self.chpeak[2])
  if m.readout==false then
  elseif s.master and fits(l,m.w/2-2) and fits(r_,m.w/2-2) then
    -- The master meter reads each channel's peak separately, and its loudness at the bottom.
    self:text(l,m.x,ry,m.w/2,13,self.chpeak[1]>1 and {255,183,171} or rc,mf,1)
    self:text(r_,m.x+m.w/2,ry,m.w/2,13,self.chpeak[2]>1 and {255,183,171} or rc,mf,1)
  else self:text(text,m.x,ry,m.w,13,over and {255,183,171} or rc,mf,1) end
  if s.master and m.readout~=false and s.loudness and m.h>=80 then
    local mode=math.floor(s.vumode or 0)&30
    local label=(mode==12 and 'LUFS-M' or mode>=16 and 'LUFS-S' or 'RMS')..'  '..peaktext(s.loudness)
    if fits(label,m.w-2) then
      if m.loudness_bg then self:rect(m.x,m.y+m.h-12,m.w,12,m.loudness_bg) end -- the theme's own footer under the readout
      self:text(label,m.x,m.y+m.h-(m.loudness_bg and 12.5 or 14),m.w,13,m.loudness_color or rc,mf,1)
    end
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
  if scale~=self.scale or font~=self.font or self.font_theme~=self.theme then
    self.scale,self.font,self.font_theme=scale,font,self.theme
    local own=self.theme and self.theme.fonts or {}        -- a layout may name its theme's own sizes and weights
    for i,role in ipairs({'main','list','header','bold','sends'}) do
      local f=own[role] or {FONTS[role],role=='bold'}
      g.setfont(i,f[3] or font,math.floor(f[1]*scale+.5),f[2] and 98 or 0)
    end
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
