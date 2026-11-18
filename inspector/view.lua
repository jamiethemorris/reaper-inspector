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
  if not self:sprite(name,state,x,y,w,h) then -- no usable art for this theme: a plain labelled button
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
  if self.notice and self.r.time_precise()<self.notice.until_time then status=self.notice.text end
  if status and status~='' then
    self:rect(0,0,W,16,{20,20,20,235});self:text(status,3,0,W-6,16,{233,154,104},'main',0)
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
  local base={152,152,152}
  if custom then local r,g,b=self.r.ColorFromNative(math.floor(s.color)&0xFFFFFF);base={r,g,b} end
  local panel,idx=mul(base,.8),mul(base,.75)
  local bright,dark=custom and {230,230,230} or {220,220,220},{23,23,23}
  local ptext=luma(panel)<=100 and bright or dark
  local itext=luma({idx[1]*.5+127.5,idx[2]*.5+127.5,idx[3]*.5+127.5})<=100 and bright or dark
  local ntext=custom and name_color(base) or {235,235,235}
  -- Vertical sections, bottom-anchored like a mixer strip. The theme hides the input row on short strips.
  local L=clamp(H-57,300,380)
  local inh=L>=350 and 42 or 22
  local T=H-L;local IN=T+83;local S=IN+inh;local B=H-47;local SH=B-S
  local pad=SH<250 and 2 or SH<350 and 3 or 4
  local meter=W>=STRIP
  local extra=meter and clamp((W-STRIP)/2,0,20) or 0
  local mid=math.floor((W-2)/2)
  self.layout={T=T,S=S,B=B,L=L,meter=meter}

  -- FX and send racks
  local row=self.theme and self.theme.row_height or 17
  self:rect(0,0,W,T+1,{61,61,61})
  local n=math.max(0,math.floor((T-6)/row))
  local sendrows=n>=4 and math.max(1,math.floor(n*.25+.5)) or n>=2 and 1 or 0
  -- The last send-rack row is pinned to the track's own output (master/parent send); the master has none.
  local outrow=not s.master and self.r.GetMasterTrack~=nil
  if outrow and n>=3 then sendrows=math.max(2,sendrows) end
  local fxrows=n-sendrows
  if outrow and sendrows>0 then sendrows=sendrows-1 else outrow=false end
  -- A full rack scrolls one row past its last entry, so an empty slot to add into is always reachable.
  local function overflow(count,rows) return rows>0 and count>=rows and count-rows+1 or 0 end
  self.fx_offset=clamp(self.fx_offset,0,overflow(#s.fx,fxrows))
  self.send_offset=clamp(self.send_offset,0,overflow(#s.sends,sendrows))
  -- Scrollbar in the rack's right margin, shown only while the rack is full.
  local function scrollbar(id,count,rows,offset,y)
    local over=overflow(count,rows);if over==0 then self[id]=nil;return end
    local c=col('mcp_list_scrollbar',{140,140,140});local h=rows*row-2;local total=count+1
    local th=math.max(8,h*rows/total)
    self:rect(W-3.5,y+1+(h-th)*offset/over,2.5,th,{c[1],c[2],c[3],160})
    self[id]={count=count,rows=rows}
  end
  local m=self.model
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
  scrollbar('fx_bar',#s.fx,fxrows,self.fx_offset,1)
  local sep=1+fxrows*row+.5
  if n>0 then self:rect(0,sep,W,1,{255,255,255,26}) end
  local sy=sep+3.5
  for i=1,sendrows do
    local send=s.sends[i+self.send_offset];local y=sy+(i-1)*row
    local art=not send and 'mcp_sendlist_empty' or send.kind=='midi' and 'mcp_sendlist_midihw' or send.mute and 'mcp_sendlist_mute' or 'mcp_sendlist_norm'
    local hover=inside({x=0,y=y,w=W,h=row},self.mx,self.my)
    self:sprite(art,hover and 1 or 0,-1,y,W-3,row)
    if send then
      local c=send.kind=='midi' and col('mcp_send_midihw',{70,185,254}) or send.mute and col('mcp_sends_muted',{228,94,101}) or col('mcp_sends_normal',{254,207,103})
      local knob=send.kind~='midi' and bm and bm:get('mcp_send_knob_stack')
      self:text(send.name,6,y-.5,W-14-(knob and 15 or 0),row,c,'list',0)
      if knob then
        -- One square frame per level; resized smoothly because the rack row is smaller than a frame.
        local frames=math.max(1,math.floor(knob.h/knob.w))
        local f=clamp(math.floor(self.mapping.to_position(send.volume)*(frames-1)+.5),0,frames-1)
        bm:blit(knob,knob.x,knob.y+f*knob.w,knob.w,knob.w,self:pxx(W-21),self:px(y+1.5),self:px(14),self:px(14),true)
      end
      self:hit('send'..i,0,y,W,row,function(cap)
        local shift,cmd,alt=(cap&8)~=0,(cap&4)~=0,(cap&16)~=0
        if alt and shift then m:send_slot_mute(s,send,cmd)
        elseif alt then m:send_edit(s,send,'remove')
        elseif shift then m:send_edit(s,send,'mute')
        elseif send.kind=='send' and not s.owner and self.root:output_enabled() and self.root.width>=2*STRIP then
          self.root.choice[s.guid]=send.dest -- show this send's destination in the output strip
        else self:show_routing(s) end
      end,function() self:send_menu(s,send) end)
      if not s.owner and self.root.shown_send and self.root.shown_send.index==send.index and send.kind=='send' then
        self:rect(2.5,y+2,1.5,row-4,c) -- marks the send whose destination the output strip shows
      end
    else
      self:hit('sendadd'..i,0,y,W,row,function() self:show_routing(s) end,function() self:send_menu(s) end)
    end
  end
  self.send_box={x=0,y=sy,w=W,h=sendrows*row,rows=sendrows}
  if outrow then -- set apart from the sends: its own divider, centred neutral text, never scrolls
    local y=sy+sendrows*row+2;local on=s.B_MAINSEND~=0
    self:rect(0,y-1.5,W,1,{255,255,255,40})
    local hover=inside({x=0,y=y,w=W,h=row},self.mx,self.my)
    self:sprite(on and 'mcp_fxlist_norm' or 'mcp_sendlist_mute',hover and 1 or 0,-1,y,W-2,row)
    local c=on and col('mcp_fx_normal',{216,216,216}) or col('mcp_sends_muted',{228,94,101})
    self:text(s.parent and 'Parent send' or 'Master send',7.5,y-.5,W-19.5,row,c,'list',1)
    if not s.owner and self.root.shown_main then self:rect(2.5,y+2,1.5,row-4,c) end
    self:hit('output',0,y,W,row,function() if not s.owner then self.root.choice[s.guid]=nil end end,function() self:output_menu(s) end)
  end
  scrollbar('send_bar',#s.sends,sendrows,self.send_offset,sy)

  -- FX button row, with the selected-track handle along its top edge
  self:rect(0,T+.5,W,.5,{255,255,255,26})
  self:rect(0,T+1,W,31,{51,51,51})
  local handle=mul(idx,.94)
  self:rect(0,T+1,W,4,handle);self:rect(0,T+1,W,1,{255,255,255,75});self:rect(0,T+4,W,1,{0,0,0,110})
  local fxon=s.I_FXEN~=0
  self:button('FX',#s.fx==0 and 'mcp_fx_empty' or fxon and 'mcp_fx_norm' or 'mcp_fx_dis',6,T+8,W-43,20,
    function() if #s.fx==0 then self:add_fx(s) else m:fx_chain(s) end end,function() self:fx_menu(s) end)
  self:button('I_FXEN',#s.fx==0 and 'track_fxempty_v' or fxon and 'track_fxon_v' or 'track_fxoff_v',W-37,T+8,29,20,
    function() m:toggle(s,'I_FXEN') end)

  -- Pan and input panel
  self:rect(0,T+32,W,S-T-32,panel)
  self:rect(0,T+32,W,1,{255,255,255,22});self:rect(W-1,T+33,1,S-T-33,{255,255,255,22})
  local kx,ky=mid-12,T+39
  if not self:sprite('mcp_pan_knob_large',0,kx,ky,24,24) and self.g.circle then
    self.g.set(.13,.13,.13,1);self.g.circle(self:pxx(kx+12),self:px(ky+12),self:px(11),1,1);self.g.a=1
  end
  local dual=s.I_PANMODE==6
  do -- pointer: REAPER draws the knob position itself, the art is only the cap
    local g,sc=self.g,self.scale
    local ang=clamp(s.D_PAN,-1,1)*math.pi*.75-math.pi/2
    local cx,cy=self:pxx(kx+12),self:px(ky+12)
    local dx,dy=math.cos(ang),math.sin(ang)
    g.set(178/255,178/255,178/255,1)
    local hw=sc -- half the 2 pt pointer width, in device pixels
    local x1,y1,x2,y2=cx+dx*5.5*sc,cy+dy*5.5*sc,cx+dx*10*sc,cy+dy*10*sc
    if g.triangle then
      g.triangle(x1-dy*hw,y1+dx*hw,x1+dy*hw,y1-dx*hw,x2+dy*hw,y2-dx*hw,x2-dy*hw,y2+dx*hw)
    else
      for o=-hw+.5,hw-.5 do g.line(x1-dy*o,y1+dx*o,x2-dy*o,y2+dx*o,1) end
    end
  end
  local pan=math.floor(math.abs(s.D_PAN)*100+.5)
  self:text(dual and 'dual pan' or pan==0 and 'center' or (pan..'%'..(s.D_PAN<0 and 'L' or 'R')),mid-30,T+66,60,12,ptext,'main',1)
  if not dual then local hit=self:hit('D_PAN',kx-2,ky-2,28,40);hit.kind,hit.token='D_PAN',s end
  local ry=IN
  if inh>=42 and not s.master then
    if not self:sprite('mcp_recinput',0,5,IN,W-11,16) then self:rect(5,IN,W-11,16,{28,28,28,150}) end
    self:text(self:input_label(s.I_RECINPUT),9,IN,W-30,16,{225,225,225},'main',0)
    self:hit('I_RECINPUT',5,IN,W-11,16,function() self:input_menu(s) end)
    ry=IN+20
  end
  local rm=math.floor(s.I_RECMODE)
  if not s.master then self:button('I_RECMODE',rm==2 and 'mcp_recmode_off' or (rm==0 or rm==7 or rm==8 or rm==16) and 'mcp_recmode_in' or 'mcp_recmode_out',5,ry,42,16,function()
    local items={}
    for _,mode in ipairs(RECMODES) do items[#items+1]={mode[2],function() m:set(s,'I_RECMODE',mode[1]) end,checked=rm==mode[1]} end
    self:menu(items)
  end) end

  -- Fader section: meter, volume readout, fader, button column
  local fxl=meter and 29+extra or 4          -- fader left edge
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
      local X,Wd,Y0,Y1=self:pxx(fxl),self:pxx(fxl+21)-self:pxx(fxl),self:px(ftop),self:px(fbot)
      local dt,dbm=math.floor(cap_t*k+.5),math.floor(cap_b*k+.5)
      bm:blit(bg,sx,bg.y,sw,cap_t,X,Y0,Wd,dt)
      bm:blit(bg,sx,bg.y+cap_t,sw,bg.h-cap_t-cap_b,X,Y0+dt,Wd,Y1-Y0-dt-dbm)
      bm:blit(bg,sx,bg.y+bg.h-cap_b,sw,cap_b,X,Y1-dbm,Wd,dbm)
    else self:rect(fxl+9,ftop,3,fbot-ftop,{16,16,16}) end
    -- The 43 pt cap body travels the whole fader; the art carries 4 pt of padding above it.
    local top,bottom=ftop+21.5,fbot-21.5
    local fy=bottom-self.mapping.to_position(s.D_VOL)*(bottom-top)
    if not self:sprite('mcp_volthumb',0,fxl-1,fy-25.5) then
      self:rect(fxl+1,fy-15,19,30,{150,150,150});self:rect(fxl+1,fy-15,19,1,{215,215,215});self:rect(fxl+1,fy-.5,19,1,{30,30,30})
    end
    local hit=self:hit('D_VOL',fxl-2,ftop-4,25,fbot-ftop+8)
    hit.kind,hit.token='D_VOL',s
    hit.top,hit.bottom,hit.fader_y=top,bottom,fy
    local bx=W-29;local y=S-17
    if not s.master then self:button('I_RECARM',s.I_RECARM~=0 and 'mcp_recarm_on' or 'mcp_recarm_off',W-36,y,36,24,function() m:toggle(s,'I_RECARM') end) end
    y=y+20+pad
    if not s.master then self:button('I_RECMON',s.I_RECMON==2 and 'mcp_monitor_auto' or s.I_RECMON==1 and 'mcp_monitor_on' or 'mcp_monitor_off',bx,y,21,20,function() m:toggle(s,'I_RECMON') end) end
    y=y+19+pad
    self:button('B_MUTE',s.B_MUTE~=0 and 'mcp_mute_on' or 'mcp_mute_off',bx,y,21,20,function() m:toggle(s,'B_MUTE') end)
    y=y+21+pad
    if not s.master then self:button('I_SOLO',s.I_SOLO~=0 and 'mcp_solo_on' or 'mcp_solo_off',bx,y,21,20,function() m:toggle(s,'I_SOLO') end) end
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
  self:text(s.name,2.5,B+.5,W-7,26,ntext,'header',1)
  if not s.master then self:hit('name',0,B,W,26).double=function() self:rename(s) end end
  self:rect(0,B+26,W,21,idx)
  self:sprite('mcp_idxbg_sel',0,0,B+26,W,21)
  self:rect(0,B+26,W,1,{255,255,255,22})
  self:text(s.master and '' or ('%d'):format(s.IP_TRACKNUMBER),0,B+26,W-2,20,itext,'main',1)
end
-- Stereo peak meter on the theme's scale (+6 to -62 dB), with its dB marks and peak readout.
function M:meter(s,m,colors)
  local now=self.r.time_precise();local dt=clamp(now-self.last_time,0,.2);self.last_time=now
  local function ydb(d) return m.y+(6-clamp(d,-62,6))/68*m.h end
  local bot=colors.col_vubot or {42,102,190};local midc=colors.col_vumid or {70,185,254}
  local top=colors.col_vutop or midc;local clip=colors.col_vuclip or {255,33,69}
  local bw=(m.w-.5)/2;local lit=m.y+m.h
  for c=1,2 do
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
  for d=6,54,12 do -- the theme prints bare numbers between two small ticks
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
  self:text(text,m.x,m.y+1.5,m.w,13,over and {255,183,171} or {100,100,100},'bold',1)
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
          self.model:set(tok,kind,kind=='D_VOL' and 1 or 0) -- like the mixer: double-click resets
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
    if d.kind=='D_PAN' then value=d.initial+((self.mx-d.x)-(self.my-d.y))/50*fine
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
  if scale~=self.scale then
    self.scale=scale
    for i,role in ipairs({'main','list','header','bold'}) do g.setfont(i,FONT,math.floor(FONTS[role]*scale+.5),role=='bold' and 98 or 0) end
  end
  self.width=g.w/self.scale;self.height=g.h/self.scale
  self.mx=(g.mouse_x or 0)/self.scale;self.my=(g.mouse_y or 0)/self.scale
  if self.theme and (not self.bitmaps or self.bitmaps.density~=density or self.bitmaps.theme~=self.theme) then
    if self.bitmaps then self.bitmaps:clear() end
    self.bitmaps=Bitmaps.new(g,self.theme,density)
  end
  local s=self.model:snapshot()
  if (s and s.guid)~=self.last_guid or (s and s.project)~=self.last_project then
    self.held={-150,-150};self.peak=0;self.fx_offset=0;self.send_offset=0
    self.last_guid=s and s.guid;self.last_project=s and s.project
  end
  self.snapshot=s;g.dest=-1;self:draw(s);self:input(s);g.update();return s
end
return M
