-- Offline synthetic-host tests, never a REAPER integration test.
local tests, passed = {}, 0
local function test(name, f) tests[#tests + 1] = {name, f} end
local function eq(a,b) assert(a == b, tostring(a)..' ~= '..tostring(b)) end
local root = './'
-- The installed theme the Reapertips layout was built against; these tests read its real artwork.
REAPERTIPS = os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/Reapertips Theme_Custom2.ReaperTheme'

test('theme resolves installed ui_img and reads real PNG dimensions', function()
  local Theme = dofile(root..'inspector/theme.lua')
  local t = assert(Theme.resolve(REAPERTIPS))
  eq(t.dir, os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/Reapertips Theme_Custom2')
  eq(t.row_height, 17)
  local p = assert(Theme.asset(t, 'mcp_recarm_off', 2))
  eq(p.width, 216); eq(p.height,48); eq(p.scale,2)
  assert(p.path:find('/200/',1,true))
end)

test('selected-track snapshot is read-only at startup and selection change', function()
  local h = dofile('tests/synthetic.lua').host()
  local m = dofile('inspector/model.lua').new(h)
  local s = m:snapshot()
  eq(s.name,'Synth'); eq(s.guid,'{A}');eq(#s.fx,1);eq(s.fx[1].name,'VSTi: Synth')
  eq(s.sends[1].name,'Reverb');eq(s.peaks[1],0.5);eq(s.peaks[2],0.25)
  h.selected=h.b;eq(m:snapshot().guid,'{B}')
  h.selected=nil;eq(m:snapshot(),nil)
  eq(#h.writes,0);eq(#h.undos,0)
end)

test('explicit control handlers target only owner with bounded volume and balanced undo', function()
  local h=dofile('tests/synthetic.lua').host();local Model=dofile('inspector/model.lua');local m=Model.new(h)
  local token=m:snapshot()
  for _,k in ipairs({'B_MUTE','I_SOLO','B_PHASE','I_RECARM'}) do
    assert(m:toggle(token,k));eq(h.a.values[k],1);assert(m:toggle(token,k));eq(h.a.values[k],0)
  end
  for _,expected in ipairs({1,2,0}) do assert(m:toggle(token,'I_RECMON'));eq(h.a.values.I_RECMON,expected) end
  assert(m:set(token,'D_VOL',999));assert(math.abs(h.a.values.D_VOL-10^(12/20))<1e-10)
  assert(m:set(token,'D_VOL',-1));eq(h.a.values.D_VOL,0)
  assert(m:set(token,'D_PAN',-9));eq(h.a.values.D_PAN,-1)
  assert(not m:set(token,'I_FOLDERDEPTH',1));assert(not m:set(token,'D_VOL',0/0))
  eq(h.open,0);eq(#h.undos,#h.writes)
  local writes=#h.writes
  h.selected=h.b;assert(not m:set(token,'D_VOL',1));eq(#h.writes,writes)
  h.selected=h.a;assert(not m:set(token,'D_VOL',1)) -- selection epoch was invalidated
  token=m:snapshot();h.a.valid=false;assert(not m:set(token,'D_VOL',1))
  h.a.valid=true;token=m:snapshot();h.project={};assert(not m:set(token,'D_VOL',1))
  eq(#h.writes,writes)
  h.project=token.project;token=m:snapshot();local fx=token.fx[1]
  h.fx[1].guid='{REPLACED}';assert(not m:open_fx(token,fx));eq(#h.writes,writes)
  token=m:snapshot();assert(m:open_fx(token,token.fx[1]));eq(h.writes[#h.writes][1],'fx')
  local v=Model.volume_mapping(h)
  eq(v.to_gain(0),0);assert(math.abs(v.to_gain(1)-10^(12/20))<1e-10)
  assert(math.abs(v.to_gain(v.to_position(1))-1)<1e-10)
  assert(v.to_position(0)==0 and v.to_position(1)>0 and v.to_position(1)<1)
end)

test('bitmap state cropping removes guide perimeter and selects real sprite axes', function()
  local Theme=dofile('inspector/theme.lua');local theme=assert(Theme.resolve(REAPERTIPS))
  local g={dest=-1,x=0,y=0,images={},blits={}}
  g.loadimg=function(i,p) g.images[i]=p;return i end
  g.setimgdim=function() end
  -- Synthetic guide perimeter on list sprite; installed file dimensions remain real.
  g.getpixel=function()
    local p=g.images[g.dest] or ''
    if p:find('mcp_fxlist_norm',1,true) and (g.x==0 or g.y==0) then return 1,0,1 end
    return 0.2,0.2,0.2
  end
  g.blit=function(...) g.blits[#g.blits+1]={...} end
  local b=dofile('inspector/bitmaps.lua').new(g,theme,2)
  local a=assert(b:get('mcp_fxlist_norm'))
  eq(a.x,1);eq(a.y,1);eq(a.w,72);eq(a.h,90)
  assert(b:draw('mcp_fxlist_norm',2,0,0,160,17,2))
  local bl=g.blits[#g.blits];eq(bl[4],1);assert(bl[5]>=61 and bl[5]+bl[7]<=91)
  g.blits={};assert(b:draw('mcp_mute_off',1,2,3,21,20,2))
  bl=g.blits[#g.blits];eq(bl[4],42);eq(bl[6],42);eq(bl[7],40)
  assert(b.count>=2);b:clear();eq(b.count,0)
end)

test('gfx frame uses installed bitmaps and click/drag dispatch keeps selection ownership', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Model=dofile('inspector/model.lua');local m=Model.new(h)
  local Theme=dofile('inspector/theme.lua');local th=assert(Theme.resolve(REAPERTIPS))
  local v=dofile('inspector/view.lua').new(h,g,m,th)
  v:frame();eq(v.scale,2);eq(#h.writes,0);assert(#g.blits>10);assert(v.bitmaps.count>6)
  assert(v.bitmaps.cache.mcp_idxbg_sel and v.bitmaps.cache.mcp_fxlist_empty,'footer and empty slots use the theme art')
  local function at(id,cap,dy)
    local hit=assert(v.hits[id],id);g.mouse_x=(hit.x+hit.w/2)*v.scale;g.mouse_y=(hit.y+hit.h/2+(dy or 0))*v.scale;g.mouse_cap=cap;v:frame()
  end
  at('B_MUTE',1);eq(h.a.values.B_MUTE,1);at('B_MUTE',0)
  at('fx1',1);eq(h.writes[#h.writes][1],'fx');at('fx1',0)
  at('D_VOL',1);local before=#h.writes;h.selected=h.b
  g.mouse_y=g.mouse_y-50;v:frame();eq(#h.writes,before);assert(v.drag==nil)
  g.mouse_cap=0;v:frame();at('D_PAN',1);before=#h.writes;h.b.valid=false
  g.mouse_x=g.mouse_x+40;v:frame();eq(#h.writes,before);assert(v.drag==nil)
  g.mouse_cap=0;v:frame();eq(#h.writes,before)
  h.selected=h.a;v:frame();at('D_VOL',1);before=#h.writes;h.project={};g.mouse_y=1;v:frame();eq(#h.writes,before)
  g.mouse_cap=0;h.selected=nil;v:frame();eq(#h.writes,before)
end)

test('application startup/receipt/duplicate/stop never edits projects or selects tracks', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local App=dofile('inspector/app.lua');local app=App.new(h,g)
  eq(#h.writes,0);assert(app:start());assert(g.initialized);eq(#h.writes,0);eq(#h.undos,0)
  app:frame();eq(h.ext['ReaperInspector/frame_count'],'1');eq(h.ext['ReaperInspector/current_track_guid'],'{A}')
  assert(tonumber(h.ext['ReaperInspector/assets_loaded'])>6)
  local otherg=fake.gfx();local other=App.new(h,otherg);assert(not other:start());assert(not otherg.initialized)
  assert(not app:frame());eq(h.ext['ReaperInspector/status'],'stopped');eq(h.ext['ReaperInspector/owner'],nil)
  app:stop();eq(#h.writes,0)
  local restarted=App.new(h,g);assert(restarted:start());g.key=27;assert(not restarted:frame());eq(#h.writes,0)
end)

test('entrypoint is relative-path safe and schedules without project mutation', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  _G.reaper,_G.gfx=h,g
  dofile('Reaper Inspector.lua')
  assert(g.initialized);eq(#h.writes,0);eq(#h.undos,0);assert(#h.frames>=1)
  h.exit();_G.reaper=nil;_G.gfx=nil
end)

test('pink guides fix sprite margins so the input arrow is never stretched', function()
  local fake=dofile('tests/synthetic.lua');local g=fake.gfx()
  local Theme=dofile('inspector/theme.lua');local theme=assert(Theme.resolve(REAPERTIPS))
  local size=assert(Theme.asset(theme,'mcp_recinput',2))
  -- Synthetic perimeter shaped like the installed art: 3 px left margin, 27 px right and bottom.
  g.getpixel=function()
    local w,h=size.width,size.height
    if (g.y==0 and g.x<4) or (g.y==h-1 and g.x>=w-28) or (g.x==w-1 and g.y>=h-28) then return 1,0,1 end
    return .2,.2,.2
  end
  local b=dofile('inspector/bitmaps.lua').new(g,theme,2)
  local a=assert(b:get('mcp_recinput'))
  eq(a.margin[1],3);eq(a.margin[2],0);eq(a.margin[3],27);eq(a.margin[4],27)
  assert(b:draw('mcp_recinput',0,5,100,111,16,2));eq(#g.blits,3)
  local left,mid,right=g.blits[1],g.blits[2],g.blits[3]
  eq(left[6],3);eq(left[10],3);eq(right[6],27);eq(right[10],27) -- caps stay 1:1
  eq(left[8],10);eq(right[8]+right[10],232);eq(mid[10],222-30);eq(g.mode,4)
  for _,bl in ipairs(g.blits) do eq(bl[7],bl[11]) end -- nothing is scaled vertically
end)

test('yellow overhang then pink margin: number footer art keeps its cap and is never stretched', function()
  local fake=dofile('tests/synthetic.lua');local g=fake.gfx()
  local Theme=dofile('inspector/theme.lua');local theme=assert(Theme.resolve(REAPERTIPS))
  local size=assert(Theme.asset(theme,'mcp_idxbg_sel',2))
  g.getpixel=function()
    local w,h=size.width,size.height
    if g.x==0 and g.y<9 then return 1,1,0 end
    if g.x==0 and g.y<49 then return 1,0,1 end
    if g.y==0 and g.x<3 then return 1,0,1 end
    if g.x==w-1 and g.y==h-1 then return 1,1,0 end
    if (g.y==h-1 and g.x>=w-3) or (g.x==w-1 and g.y>=h-3) then return 1,0,1 end
    return .2,.2,.2
  end
  local b=dofile('inspector/bitmaps.lua').new(g,theme,2)
  local a=assert(b:get('mcp_idxbg_sel'))
  eq(a.over[2],8);eq(a.margin[2],40);eq(a.margin[4],2);eq(a.margin[1],2);eq(a.margin[3],2)
  assert(b:draw('mcp_idxbg_sel',0,0,100,86,21,2))
  local top=g.blits[1];eq(top[9],200-8) -- overhang sits above the control rectangle
  for _,bl in ipairs(g.blits) do eq(bl[7],bl[11]) end
end)

test('mixer-style FX names drop the type prefix and vendor but keep user renames', function()
  local label=dofile('inspector/model.lua').fx_label
  eq(label('VST3i: Kontakt 8 (Native Instruments)'),'Kontakt 8')
  eq(label('VSTi: Kontakt 8 (Native Instruments) (64 out)'),'Kontakt 8')
  eq(label('JS: Volume Adjustment'),'Volume Adjustment');eq(label('CLAP: Vital (Matt Tytel)'),'Vital')
  eq(label('My chain (wide)'),'My chain (wide)');eq(label('VST: (odd)'),'(odd)')
end)

test('uncoloured track uses the theme grey panel, coloured track its own colour', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  local function has(r,gr,b)
    for _,c in ipairs(g.calls) do
      if c[1]=='set' and math.abs(c[2]*255-r)<.6 and math.abs(c[3]*255-gr)<.6 and math.abs(c[4]*255-b)<.6 then return true end
    end
  end
  v:frame();assert(has(121.6,121.6,121.6),'neutral selected panel');assert(not has(190,164,43),'no invented mustard')
  g.calls={};h.GetTrackColor=function() return 0x1000000|1 end
  v:frame();assert(has(204*.8,179*.8,49*.8),'track colour dimmed by the theme amount')
end)

test('slot clicks and menus act only on the verified FX; empty slots open the chain', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  v:frame()
  local function press(id,cap)
    local hit=assert(v.hits[id],id);g.mouse_x=(hit.x+hit.w/2)*v.scale;g.mouse_y=(hit.y+hit.h/2)*v.scale
    g.mouse_cap=cap;v:frame();g.mouse_cap=0;v:frame()
  end
  local drawn=false
  for _,c in ipairs(g.calls) do if c[1]=='drawstr' and c[2]=='Synth' then drawn=true end end
  assert(drawn,'short FX name drawn')
  press('fx1',1);eq(h.writes[#h.writes][4],3)                       -- open floating window
  h.floating={};press('fx1',1);eq(h.writes[#h.writes][4],2);h.floating=nil -- click again hides it
  press('fx1',1|8);eq(h.fx[1].enabled,false);eq(h.open,0)             -- shift-click bypass, undo closed
  local at_x,at_y;local show=g.showmenu;g.showmenu=function(str) at_x,at_y=g.x,g.y;return show(str) end
  local function pick(label) -- position of a selectable entry in the last menu string
    local n=0
    for part in (g.menus[#g.menus]..'|'):gmatch('([^|]*)|') do
      if part~='' and part:sub(1,1)~='>' then n=n+1;if part:gsub('^[<!#]+','')==label then return n end end
    end
    error('no menu entry '..label)
  end
  g.menu=0;press('fx1',2);local str=g.menus[#g.menus]
  assert(str:find('Add FX...|',1,true)==1 and str:find('!Bypass FX',1,true) and str:find('#Paste FX',1,true) and str:find('Bypass FX slot for all tracks',1,true))
  assert(str:find('#Run FX in parallel with previous FX',1,true),'first slot has no previous FX')
  g.menu=pick('Bypass FX');press('fx1',2);eq(h.fx[1].enabled,true)   -- right-click menu: Bypass FX
  eq(at_x,g.mouse_x);eq(at_y,g.mouse_y)                              -- menu opens at the pointer
  local w=#h.writes;h.touched=h.a
  press('fxadd2',1);eq(#h.writes,w);eq(#h.commands,1);eq(h.commands[1],40271) -- Add FX browser only, no chain
  h.GetToggleCommandStateEx=function() return 1 end
  press('fxadd2',1);eq(#h.commands,3);eq(#h.writes,w)                       -- already open: close, reopen
  h.touched=h.b;press('fxadd2',1);eq(#h.commands,3);eq(h.writes[#h.writes][4],1);assert(v.notice) -- other track touched: chain
  press('FX',1);eq(h.writes[#h.writes][4],1)
  press('I_FXEN',1);eq(h.a.values.I_FXEN,0)
  -- copy, then paste after the slot; cut clears the clipboard once moved
  g.menu=pick('Copy FX');press('fx1',2);g.menu=0;press('fx1',2);g.menu=pick('Paste FX');press('fx1',2)
  local c=h.writes[#h.writes];eq(c[1],'fxcopy');eq(c[3],0);eq(c[5],1);eq(c[6],false);assert(v.model.clip)
  assert(v.model:fx_copy(v.snapshot,v.snapshot.fx[1],true));assert(v.model:fx_paste(v.snapshot,0));eq(h.writes[#h.writes][6],true);eq(v.model.clip,nil)
  h.GetUserInputs=function() return true,'Lead, wide' end
  g.menu=pick('Rename FX instance');press('fx1',2);eq(h.fx[1].renamed_name,'Lead, wide')
  g.menu=pick('Add container');press('fx1',2);eq(h.fx[2].name,'Container')
  g.menu=0;v:frame();press('fx2',2);g.menu=pick('Run FX in parallel with previous FX');press('fx2',2);eq(h.fx[2].parallel,'1')
  g.menu=pick('Bypass FX slot for all tracks');press('fx1',2);eq(h.fx[1].enabled,false);eq(h.open,0)
  press('fx1',1|4);eq(h.writes[#h.writes][4],1)                       -- cmd-click: FX chain
  press('fx1',1|4|8);eq(h.fx[1].offline,true)                         -- shift+cmd-click: offline
  local s=v.snapshot;local stale=s.fx[1];h.fx[1].guid='{OTHER}'
  local before=#h.writes;assert(not v.model:fx_edit(s,stale,'delete'));eq(#h.writes,before)
  g.menu=0
end)

test('send, routing, automation and input controls stay scoped to the inspected track', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua');local Model=dofile('inspector/model.lua');local m=Model.new(h)
  local v=dofile('inspector/view.lua').new(h,g,m,assert(Theme.resolve(REAPERTIPS)))
  v:frame();local s=v.snapshot;local send=s.sends[1]
  eq(send.kind,'send');eq(send.name,'Reverb')
  assert(m:send_edit(s,send,'mute'));eq(h.send.mute,1)
  h.send.dest={};local before=#h.writes
  assert(not m:send_edit(s,send,'remove'),'send that moved is refused');eq(#h.writes,before)
  h.send.dest=h.b;h.send.mute=0;s=m:snapshot();send=s.sends[1]
  assert(m:send_slot_mute(s,send,true));eq(h.send.mute,1)
  assert(m:goto_send_dest(s,send));eq(h.selected,h.b);eq(h.commands[#h.commands],40913);h.commands=nil
  h.selected=h.a;s=m:snapshot();send=s.sends[1]
  assert(m:send_edit(s,send,'remove'));eq(h.send.present,false)
  assert(not m:add_send(s,h.a),'no send to itself');assert(m:add_send(s,h.b))
  local targets=m:send_targets(s);eq(#targets,1);eq(targets[1].track,h.b)
  h.touched=h.b;local ok,why=m:routing(s);assert(not ok and why=='touch');eq(h.commands,nil)
  h.touched=h.a;assert(m:routing(s));eq(h.commands[1],40293)
  assert(m:set(s,'I_AUTOMODE',3));eq(h.a.values.I_AUTOMODE,3);assert(m:set(s,'I_AUTOMODE',99));eq(h.a.values.I_AUTOMODE,5)
  assert(m:set(s,'I_RECINPUT',4096+(63<<5)));eq(h.a.values.I_RECINPUT,6112)
  eq(v:input_label(6112),'MIDI: All: All channels');eq(v:input_label(-1),'None');eq(v:input_label(1024),'Input 1 / Input 2')
  eq(h.open,0);h.selected=h.b;assert(not m:add_send(s,h.b));assert(not m:set(s,'I_AUTOMODE',0))
end)

test('a full rack shows a scrollbar and scrolls one row past the end to an empty slot', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  g.ext_retina=2;g.w=244;g.h=1400;v:frame()
  local rows=v.fx_box.rows;assert(rows>=3)
  eq(v.fx_bar,nil);eq(v.send_bar,nil)                         -- one FX, one send: nothing to scroll
  for i=2,rows-1 do h.fx[i]={name='FX '..i,guid='{FX'..i..'}',enabled=true} end
  v:frame();eq(v.fx_bar,nil);assert(v.hits['fxadd'..rows])     -- one free slot left: still no bar
  h.fx[rows]={name='FX '..rows,guid='{FX'..rows..'}',enabled=true}
  v:frame();assert(v.fx_bar,'full rack shows its scrollbar');eq(v.hits['fxadd'..rows],nil)
  g.mouse_x=20;g.mouse_y=40
  g.mouse_wheel=-120;v:frame();eq(v.fx_offset,1);v:frame();assert(v.hits['fxadd'..rows],'empty slot reachable')
  g.mouse_wheel=-120;v:frame();v:frame();eq(v.fx_offset,1)     -- and no further (clamped on the next draw)
  -- empty send slot: left-click opens routing, right-click opens the menu
  local hit=assert(v.hits.sendadd2);g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;h.touched=h.a;local menus=#(g.menus or {})
  g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame();eq(h.commands[#h.commands],40293);eq(#(g.menus or {}),menus)
  g.mouse_cap=2;v:frame();g.mouse_cap=0;v:frame();eq(#g.menus,menus+1)
  eq(#h.writes,0)
end)

test('output strip: master by default, clicked send destination, parent folder, fully editable, scoped', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua');local Model=dofile('inspector/model.lua');local m=Model.new(h)
  local set_calls={}
  local v=dofile('inspector/view.lua').new(h,g,m,assert(Theme.resolve(REAPERTIPS)),{set_output=function(on) set_calls[#set_calls+1]=on end})
  local function size(w) g.ext_retina=2;g.w=w*2;g.h=1400;v:frame() end
  local function press(id,cap)
    local hit=assert(v.hits[id],id);g.mouse_x=(hit.x+hit.w/2)*v.scale;g.mouse_y=(hit.y+hit.h/2)*v.scale
    g.mouse_cap=cap;v:frame();g.mouse_cap=0;v:frame()
  end
  size(171);eq(v.out_snapshot,nil);assert(v.hits.output,'output row exists even without room for the strip')
  h.touched=h.a;press('send1',1);eq(h.commands[#h.commands],40293);eq(v.choice['{A}'],nil) -- too narrow: routing as before
  size(180);local o=assert(v.out_snapshot);eq(o.track,h.master);assert(o.master);eq(v.shown_main,true)
  assert(v.hits['out:D_VOL'] and v.hits['out:B_MUTE'] and v.hits['out:FX'] and v.hits['out:fx1'])
  for _,id in ipairs({'out:I_RECARM','out:I_RECMON','out:I_SOLO','out:I_RECINPUT','out:I_RECMODE','out:output'}) do eq(v.hits[id],nil) end
  assert(v.hits.D_VOL.x+v.hits.D_VOL.w<=90 and v.hits['out:D_VOL'].x>=90,'strips sit side by side')
  press('out:B_MUTE',1);eq(h.master.values.B_MUTE,1);eq(h.a.values.B_MUTE,0)
  local hit=v.hits['out:D_VOL'];g.mouse_x=(hit.x+hit.w/2)*2;g.mouse_y=hit.fader_y*2;g.mouse_cap=1;v:frame()
  g.mouse_y=g.mouse_y+60;v:frame();g.mouse_cap=0;v:frame()
  assert(h.master.values.D_VOL<1,'output fader moves the output track');eq(h.a.values.D_VOL,1)
  local commands=#h.commands
  press('send1',1);eq(#h.commands,commands);eq(v.out_snapshot.track,h.b);eq(v.shown_send.index,0) -- send click switches the strip
  press('out:B_MUTE',1);eq(h.b.values.B_MUTE,1)
  press('output',1);eq(v.out_snapshot.track,h.master)                                         -- output row switches back
  h.a.values.I_MIDIHWOUT=0;h.GetMIDIOutputName=function() return true,'MIDI Interface' end;v:frame()
  eq(v.snapshot.sends[1].kind,'midi');press('send1',1);eq(h.commands[#h.commands],40293);eq(v.out_snapshot.track,h.master)
  h.a.values.I_MIDIHWOUT=-1;v:frame()
  h.a.parent=h.b;v:frame();eq(v.out_snapshot.track,h.b)                                        -- folder child: parent send
  local label=false
  for _,c in ipairs(g.calls) do if c[1]=='drawstr' and c[2]=='Parent send' then label=true end end
  assert(label);h.a.parent=nil;v:frame()
  g.menu=1;press('output',2);eq(h.a.values.B_MAINSEND,0);assert(g.menus[#g.menus]:find('!Master send',1,true))
  g.menu=2;press('output',2);eq(set_calls[1],false);g.menu=0
  -- the output token dies with its owner or its track
  local token=v.out_snapshot;assert(m:set(token,'D_PAN',.2))
  h.master.valid=false;assert(not m:set(token,'D_PAN',.4));h.master.valid=true
  h.selected=h.b;assert(not m:set(token,'D_PAN',.4));eq(h.master.values.D_PAN,.2)
  h.selected=h.a;v.options.output_strip=false;v:frame();eq(v.out_snapshot,nil);eq(v.hits['out:D_VOL'],nil)
  eq(h.open,0)
end)

test('output strip toggle lives in the Inspector menu and is remembered', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local app=dofile('inspector/app.lua').new(h,g);assert(app:start())
  eq(app.view.options.output_strip,true)
  g.menu=2;app:menu();eq(app.view.options.output_strip,false);eq(h.ext['ReaperInspector/output_strip'],'0')
  assert(g.menus[#g.menus]:find('!Show output strip',1,true))
  app:stop();local again=dofile('inspector/app.lua').new(h,g);assert(again:start());eq(again.view.options.output_strip,false)
  again:menu();eq(again.view.options.output_strip,true);again:stop();eq(#h.writes,0)
end)

test('double-clicking a track name renames that strip; the master has no rename', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  g.ext_retina=2;g.w=360;g.h=1400;v:frame()
  local asked,reply=0,nil
  h.GetUserInputs=function(_,_,_,current) asked=asked+1;eq(current,h.a.name);return reply~=nil,reply end
  local function click(id)
    local hit=assert(v.hits[id],id);g.mouse_x=(hit.x+hit.w/2)*2;g.mouse_y=(hit.y+hit.h/2)*2
    g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  end
  click('name');eq(asked,0)                                  -- a single click does nothing
  reply='Lead, wide';click('name');eq(asked,1);eq(h.a.name,'Lead, wide');eq(h.open,0)
  local writes=#h.writes
  click('name');reply=nil;click('name');eq(asked,2);eq(#h.writes,writes)   -- cancelled: no edit
  reply='Lead, wide';click('name');click('name');eq(#h.writes,writes)      -- unchanged: no undo point
  eq(v.out_snapshot.track,h.master);eq(v.hits['out:name'],nil)
end)

test('the Inspector follows the theme REAPER is using until one is chosen by hand', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local App=dofile('inspector/app.lua')
  local zip='tests/fixtures/Zipped theme.ReaperThemeZip'
  local app=App.new(h,g);assert(app:start());eq(app.following,true);eq(app.theme_path,REAPERTIPS);eq(app.theme.layout,'reapertips')
  h.theme_file=zip
  for _=1,31 do app:frame() end                                   -- REAPER switched theme: picked up within a second
  eq(app.theme_path,zip);eq(app.theme.layout,'generic');eq(app.view.theme,app.theme)
  h.theme_file='/nonexistent/Missing.ReaperTheme'
  for _=1,31 do app:frame() end;assert(app.view.options.status~='','an unreadable theme reports an error')
  eq(app.theme_path,zip)                                          -- and keeps the last good one
  assert(app:load_path(REAPERTIPS));eq(app.following,false);eq(h.ext['ReaperInspector/theme_choice'],REAPERTIPS)
  h.theme_file=zip;for _=1,31 do app:frame() end;eq(app.theme_path,REAPERTIPS)   -- a hand-picked theme stays
  app:stop();app=App.new(h,g);assert(app:start());eq(app.following,false);eq(app.theme_path,REAPERTIPS)
  g.menu=4;app:menu();eq(app.following,true);eq(app.theme_path,zip);eq(h.ext['ReaperInspector/theme_choice'],'')
  assert(g.menus[#g.menus]:find("Follow REAPER's theme",1,true))
  app:stop()
  h.ext['ReaperInspector/theme']='/old/0.3/value.ReaperTheme'     -- the pre-0.4 key is ignored
  h.theme_file=REAPERTIPS;app=App.new(h,g);assert(app:start());eq(app.following,true);eq(app.theme_path,REAPERTIPS);app:stop()
  eq(#h.writes,0)
end)

test('theme archives: read in place, only requested images copied to the cache, checksums enforced', function()
  local Theme=dofile('inspector/theme.lua');local Unzip=dofile('inspector/unzip.lua')
  local fake=dofile('tests/synthetic.lua');local h=fake.host()
  local env={cache=h.cache..'/zip',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  os.execute('rm -rf "'..env.cache..'"')
  local zip='tests/fixtures/Zipped theme.ReaperThemeZip'
  local before=assert(io.open(zip,'rb')):read('a')
  local t=assert(Theme.resolve(zip,env))
  eq(t.row_height,21);eq(t.layout,'generic');eq(t.colors.mcp_fx_normal[1],1);eq(t.colors.mcp_fx_normal[3],3)
  assert(t.dir:find(env.cache,1,true)==1 and t.dir:find('Zipped theme%-%x%x%x%x%x%x%x%x$'))
  local a=assert(Theme.asset(t,'mcp_stored',2));eq(a.width,6);eq(a.height,4);eq(a.scale,2)
  local d=assert(Theme.asset(t,'mcp_deflated',2));eq(d.width,40);eq(d.height,30);eq(d.scale,1)   -- only a 100% copy exists
  eq(Theme.asset(t,'mcp_absent',2),nil)
  eq(assert(io.open(a.path,'rb')):read('a'),assert(Unzip.read(t.zip,'Zipped_unpacked/200/mcp_stored.png')))
  eq(Theme.asset(t,'mcp_stored',2).path,a.path)                                                -- second use reads the cached copy
  -- a .ReaperTheme that points at the archive supplies colour overrides
  local side=assert(Theme.resolve('tests/fixtures/Zipped theme.ReaperTheme',env))
  eq(side.colors.mcp_fx_normal[1],9);eq(side.colors.mcp_sends_normal[1],4);eq(side.dir,t.dir)
  local _,err=Theme.resolve(zip);assert(err:find('cache'))
  -- damage is reported, never drawn
  local bad=env.cache..'/bad.ReaperThemeZip';local at=before:find('IDAT',1,true)
  local f=assert(io.open(bad,'wb'));f:write(before:sub(1,at+5)..string.char((before:byte(at+6)+1)%256)..before:sub(at+7));f:close()
  local z=assert(Unzip.open(bad));local data,why=Unzip.read(z,'Zipped_unpacked/200/mcp_stored.png');eq(data,nil);assert(why:find('checksum'))
  eq(Unzip.open('README.md'),nil)
  eq(assert(io.open(zip,'rb')):read('a'),before)
end)

test('an unrecognised theme lends only its list cells; every control is still drawn and clickable', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local theme=assert(Theme.resolve(REAPERTIPS));theme.layout='generic'   -- same art, treated as a stranger
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme)
  g.ext_retina=2;g.w=244;g.h=1400;v:frame()
  local loaded={}
  for _,p in pairs(g.images) do loaded[#loaded+1]=p:match('([^/]+)%.png$') end
  assert(#loaded>0);for _,n in ipairs(loaded) do assert(n:find('^mcp_fxlist_') or n:find('^mcp_sendlist_'),n) end
  eq(#v.bitmaps.missing,0)
  local text={};for _,c in ipairs(g.calls) do if c[1]=='drawstr' then text[c[2]]=true end end
  for _,label in ipairs({'M','S','rec','FX','I/O','trim'}) do assert(text[label],label) end
  for _,id in ipairs({'B_MUTE','I_SOLO','I_RECARM','I_RECMON','FX','I_FXEN','D_VOL','D_PAN','I_AUTOMODE','fx1','output'}) do assert(v.hits[id],id) end
  local hit=v.hits.B_MUTE;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.a.values.B_MUTE,1);eq(h.open,0)
end)

test('narrow panels drop the meter before controls can collide; double-click resets the fader', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  for _,width in ipairs({66,74,86,122,200}) do
    g.ext_retina=2;g.w=width*2;g.h=1400;v:frame()
    eq(v.layout.meter,width>=86);eq(v.hits.meter~=nil,width>=86)
    local f,b=v.hits.D_VOL,v.hits.B_MUTE
    assert(f.x>=0 and f.x+f.w<=b.x,'fader collides with buttons at '..width)
    if v.hits.meter then assert(v.hits.meter.x+v.hits.meter.w<=f.x+2,'meter collides with fader at '..width) end
  end
  h.a.values.D_VOL=.25;v:frame()
  local hit=v.hits.D_VOL;g.mouse_x=(hit.x+hit.w/2)*2;g.mouse_y=(hit.top+5)*2
  g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame();local moved=h.a.values.D_VOL
  g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame();eq(h.a.values.D_VOL,1);assert(moved~=1)
end)

test('dual-pan track refuses unsupported pan write at model boundary', function()
  local h=dofile('tests/synthetic.lua').host();h.a.values.I_PANMODE=6
  local m=dofile('inspector/model.lua').new(h);local token=m:snapshot()
  assert(not m:set(token,'D_PAN',.8));eq(#h.writes,0)
end)

test('theme paths are literal data including spaces/apostrophes and invalid load retains current theme', function()
  local Theme=dofile('inspector/theme.lua')
  local theme=assert(Theme.resolve('tests/fixtures/Quoted theme.ReaperTheme'))
  eq(theme.dir,"tests/fixtures/theme's [safe] assets");eq(theme.row_height,19)
  eq(assert(Theme.resolve('"tests/fixtures/theme\'s [safe] assets/"')).dir,theme.dir)
  assert(not Theme.resolve('tests/fixtures/missing.ReaperTheme'))
  assert(not Theme.resolve('bad\npath'));assert(not Theme.resolve('bad\0path'))
  assert(not Theme.resolve("x'; os.execute('false'); --"))
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local app=dofile('inspector/app.lua').new(h,g);assert(app:start());local before=app.theme
  assert(not app:load_path('/not/a/theme'));eq(app.theme,before)
  g.menu=2;h.GetUserInputs=function() return true,"tests/fixtures/theme's [safe] assets" end
  app:choose_theme();eq(app.theme.dir,theme.dir);eq(h.ext['ReaperInspector/theme_choice'],theme.dir)
  g.menu=1;app:menu();eq(g.dockstate&1,1);app:menu();eq(g.dockstate&1,0)
  eq(#h.writes,0);app:stop()
end)

test('native volume mapping roundtrips zero/unity/maximum with exact bounds', function()
  local Model=dofile('inspector/model.lua')
  local r={DB2SLIDER=function(d) return d+150 end,SLIDER2DB=function(s) return s-150 end}
  local v=Model.volume_mapping(r);assert(v.native);eq(v.to_gain(-1),0)
  eq(v.to_position(0),0);eq(v.to_position(999),1)
  for _,gain in ipairs({.0001,.1,1,10^(12/20)}) do assert(math.abs(v.to_gain(v.to_position(gain))-gain)<1e-9) end
  assert(math.abs(v.to_gain(10)-10^(12/20))<1e-9)
end)

test('draw frame supports retina, nonretina, short viewport and read-only list scrolling', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  for i=2,30 do h.fx[i]={name='FX '..i,guid='{FX'..i..'}',enabled=true} end
  local theme=assert(dofile('inspector/theme.lua').resolve(REAPERTIPS))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme)
  for _,size in ipairs({{170,700,2},{128,430,1},{240,900,1.5}}) do
    g.ext_retina=size[3];g.w=size[1]*size[3];g.h=size[2]*size[3];v:frame()
    eq(v.width,size[1]);eq(v.height,size[2]);assert(v.hits.D_VOL);assert(v.hits.D_PAN)
  end
  g.mouse_x=10*v.scale;g.mouse_y=50*v.scale;g.mouse_wheel=-120;v:frame();eq(v.fx_offset,1);eq(g.mouse_wheel,0)
  h.GetOS=function() return 'Win64' end;g.ext_retina=2;g.w=170;g.h=700;v:frame();eq(v.scale,1);eq(v.width,170)
  eq(#h.writes,0)
end)

test('setter exceptions close undo blocks and held mouse at startup does not click', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local m=dofile('inspector/model.lua').new(h);h.SetMediaTrackInfo_Value=function() error('synthetic failure') end
  assert(not m:set(m:snapshot(),'D_VOL',.5));eq(h.open,0)
  g.mouse_cap=1;g.mouse_x=260;g.mouse_y=830
  local theme=assert(dofile('inspector/theme.lua').resolve(REAPERTIPS))
  local v=dofile('inspector/view.lua').new(h,g,m,theme);v:frame();eq(#h.writes,0);assert(not v.drag)
end)

test('modified send sprites use integral rows and clamp last state within guide crop', function()
  local fake=dofile('tests/synthetic.lua');local g=fake.gfx()
  g.getpixel=function() return g.x==0 and 1 or .2,0,g.x==0 and 1 or .2 end
  local Theme=dofile('inspector/theme.lua');local b=dofile('inspector/bitmaps.lua').new(g,assert(Theme.resolve(REAPERTIPS)),2)
  for state=0,2 do b:draw('mcp_sendlist_norm',state,0,0,160,17,2) end
  eq(g.blits[1][5],1);eq(g.blits[1][7],32)
  eq(g.blits[2][5],33);eq(g.blits[2][7],32)
  eq(g.blits[3][5],65);eq(g.blits[3][7],30)
end)

test('production UI handlers with synthetic clicks cover all controls and fader endpoints', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Model=dofile('inspector/model.lua');local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,Model.new(h),assert(Theme.resolve(REAPERTIPS)));v:frame()
  local function point(id,cap)
    local hit=assert(v.hits[id]);g.mouse_x=(hit.x+hit.w/2)*v.scale;g.mouse_y=(hit.y+hit.h/2)*v.scale;g.mouse_cap=cap;v:frame()
  end
  for _,id in ipairs({'I_RECARM','I_RECMON','B_MUTE','I_SOLO','B_PHASE'}) do
    point(id,1);eq(h.a.values[id],1);point(id,0)
  end
  point('D_VOL',1);local hit=v.hits.D_VOL
  -- Keep the original captured thumb offset when hitting absolute endpoints.
  local offset=v.drag.offset
  g.mouse_y=(hit.top+offset)*v.scale;v:frame();assert(math.abs(h.a.values.D_VOL-10^(12/20))<1e-8)
  g.mouse_y=(hit.bottom+offset)*v.scale;v:frame();eq(h.a.values.D_VOL,0)
  g.mouse_cap=0;v:frame();point('D_PAN',1);g.mouse_x=g.mouse_x+30;v:frame();assert(h.a.values.D_PAN>0)
  g.mouse_cap=0;v:frame();eq(h.b.values.D_VOL,1);eq(h.b.values.D_PAN,0)
end)

test('native track repaint is requested only after successful explicit changes', function()
  local fake=dofile('tests/synthetic.lua');local h=fake.host()
  local m=dofile('inspector/model.lua').new(h);local t=m:snapshot();eq(h.refresh,nil)
  assert(m:toggle(t,'B_MUTE'));eq(h.refresh,1);eq(h.arrange,1)
  assert(m:set(t,'B_MUTE',1));eq(h.refresh,1) -- unchanged values are no-ops
end)

test('Apple Silicon macOS uses Retina framebuffer and native-sized controls', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  g.ext_retina=2;g.w=414;g.h=1810
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  v:frame();eq(v.scale,2);eq(v.width,207);eq(v.height,905)
  eq(v.hits.B_MUTE.w*v.scale,42)
  eq(#h.writes,0)
end)

test('tall docks give surplus height to lists, not an elongated fader', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(REAPERTIPS)))
  local previous_rows=0
  for _,height in ipairs({700,905,1200}) do
    g.ext_retina=2;g.w=414;g.h=height*2;v:frame()
    local travel=v.hits.D_VOL.bottom-v.hits.D_VOL.top
    assert(travel>=120 and travel<=190,'fader travel stretched: '..travel)
    local lower=v.layout.L;eq(height-v.layout.T,lower)
    assert(lower>=300 and lower<=380,'lower strip not bounded: '..lower)
    assert(v.fx_box.rows>previous_rows,'extra dock height must grow FX rack')
    previous_rows=v.fx_box.rows
    assert(v.hits.B_PHASE,'phase control retained')
  end
  eq(#h.writes,0)
end)

for _, t in ipairs(tests) do
  local ok, err = xpcall(t[2], debug.traceback)
  if ok then passed = passed + 1; print('PASS '..t[1]) else print('FAIL '..t[1]..'\n'..err) end
end
print(('%d/%d offline tests passed'):format(passed,#tests))
os.exit(passed == #tests and 0 or 1)
