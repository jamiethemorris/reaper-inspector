-- Offline synthetic-host tests, never a REAPER integration test.
local tests, passed = {}, 0
local function test(name, f) tests[#tests + 1] = {name, f} end
local function eq(a,b) assert(a == b, tostring(a)..' ~= '..tostring(b)) end
local root = './'
-- The installed theme the Reapertips layout was built against; these tests read its real artwork.
REAPERTIPS = os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/Reapertips Theme_Custom2.ReaperTheme'
-- The tests' stand-in for "any theme without a layout of its own": Flat Madness unpacked with one rectangle of its mixer script
-- changed, so it is read as generic (own artwork, Inspector arrangement).
local function flat_generic(h)
  local dir=h.cache..'/flat-generic'
  local f=io.open(dir..'/rtconfig.txt','rb')
  if not f then
    local zip=h.GetResourcePath()..'/ColorThemes/Flat Madness CI 5.1.0 Dark.ReaperThemeZip'
    assert(os.execute('mkdir -p "'..dir..'-x" "'..dir..'" && unzip -q -o "'..zip..'" "FM*" -d "'..dir..'-x" && cp -R "'..dir..'-x"/FM*/. "'..dir..'/"'))
    f=assert(io.open(dir..'/rtconfig.txt','rb'));local cfg=f:read('a');f:close()
    local changed,n=cfg:gsub('%[7 102 22 20%]','[7 102 22 21]');assert(n==1)
    f=assert(io.open(dir..'/rtconfig.txt','wb'));f:write(changed)
  end
  f:close();return dir
end

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
  eq(v.hits['out:sendadd1'],nil);eq(v.hits['out:send1'],nil);eq(v.out.send_box.rows,0) -- the master strip shows inserts only
  eq(o.loudness,h.Track_GetPeakInfo(h.master,1024));eq(o.mono,false);eq(v.snapshot.loudness,nil)
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

test('experimental artwork menu can preview and restore generic artwork without changing layout', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local App=dofile('inspector/app.lua')
  h.theme_file=flat_generic(h)
  local app=App.new(h,g);assert(app:start());app:frame()
  local v=app.view;eq(v.theme.layout,'generic')
  assert(not v.bitmaps.cache.mcp_volthumb)
  local old=v.hits.D_VOL
  g.menu=5;v.drag={};app:menu();eq(v.drag,nil);app:frame()
  eq(v.theme.layout,'generic');assert(v.bitmaps.cache.mcp_volthumb)
  for _,k in ipairs({'x','y','w','h'}) do eq(v.hits.D_VOL[k],old[k]) end
  app:menu();assert(g.menus[#g.menus]:find('!Try full theme artwork',1,true));app:frame()
  assert(not v.bitmaps.cache.mcp_volthumb)
  app:menu();app:stop();local again=App.new(h,g);assert(again:start());again:frame()
  assert(not again.view.bitmaps.cache.mcp_volthumb);again:stop();eq(#h.writes,0)
  -- CSIX-BASIC is recognised by its mixer script: generic arrangement, own artwork, no switch needed.
  -- Its pan knob face is a stack of frames, drawn instead of a generated line.
  h.theme_file=h.GetResourcePath()..'/ColorThemes/CSIX-BASIC.ReaperThemeZip'
  local csix=App.new(h,g);assert(csix:start())
  local pointers=0;csix.view.pointer=function() pointers=pointers+1 end
  g.blits={};csix:frame()
  eq(csix.view.theme.layout,'generic');assert(csix.view.theme.full_art);eq(csix.view.options.full_theme_artwork,nil)
  eq(pointers,0);assert(csix.view.bitmaps.cache.mcp_volthumb)
  local stack=assert(csix.view.bitmaps.cache.mcp_pan_knob_stack);local drawn
  for _,b in ipairs(g.blits) do if b[1]==stack.slot then eq(b[6],stack.w);eq(b[7],stack.w);eq(b[10],24);eq(b[11],24);eq(b[5],30*stack.w);drawn=true end end
  assert(drawn)
  local Theme=dofile('inspector/theme.lua')
  local env={cache=h.cache..'/csix',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local changed,n=csix.view.theme.rtconfig:gsub('%[5 8 37 20%]','[5 8 39 20]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'"')
  local f=assert(io.open(env.cache..'/rtconfig.txt','w'));f:write(changed);f:close()
  local other=assert(Theme.resolve(env.cache,env));eq(other.layout,'generic');assert(not other.full_art)
  csix:stop();eq(#h.writes,0)
end)

test('CSIX strips read their edition\'s text colours and match the mixer at the record tab, readout and footer', function()
  local fake=dofile('tests/synthetic.lua')
  local App,Theme=dofile('inspector/app.lua'),dofile('inspector/theme.lua')
  local function open(file)
    local h,g=fake.host(),fake.gfx();h.theme_file=file:find('^/') and file or h.GetResourcePath()..'/ColorThemes/'..file
    local app=App.new(h,g);assert(app:start());app:frame();return app,h,g
  end
  local function rgb(c) return c and table.concat(c,',') end
  local function shown(g,r,gr,b) -- text drawn in this colour
    local cur,n;n=0
    for _,c in ipairs(g.calls) do
      if c[1]=='set' then cur=c
      elseif c[1]=='drawstr' and cur and math.abs(cur[2]-r/255)<1e-6 and math.abs(cur[3]-gr/255)<1e-6 and math.abs(cur[4]-b/255)<1e-6 then n=n+1 end
    end
    return n
  end
  local app,h,g=open('CSIX-BASIC.ReaperThemeZip')
  local c=app.view.theme.csix
  eq(rgb(c.readout),'100,200,255');eq(rgb(c.vol_sel),'255,255,255');eq(rgb(c.vol),'210,210,210')
  eq(rgb(c.idx_sel),'38,38,38');eq(rgb(c.idx),'200,200,200');eq(rgb(c.name_sel),'235,255,255')
  assert(shown(g,100,200,255)>0,'peak readout uses the edition colour');assert(shown(g,235,255,255)>0,'selected name colour')
  assert(app.view.bitmaps.cache.mcp_vol_label,'the readout box art is drawn');assert(app.view.bitmaps.cache.mcp_namebg)
  -- The record tab's art ends 2 pt inside its 36 pt cell, which the mixer's 76 pt strip clips: the cell reaches 2 pt past the edge.
  local flat,fh,fg=open(flat_generic(fake.host()))
  eq(app.view.hits.I_RECARM.x,flat.view.hits.I_RECARM.x+2);eq(app.view.hits.I_RECARM.w,36)
  -- Another edition's own colours come from its script, not from BASIC's.
  local env={cache=h.cache..'/csix-colors',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local function variant(from,to)
    local changed,n=app.view.theme.rtconfig:gsub(from,to);assert(n>0,from);os.execute('mkdir -p "'..env.cache..'"')
    local f=assert(io.open(env.cache..'/rtconfig.txt','w'));f:write(changed);f:close();return assert(Theme.resolve(env.cache,env))
  end
  local t=variant('%[100 200 255 255 255 180 255 255%]','[0 150 255 255 255 180 255 255]')
  eq(rgb(t.csix.readout),'0,150,255');assert(t.full_art);eq(t.csix.idx_sel[1],38)
  t=variant('%?track_selected %[38 38 38%] %[200 200 200%]','?track_selected [255 150 0] [38 38 38]')
  eq(rgb(t.csix.idx_sel),'255,150,0');eq(rgb(t.csix.idx),'38,38,38')
  -- CSIX-AE-Narrow/SX differ in the mixer geometry (the pan section is 35 pt, the polarity button moves, the fader sits over the
  -- meter): a one-value change in that script must not borrow BASIC's arrangement.
  t=variant('%[0 0 0 36%] %[0 0 0 45%]','[0 0 0 35] [0 0 0 45]')
  eq(t.layout,'generic');assert(not t.full_art);eq(t.csix,nil)
  app:stop();flat:stop()
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

test('generic strip borrows only compatible mute and solo art and preserves clicks', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local env={cache=h.cache..'/generic-art',mkdir=h.RecursiveCreateDirectory}
  local theme=assert(Theme.resolve(flat_generic(h),env))
  eq(theme.layout,'generic')
  -- The synthetic gfx does not decode PNGs. Model the measured pink perimeter
  -- of this theme's 200% mute/solo sheets; the offline preview uses the real pixels.
  local getpixel=g.getpixel
  g.getpixel=function()
    local p=g.images[g.dest] or ''
    if (p:find('/200/track_mute_',1,true) or p:find('/200/track_solo_',1,true)) and
      (g.x==0 or g.y==0 or g.x==121 or g.y==41) then return 1,0,1 end
    return getpixel()
  end
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme)
  g.ext_retina=2;g.w=244;g.h=1400;v:frame()
  local drawn={}
  for _,b in ipairs(g.blits) do
    local n=g.images[b[1]]:match('([^/]+)%.png$'):gsub('^%d+_','')
    drawn[n]=true
    assert(n:find('^mcp_fxlist_') or n:find('^mcp_sendlist_') or n=='track_mute_off' or n=='track_solo_off',n)
  end
  assert(drawn.track_mute_off and drawn.track_solo_off,'theme buttons actually blitted')
  eq(#v.bitmaps.missing,0)
  local text={};for _,c in ipairs(g.calls) do if c[1]=='drawstr' then text[c[2]]=true end end
  for _,label in ipairs({'rec','FX','I/O','trim'}) do assert(text[label],label) end
  for _,id in ipairs({'B_MUTE','I_SOLO','I_RECARM','I_RECMON','FX','I_FXEN','D_VOL','D_PAN','I_AUTOMODE','fx1','output'}) do assert(v.hits[id],id) end
  local hit=v.hits.B_MUTE;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.a.values.B_MUTE,1);eq(h.open,0)
  -- A sheet with an incomplete third frame falls back to the labelled button.
  local a=assert(v.bitmaps.cache.track_mute_on);a.w=121
  g.calls={};g.blits={};v:frame()
  local plain=false;for _,c in ipairs(g.calls) do if c[1]=='drawstr' and c[2]=='M' then plain=true end end
  assert(plain);for _,b in ipairs(g.blits) do assert(b[1]~=a.slot) end
end)

test('cache folder names are plain ASCII whatever the archive is called, and a failed cache is reported', function()
  local Theme=dofile('inspector/theme.lua')
  local fake=dofile('tests/synthetic.lua');local h=fake.host()
  local env={cache=h.cache..'/dash',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  os.execute('rm -rf "'..env.cache..'"');env.mkdir(env.cache)
  local zip=env.cache..'/Zipped \226\128\147 Th\195\168me.ReaperThemeZip'      -- en dash and an accent in the name
  local f=assert(io.open(zip,'wb'));f:write(assert(io.open('tests/fixtures/Zipped theme.ReaperThemeZip','rb')):read('a'));f:close()
  local previous=os.setlocale(nil,'ctype');os.setlocale('en_US.UTF-8','ctype')   -- as inside a desktop application
  local ok,err=pcall(function()
    local t=assert(Theme.resolve(zip,env))
    assert(not t.dir:sub(#env.cache+1):find('[^A-Za-z0-9 _%-/]'),t.dir)
    assert(Theme.asset(t,'mcp_stored',2),'image cached');eq(t.error,nil)
    -- a cache that cannot be written says so instead of quietly losing the artwork
    local stuck=assert(Theme.resolve(zip,{cache='/nonexistent/reaper-inspector',mkdir=function() end}))
    eq(Theme.asset(stuck,'mcp_stored',2),nil);assert(stuck.error and stuck.error:find('cache'))
  end)
  os.setlocale(previous,'ctype');assert(ok,err)
end)

test('Reapertips v1.95 gets its own strip: every control from its own artwork at native size', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/v195',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'Reapertips Theme.ReaperThemeZip',env))
  eq(theme.layout,'reapertips2');eq(theme.version,1);eq(theme.param('mcp_sidebar_w'),86);eq(theme.param('absent',7),7)
  eq(assert(Theme.resolve(REAPERTIPS)).layout,'reapertips')                      -- v1.90 keeps the first layout
  local light=assert(Theme.resolve(home..'Reapertips Theme \226\128\147 Light.ReaperThemeZip',env))
  eq(light.version,3);eq(light.param('mcp_dim_sel_strength'),0)
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(hgt) g.ext_retina=2;g.w=172;g.h=hgt*2;v:frame() end
  at(500);eq(#v.bitmaps.missing,0)                                                -- short strip: input box only
  local arm,mute,solo,fx=v.hits.I_RECARM,v.hits.B_MUTE,v.hits.I_SOLO,v.hits.FX
  eq(arm.w,21);eq(arm.h,21);eq(mute.w,21);eq(mute.x,arm.x);eq(solo.y-mute.y,23)
  eq(fx.x,5);eq(fx.w,57);eq(v.hits.I_FXEN.x,62);eq(v.hits.I_FXEN.w,18)
  assert(v.hits.I_RECINPUT and v.hits.I_RECINPUT.w<60);eq(v.hits.I_RECMODE,nil)
  assert(v.hits.I_AUTOMODE.y<v.hits.B_PHASE.y,'envelope sits above polarity in v1.95')
  eq(v.hits.D_VOL.x,31);assert(v.layout.meter)
  at(700)                                                                         -- tall strip: full-width input box and record mode
  assert(v.hits.I_RECINPUT.w>70 and v.hits.I_RECMODE and v.hits.I_RECMODE.y>v.hits.I_RECINPUT.y)
  for _,id in ipairs({'D_PAN','IO','I_RECMON','name','output','fx1'}) do assert(v.hits[id],id) end
  local hit=v.hits.B_MUTE;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.a.values.B_MUTE,1)
  g.w=130;v:frame();for _,id in ipairs({'D_VOL','B_MUTE','I_RECARM','FX'}) do local k=v.hits[id];assert(k.x>=0 and k.x+k.w<=66,id) end
end)

test('6-style keeps v1.90 geometry and adapts Default 6 to its native art and section sizes', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/d6',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'Default_6.0.ReaperThemeZip',env))
  local custom=assert(Theme.resolve(REAPERTIPS))
  eq(theme.layout,custom.layout);eq(theme.row_height,16)
  local View,Model=dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local v=View.new(h,g,Model.new(h),theme,{output_strip=false})
  for _,density in ipairs({1,1.5,2}) do
    g.ext_retina=density;g.w=188;g.h=2186;v:frame()
    assert(v.bitmaps.cache.mcp_pan_knob_small);eq(v.bitmaps.cache.mcp_pan_knob_large,nil)
    assert(v.hits.I_RECINPUT and v.hits.INFX and v.hits.I_RECMODE)
    assert(v.hits.I_RECINPUT.y<v.hits.INFX.y and v.hits.INFX.y<v.hits.I_RECMODE.y)
    assert(v.bitmaps.cache.mcp_fx_in_empty_ol)
    assert(v.hits.D_PAN.w<28);assert(v.hits.D_VOL and v.hits.IO and v.hits.B_PHASE)
    eq(#v.bitmaps.missing,0)
  end
  g.ext_retina=2;g.w=172;g.h=800;v:frame();eq(v.hits.INFX,nil);eq(v.hits.I_RECINPUT,nil)
  assert(v.hits.I_RECMODE);eq(#h.writes,0)
  local c=View.new(h,g,Model.new(h),custom,{output_strip=false})
  g.h=2186;c:frame();assert(c.bitmaps.cache.mcp_pan_knob_large);eq(c.hits.D_PAN.w,28);eq(c.hits.INFX,nil)
  v:frame();local hit=v.hits.INFX
  g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.writes[#h.writes][1],'fx');eq(h.writes[#h.writes][3],0x1000000)
  eq(assert(Theme.resolve(home..'Instrument_6_MTL.ReaperThemeZip',env)).layout,'generic')
end)

test('6-style recognises compatible geometry without relying on a theme name', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme,View,Model=dofile('inspector/theme.lua'),dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local dir=h.cache..'/6-style-variant'
  local env={cache=dir,mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local stock=assert(Theme.resolve(home..'Default_6.0.ReaperThemeZip',env))
  local neptune=assert(Theme.resolve(home..'Neptune VI.ReaperThemeZip',env))
  local jmod=assert(Theme.resolve(home..'Neptune VI_JMod.ReaperTheme',env))
  local function render(theme)
    local v=View.new(h,g,Model.new(h),theme,{output_strip=false})
    g.ext_retina=2;g.w=188;g.h=1500;v:frame();return v
  end
  local base=render(stock)
  for _,theme in ipairs({neptune,jmod}) do
    eq(theme.layout,stock.layout);assert(theme.stock6)
    local v=render(theme)
    assert(v.bitmaps.cache.mcp_pan_knob_small and v.bitmaps.cache.mcp_volthumb)
    eq(v.hits.I_RECARM.y,v.hits.INFX.y+base.hits.I_RECARM.y-base.hits.INFX.y-2)
    eq(v.hits.name.h,base.hits.name.h+1)
  end
  eq(#h.writes,0)
  local function classify(cfg)
    local f=assert(io.open(dir..'/rtconfig.txt','w'));f:write(cfg);f:close()
    return assert(Theme.resolve(dir,env)).layout
  end
  eq(classify(neptune.rtconfig),stock.layout)
  local changed,n=neptune.rtconfig:gsub('(%[0 19 21 )20(%])','%138%2',1)
  eq(n,1);eq(classify(changed),'generic')
  changed,n=neptune.rtconfig:gsub('%[0 %-2 36 24%]','[0 -12 36 24]',1)
  eq(n,1);eq(classify(changed),'generic')
  for _,file in ipairs({'phaselab-theme-2.0-colored.ReaperThemeZip','phaselab-theme-2.0-uncolored.ReaperThemeZip',
      'phaselab-theme-uncoloredTCP_1.3_Custom.ReaperTheme','phaselab-theme-uncoloredTCP_1.3.zip'}) do
    local theme=assert(Theme.resolve(home..file,env))
    assert(theme.stock6,file..' resolved as '..theme.layout)
    local v=render(theme)
    for _,id in ipairs({'I_RECARM','B_MUTE','I_SOLO'}) do eq(v.hits[id].w,20);eq(v.hits[id].h,20) end
    eq(v.hits.I_RECARM.x,v.hits.I_RECMON.x)
    eq(v.hits.D_VOL.w,24);eq(v.hits.FX.w,base.hits.FX.w-1)
    assert(v.bitmaps.cache.mcp_volthumb and v.bitmaps.cache.mcp_recarm_off)
    assert(v.bitmaps.cache.track_mute_off and v.bitmaps.cache.track_phase_norm)
    eq(classify(theme.rtconfig),stock.layout)
  end
end)

test('PhaseLab colour bar stays behind the controls; pan marker and record-arm surround come from its art', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local chosen,tall=true,true
  h.IsTrackSelected=function(track) return chosen and track==h.a end
  local Theme,View,Model=dofile('inspector/theme.lua'),dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/phasefooter',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  -- The synthetic gfx does not decode PNGs: model the measured guide lines of the 200% art.
  g.getpixel=function()
    local name=(g.images[g.dest] or ''):match('/200_([%w_]+)%.png$')
    if tall and (name=='mcp_idxbg' or name=='mcp_idxbg_sel') and g.x==0 then
      if g.y<2285 then return 1,1,0 end
      if g.y<2325 then return 1,0,1 end
    elseif (name=='mcp_recarm_off_ol' or name=='mcp_mute_off_ol') and ((g.y==0 and g.x<15) or (g.x==0 and g.y<3)) then
      return 1,0,1
    end
    return .2,.2,.2
  end
  local function frame(theme)
    local v=View.new(h,g,Model.new(h),theme,{output_strip=false})
    local pointers=0;v.pointer=function() pointers=pointers+1 end
    g.w=188;g.h=1500;g.blits={};v:frame()
    local first,last={}, {}
    for i,b in ipairs(g.blits) do
      local name=g.images[b[1]]:match('/200_([%w_]+)%.png$') or g.images[b[1]]:match('([%w_]+)%.png$')
      first[name]=first[name] or i;last[name]=i
    end
    return v,first,last,pointers
  end
  local theme=assert(Theme.resolve(home..'phaselab-theme-2.0-colored.ReaperThemeZip',env))
  eq(theme.colors.col_seltrack2[1],73)
  local v,first,last,pointers=frame(theme)
  assert(first.mcp_bgsel and first.mcp_bgsel<first.mcp_idxbg_sel,'mixer background goes under the colour bar')
  assert(first.mcp_extmixbgsel<first.mcp_fxlist_bg and first.mcp_fxlist_bg<first.mcp_fxlist_norm,'insert list background sits between rack backing and cells')
  eq(v.hits.I_RECARM.y,v.layout.S-16) -- the theme's own offset: its surround must meet the fader panel
  eq(first.mcp_idxbg,nil)
  for _,front in ipairs({'mcp_fx_norm','mcp_pan_knob_small','mcp_recarm_off','mcp_volthumb','mcp_recmode_in'}) do
    assert(first[front] and last.mcp_idxbg_sel<first[front],front..' must be drawn over the colour bar')
  end
  for _,b in ipairs(g.blits) do
    if g.images[b[1]]:match('/200_mcp_idxbg_sel%.png$') then
      assert(b[9]>=v.layout.T*2 and b[9]+b[11]<=g.h,'colour bar left the lower strip')
      eq(b[7],b[11]) -- never stretched vertically
    end
  end
  -- The theme's own marker frames replace the generated pointer line.
  eq(pointers,0)
  local stack=g.blits[first.mcp_pan_knob_stack];eq(stack[6],40);eq(stack[7],40);eq(stack[5],17*40)
  assert(first.mcp_pan_knob_small<first.mcp_pan_knob_stack)
  -- The record-arm surround is the button's guided overlay; an overlay without guide lines is not one.
  assert(first.mcp_recarm_off<first.mcp_recarm_off_ol)
  h.a.values.I_RECARM=1
  local _,armed=frame(theme)
  assert(armed.mcp_recarm_on and not armed.mcp_recarm_on_ol and not armed.mcp_recarm_off_ol)
  h.a.values.I_RECARM=0;chosen=false
  local _,plain=frame(theme)
  assert(plain.mcp_idxbg and plain.mcp_bg and not plain.mcp_idxbg_sel and not plain.mcp_bgsel)
  -- Stock 6 has no such art: its footer stays in the footer and REAPER's pointer line remains.
  local stock=assert(Theme.resolve(home..'Default_6.0.ReaperThemeZip',env));tall=false
  local _,sfirst,_,spointers=frame(stock)
  eq(spointers,1);eq(sfirst.mcp_pan_knob_stack,nil)
  assert(sfirst.mcp_mute_off<sfirst.mcp_mute_off_ol,'stock overlay (button shadow) follows its button')
  for _,b in ipairs(g.blits) do
    if g.images[b[1]]:match('mcp_idxbg') then assert(b[9]>=g.h-60,'stock footer left its tile') end
  end
  eq(#h.writes,0)
end)

test('6-style uses the guided mixer background behind pan without covering the footer', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.IsTrackSelected=function(track) return track==h.a end
  local Theme,View,Model=dofile('inspector/theme.lua'),dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/panbg',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local function render(theme,margin)
    g.w=376;g.h=1500;g.blits={}
    g.getpixel=function()
      if (g.images[g.dest] or ''):match('/200_mcp_bg[^/]*%.png$') then
        -- Actual 200% PNG guides: two pink pixels along the top, a longer left guide.
        if (g.x==0 and g.y<margin) or (g.y==0 and g.x<2) then return 1,0,1 end
      end
      return .3,.3,.3
    end
    local v=View.new(h,g,Model.new(h),theme);v.choice[h.a.guid]=h.b;v:frame();return v
  end
  local function draws(v)
    local count={}
    for _,b in ipairs(g.blits) do
      local asset=g.images[b[1]]:match('/200_(mcp_bg%a*)%.png$')
      if asset then
        local T,S=v.layout.T,v.layout.S
        eq(b[5],65);eq(b[9],(T+32)*2);eq(b[11],(S-T-32)*2)
        count[asset]=(count[asset] or 0)+b[10]
      end
    end
    return count
  end
  local neptune=assert(Theme.resolve(home..'Neptune VI.ReaperThemeZip',env))
  local v=render(neptune,324);local count=draws(v)
  eq(count.mcp_bgsel,188);eq(count.mcp_bg,188)
  eq(next(draws(render(neptune,66))),nil) -- same structure, but the protected area no longer fits
  eq(next(draws(render(assert(Theme.resolve(home..'Default_6.0.ReaperThemeZip',env)),66))),nil)
  eq(#h.writes,0)
end)

test('Default 6 and 7 families paint theme rack backing before slots and fall back if absent', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme,View,Model=dofile('inspector/theme.lua'),dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/rackbg',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  g.w=376;g.h=1500
  local load=g.loadimg;local missing={}
  g.loadimg=function(i,path)
    if missing[path:match('([^/]+)%.png$')] then return -1 end
    return load(i,path)
  end
  local function render(theme)
    g.blits={};View.new(h,g,Model.new(h),theme):frame()
    local names={}
    for _,b in ipairs(g.blits) do
      local name=g.images[b[1]]:match('([^/]+)%.png$')
      names[#names+1]=name
    end
    return names
  end
  for _,file in ipairs({'Neptune VI.ReaperThemeZip','MK_Colored_Stripes_v5.3.ReaperThemeZip'}) do
    local theme=assert(Theme.resolve(home..file,env))
    missing={}
    local names=render(theme)
    assert(names[1]=='mcp_extmixbgsel',file..': '..tostring(names[1]))
    assert(names[2]:match('mcp_fxlist_norm$'))
    assert(table.concat(names,','):find(',mcp_extmixbg,',1,true)) -- unselected output strip
    missing.mcp_extmixbgsel=true
    eq(render(theme)[1],'mcp_extmixbg')
    missing.mcp_extmixbg=true
    eq(render(theme)[1],names[2])
  end
  eq(#h.writes,0)
end)

test('rack backing with touching vertical guides stretches a middle row, not the black foot', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme,View,Model=dofile('inspector/theme.lua'),dofile('inspector/view.lua'),dofile('inspector/model.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/reark',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'reARK_6.73.ReaperThemeZip',env))
  g.getpixel=function()
    if (g.images[g.dest] or ''):match('/200_mcp_extmixbgsel%.png$') then
      -- Guide runs from the real 85x9 reARK selected backing.
      local x,y=g.x,g.y
      if y==0 and x<2 or x==84 and y==8 then return 1,1,0 end
      if x==0 and y==1 or x==84 and y>=2 and y<8 or y==0 and x>=2 and x<25 or y==8 and x>=61 and x<84 then return 1,0,1 end
    end
    return .2,.2,.2
  end
  g.w=188;g.h=1500
  local v=View.new(h,g,Model.new(h),theme,{output_strip=false});v:frame()
  local stretched=false
  for _,b in ipairs(g.blits) do
    if g.images[b[1]]:match('/200_mcp_extmixbgsel%.png$') and b[11]>10 then
      eq(b[5],2);eq(b[7],1);stretched=true
    end
  end
  assert(stretched,'missing stretched rack backing')
end)

test('Default 7 gets its own strip, built from base art plus overlays, following Theme Adjuster values', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/d7',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'Default_7.0.ReaperThemeZip',env))
  eq(theme.layout,'default7');eq(theme.row_height,18);eq(theme.param('LayoutA-verboseMcp'),0);eq(theme.param('mcpBgColR'),129)
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(hgt) g.ext_retina=2;g.w=184;g.h=hgt*2;v:frame() end
  at(640);eq(#v.bitmaps.missing,0)
  local loaded={};for _,p in pairs(g.images) do loaded[p:match('([^/]+)%.png$'):gsub('^200_','')]=true end
  for _,n in ipairs({'track_mute_off','track_mute_off_ol','track_recarm_off_ol','mcp_io_s_ol','mcp_fx_norm','track_fxon_v_ol','dropdownBg_h','tcp_pan_knob_small','mcp_volthumb'}) do assert(loaded[n],n) end
  local mute,solo,io,fx,byp,env_,phase=v.hits.B_MUTE,v.hits.I_SOLO,v.hits.IO,v.hits.FX,v.hits.I_FXEN,v.hits.I_AUTOMODE,v.hits.B_PHASE
  eq(mute.w,20);eq(mute.h,20);eq(mute.x,92-32+6);eq(solo.y,mute.y+20);eq(io.y,solo.y+26);eq(io.h,22)
  eq(fx.y,io.y+28);eq(byp.y,fx.y+20);eq(byp.h,16);eq(env_.y,byp.y+22);eq(phase.y,env_.y+28)
  eq(v.hits.I_RECINPUT.w,80);eq(v.hits.I_RECMODE.w,40);assert(v.hits.INFX);eq(v.hits.I_RECARM.w,24)
  local compact=v.hits.D_PAN.y-v.hits.I_RECINPUT.y
  theme.live={['LayoutA-verboseMcp']=1};v:frame()                        -- Theme Adjuster: verbose
  eq(v.hits.IO.h,32);eq(v.hits.D_PAN.y-v.hits.I_RECINPUT.y,compact+14);eq(theme.param('LayoutA-verboseMcp'),1)
  theme.live={['LayoutA-mcpNormalShowRoute']=0};v:frame();eq(v.hits.IO,nil);assert(v.hits.FX.y<fx.y)
  theme.live=nil
  at(470);assert(v.hits.B_MUTE and v.hits.FX);eq(v.hits.B_PHASE,nil)      -- short strip: lowest buttons are left out, not squeezed
  for _,k in pairs(v.hits) do assert(k.y+k.h<=470+.01,k.id) end
  local hit=v.hits.INFX;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.writes[#h.writes][1],'fx');eq(h.writes[#h.writes][3],0x1000000)   -- input FX chain
end)

test('80gray: every installed edition gets the theme\'s own rows, sizes and colours; a changed script stays generic', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/g80',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  for _,edition in ipairs({'Classic','D3','Everforest Light','MP Classic','MP Machine','MP Octagon','MP Pro','MP Ristretto','MP Spectrum'}) do
    local t=assert(Theme.resolve(home..'80gray v2.2 '..edition..'.ReaperThemeZip',env))
    eq(t.layout,'gray80');eq(t.row_height,14);eq(t.send_row_height,18)
    for _,k in ipairs({'bg','bg_sel','idx','idx_sel','on_light','on_dark','bar','bar_sel','label','readout','line'}) do assert(t.gray80[k],edition..' '..k) end
  end
  local theme=assert(Theme.resolve(home..'80gray v2.2 Classic.ReaperThemeZip',env))
  eq(theme.gray80.bg[1],45);eq(theme.gray80.bg_sel[1],57);eq(theme.gray80.bar_sel[1],211);eq(theme.gray80.bar[1],38)
  eq(theme.param('p_mcp_indicator_width'),3);eq(theme.param('p_mcp_diagram_height'),16)
  local light=assert(Theme.resolve(home..'80gray v2.2 Everforest Light.ReaperThemeZip',env));eq(light.gray80.bg[1],255);eq(light.gray80.label[1],92)
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  -- The theme's default 63 pt strip: every control where its script puts it.
  at(63,700);eq(#v.bitmaps.missing,0)
  local T,RS,RB=v.layout.T,v.layout.S,v.layout.B
  eq(RS,T+44);eq(RB,700-16-16-4-16)
  local k=v.hits
  local function box(hit,x,y,w,hh) eq(hit.x,x);eq(hit.y,y);eq(hit.w,w);eq(hit.h,hh) end
  box(k.FX,3.5,T+3,22,18);box(k.I_FXEN,25.5,T+3,13,18);box(k.I_AUTOMODE,40,T+4,22,18);box(k.B_PHASE,46,T+23,13,18)
  box(k.D_PAN,2,T+24,41,14);box(k.B_MUTE,43,RS,18,18);box(k.I_SOLO,43,RS+18,18,18);box(k.IO,43,RS+37,20,20)
  box(k.I_RECARM,45,RB-14,14,14);box(k.I_RECMON,45,RB-29,14,14);box(k.INFX,45,RB-44,14,14)
  box(k.D_VOL,2,RS,16,RB-RS);box(k.meter,23,RS+1,17,RB-RS-2);eq(k.I_RECINPUT,nil)
  local loaded={};for _,p in pairs(g.images) do loaded[p:match('([^/]+)%.png$')]=true end
  for _,n in ipairs({'track_mute_off','track_solo_off','track_recarm_off','track_monitor_off','track_fx_in_empty','track_env','track_phase_norm','mcp_volbg','mcp_volthumb','mcp_panbg','mcp_panthumb','mcp_custom_meter_bg','mcp_diagram_dot'}) do assert(loaded[n],n) end
  local routing;for n in pairs(loaded) do if n:match('^mcp_io') then routing=true end end;assert(routing)
  -- Wider panels: controls keep their size; the right column follows the edge, the top pair stays centred.
  for _,w in ipairs({63,86,122,200}) do
    at(w,700);k=v.hits
    eq(k.B_MUTE.x,w-20);eq(k.B_MUTE.w,18);eq(k.I_RECARM.x,w-18);eq(k.FX.x,-5+(w-46)/2);eq(k.meter.w,w-46)
    local order={}
    for _,id in ipairs({'FX','I_FXEN','I_AUTOMODE','B_PHASE','D_PAN','B_MUTE','I_SOLO','IO','I_RECARM','I_RECMON','INFX','D_VOL','meter','name'}) do order[#order+1]=assert(k[id],id) end
    for i,a in ipairs(order) do
      assert(a.x>=0 and a.x+a.w<=w+.01 and a.y+a.h<=700.01,a.id..' leaves the strip at '..w)
      for j=i+1,#order do local b=order[j]
        assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,a.id..' overlaps '..b.id..' at '..w)
      end
    end
  end
  -- Stereo and dual pan swap the slider for two knobs; send rows are taller than insert rows.
  h.a.values.I_PANMODE=5;at(86,700);box(v.hits.D_PAN,-3+40/3,T+24,17,17);box(v.hits.D_WIDTH,12+40*.66,T+24,17,17)
  h.a.values.I_PANMODE=6;at(86,700);assert(v.hits.D_DUALPANL and v.hits.D_DUALPANR);eq(v.hits.D_PAN,nil)
  h.a.values.I_PANMODE=3;at(86,700)
  eq(v.hits.fxadd2.y-v.hits.fx1.y,14);eq(v.hits.output.h,18)
  local hit=v.hits.B_MUTE;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.writes[#h.writes][2],'B_MUTE');eq(#h.writes,1)
  -- Master as the output strip: its own bottom rows, a solo button and a working mono switch; none on a track.
  v.options.output_strip=true;at(200,700);k=v.hits
  assert(k['out:I_SOLO'] and k['out:MONO'] and k['out:IO']);eq(k['out:B_PHASE'],nil);eq(k['out:name'],nil);eq(k.MONO,nil)
  eq(k['out:MONO'].y,T+23);eq(k['out:MONO'].x,100+100-20)
  eq(k['out:D_VOL'].h,(700-16-4-16)-RS)                       -- no routing-diagram row under the master
  local before=#h.writes;h.commands={}
  hit=k['out:MONO'];g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(h.commands[#h.commands],40917);eq(#h.commands,1);eq(#h.writes,before)
  assert(not dofile('inspector/model.lua').new(h):master_mono(v.snapshot),'only the master has a mono switch')
  -- Recognised by its script, not its name: one changed size falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[26 __y 18 18 0 0 0 0%]','[26 __y 20 18 0 0 0 0]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'/changed"')
  local f=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f:write(changed);f:close()
  local other=assert(Theme.resolve(env.cache..'/changed',env));eq(other.layout,'generic');eq(other.gray80,nil);eq(other.send_row_height,nil)
end)

test('theFRXST: name on top, racks inside the strip, bottom-anchored panel; the meter gives way on narrow strips', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/frxst',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'theFRXST 3.three.ReaperThemeZip',env))
  eq(theme.layout,'frxst');eq(theme.row_height,23);eq(theme.send_row_height,27)
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;v:frame() end
  -- The theme's own 124 pt strip: each control at the script's rectangle, 1 pt lower as the mixer shows it.
  at(124,800);eq(#v.bitmaps.missing,0)
  local k=v.hits;local function Y(y) return 800-343+y end
  local function box(hit,x,y,w,hh) eq(hit.x,x);eq(hit.y,y);eq(hit.w,w);eq(hit.h,hh) end
  box(k.FX,7,Y(59),25,25);box(k.I_FXEN,30,Y(61),20,21);box(k.IO,94,Y(59),22,25)
  box(k.I_RECINPUT,7,Y(84),80,25);box(k.INFX,87,Y(84),30,25);box(k.I_RECMON,9,Y(109),106,25)
  box(k.D_PAN,13,Y(169),36,21);box(k.I_AUTOMODE,7,Y(226),25,25);box(k.B_PHASE,32,Y(226),22,25)
  box(k.B_MUTE,13,Y(262),36,25);box(k.I_SOLO,13,Y(287),36,25);box(k.I_RECARM,13,Y(312),36,25)
  box(k.D_VOL,52,Y(145),22,191);box(k.meter,77,Y(145)+1,36,189)
  eq(k.D_WIDTH,nil)                                                   -- shown, but only live in stereo pan mode
  eq(k.fx1.y,23);eq(k.fx1.x,5);eq(k.fxadd2.y-k.fx1.y,23);eq(k.output.h,27);assert(k.output.y+27<=Y(51))
  eq(k.name.y,0);assert(k.name.y+k.name.h<=k.fx1.y)
  -- Narrower and wider panels: left column and fader stay put, right-hand controls follow the edge,
  -- and the meter takes the difference until there is no room for it.
  for _,w in ipairs({86,100,124,172}) do
    at(w,800);k=v.hits;local d=w-124
    eq(k.IO.x,94+d);eq(k.INFX.x,87+d);eq(k.I_RECINPUT.w,80+d);eq(k.I_RECMON.w,106+d);eq(k.D_VOL.x,52);eq(k.B_MUTE.x,13)
    eq(k.meter~=nil,38+d>=10);eq(v.layout.meter,38+d>=10)
    if k.meter then eq(k.meter.w,36+d);assert(k.meter.x+k.meter.w<=w-4) end
    local order={}
    for _,id in ipairs({'name','FX','I_FXEN','IO','I_RECINPUT','INFX','I_RECMON','D_PAN','I_AUTOMODE','B_PHASE','B_MUTE','I_SOLO','I_RECARM','D_VOL'}) do order[#order+1]=assert(k[id],id) end
    if k.meter then order[#order+1]=k.meter end
    for i,a in ipairs(order) do
      assert(a.x>=0 and a.x+a.w<=w+.01 and a.y+a.h<=800.01,a.id..' leaves the strip at '..w)
      for j=i+1,#order do local b=order[j]
        -- Two pairs of the theme's own rectangles overlap by 2 pt.
        local own=(a.id=='FX' and b.id=='I_FXEN') or (a.id=='B_PHASE' and b.id=='D_VOL')
        assert(own or a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,a.id..' overlaps '..b.id..' at '..w)
      end
    end
  end
  h.a.values.I_PANMODE=5;at(124,800);box(v.hits.D_WIDTH,13,Y(194),36,21)
  h.a.values.I_PANMODE=6;at(124,800);assert(v.hits.D_DUALPANL and v.hits.D_DUALPANR);eq(v.hits.D_PAN,nil)
  h.a.values.I_PANMODE=3
  -- Master as the output strip: its own rows, mono switch, no input rows.
  v.options.output_strip=true;at(248,800);k=v.hits
  box(k['out:MONO'],124+12,Y(138),35,25);box(k['out:D_VOL'],124+49,Y(88),22,249);box(k['out:B_MUTE'],124+12,Y(262),36,25)
  assert(k['out:I_SOLO'] and k['out:IO'] and k['out:FX']);eq(k['out:I_RECINPUT'],nil);eq(k['out:I_RECMON'],nil);eq(k['out:I_RECARM'],nil);eq(k['out:name'],nil)
  local before=#h.writes
  local hit=k.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[13 262 36 25 0 1 0 1%]','[13 262 38 25 0 1 0 1]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'/changed"')
  local f=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f:write(changed);f:close()
  local other=assert(Theme.resolve(env.cache..'/changed',env));eq(other.layout,'generic');eq(other.send_row_height,nil)
end)

test('Mydaw: top rows hang from the panel top, the button column and name from the bottom, at any strip width', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/mydaw',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  local theme=assert(Theme.resolve(home..'Mydaw.ReaperThemeZip',env))
  eq(theme.layout,'mydaw');eq(theme.row_height,15);eq(theme.send_row_height,18)
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;v:frame() end
  -- The theme's default 80 pt strip with its full 380 pt panel.
  at(80,800);eq(#v.bitmaps.missing,0)
  local k=v.hits;local T=420;local function B(y) return 800-380+y end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.001,hit.id..' x '..hit.x);eq(hit.y,y);eq(hit.w,w);eq(hit.h,hh) end
  local x0=14                                                        -- 0.33 of the width, less the fraction of a pixel, minus 12
  box(k.FX,4,T+4,24,15);box(k.I_FXEN,51,T+4,24,15);box(k.I_RECINPUT,4,T+31,72,15)
  box(k.INFX,4,T+50,15,15);box(k.I_RECMON,30,T+50,21,15);box(k.I_RECMODE,61,T+50,15,15);box(k.IO,4,T+69,72,15)
  box(k.meter,80*.66-6,T+110,15,246);box(k.D_VOL,80*.66+5,T+103,22,246)
  box(k.D_PAN,x0-7,B(227),38,38);box(k.B_MUTE,x0,B(274),25,25);box(k.B_PHASE,x0,B(303),25,15)
  box(k.I_SOLO,x0,B(322),25,15);box(k.I_RECARM,x0,B(341),25,15);box(k.name,0,B(359),80,21)
  eq(k.fxadd2.y-k.fx1.y,15);eq(k.output.h,18);assert(k.output.y+18<=T)
  for _,w in ipairs({68,74,80,86,120}) do
    for _,mode in ipairs({3,5,6}) do
      h.a.values.I_PANMODE=mode;at(w,700);k=v.hits
      local ids={'FX','I_FXEN','I_RECINPUT','INFX','I_RECMON','I_RECMODE','IO','B_MUTE','B_PHASE','I_SOLO','I_RECARM','name','meter'}
      for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
      if mode==6 then eq(k.D_PAN,nil) else eq(k.D_PAN.w,(mode==3 and w>74) and 38 or 25) end
      local order={}
      for _,id in ipairs(ids) do order[#order+1]=assert(k[id],id..' at '..w) end
      for i,a in ipairs(order) do
        assert(a.x>=0 and a.x+a.w<=w+.01 and a.y+a.h<=700.01,a.id..' leaves the strip at '..w)
        for j=i+1,#order do local b=order[j]
          assert(a.x+a.w<=b.x or b.x+b.w<=a.x or a.y+a.h<=b.y or b.y+b.h<=a.y,a.id..' overlaps '..b.id..' at '..w)
        end
      end
      assert(k.D_VOL.x+k.D_VOL.w<=w+.01 and k.D_VOL.x>=k.meter.x)  -- the fader's slot lies over the meter's right side
    end
  end
  h.a.values.I_PANMODE=3
  -- Master as the output strip: menu art, centred routing, mono switch, no input rows; its meter takes the width.
  v.options.output_strip=true;at(240,800);k=v.hits
  box(k['out:B_MUTE'],120+13,B(266),25,25);box(k['out:MONO'],120+13,B(333),25,15);box(k['out:meter'],120+50,T+110,53,238) -- the master's bottom rows sit 8 pt higher
  box(k['out:IO'],120+24,T+31,72,15)
  assert(k['out:I_SOLO'] and k['out:FX'] and k['out:D_PAN']);eq(k['out:I_RECINPUT'],nil);eq(k['out:I_RECARM'],nil);eq(k['out:B_PHASE'],nil);eq(k['out:name'],nil)
  at(172,800);eq(v.hits['out:meter'].w,19)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[low_ident{0} sm47{0} s25{0} s25{0} 0 1 0 1%]','[low_ident{0} sm47{0} s26{0} s25{0} 0 1 0 1]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'/changed"')
  local f=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f:write(changed);f:close()
  local other=assert(Theme.resolve(env.cache..'/changed',env));eq(other.layout,'generic');eq(other.send_row_height,nil)
end)

test('CSIX AE-Narrow / SX: one layout for all six editions, bottom-up from the panel, the meter taking extra width', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/csixsx',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  for _,name in ipairs({'AE-Narrow-dark','AE-Narrow-light','AE-Narrow-slate','SX-dark','SX-light','SX-loom'}) do
    local t=assert(Theme.resolve(home..'CSIX-'..name..'.ReaperThemeZip',env),name);eq(t.layout,'csixsx');assert(t.csix and t.csix.vol,name)
  end
  eq(Theme.resolve(home..'CSIX-BASIC.ReaperThemeZip',env).layout,'generic')       -- a different script: not this layout
  local theme=assert(Theme.resolve(home..'CSIX-AE-Narrow-dark.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;v:frame() end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);eq(hit.y,y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);eq(hit.h,hh) end
  -- The 84 pt strip of the native screenshot, 313 pt panel (measured: the panel's rows are 2 px per point).
  at(84,563);eq(#v.bitmaps.missing,0);eq(v.layout.L,313)
  -- Rack text: mcp.fxlist/sendlist.font 11 is user_font10 (Roboto, 400, 20 px), not the condensed bold 16 px sibling; the pinned
  -- 'Master send' row draws with the 'list' slot, so slots 2 (inserts, Master send) and 5 (sends) must be the same font.
  local function slot(i) for n=#g.calls,1,-1 do local c=g.calls[n];if c[1]=='setfont' and c[2]==i and c[3] then return c[3]..' '..c[4]..' '..c[5] end end end
  eq(slot(2),'Roboto 25 0');eq(slot(5),slot(2));eq(slot(4),'Roboto Condensed 25 0')
  local k,T=v.hits,250
  box(k.FX,5,T+8,42.33,20);box(k.I_FXEN,47.33,T+8,31.67,20);box(k.D_PAN,30,T+35,26,26)
  box(k.I_RECINPUT,6,T+77,73,16);box(k.INFX,6,T+93,30,12);box(k.I_RECMODE,6,T+105,29,16);box(k.B_PHASE,35,T+105,16,17)
  box(k.meter,6,T+157,29,105);box(k.D_VOL,38,T+155,21,107);box(k.I_RECARM,52,T+117,32,22);box(k.I_RECMON,61,T+139,21,20)
  box(k.B_MUTE,60,T+161,21,20);box(k.I_SOLO,60,T+184,21,20);box(k.IO,59,T+213,23,22);box(k.name,0,T+266,84,27)
  eq(k.output.h,16);assert(k.output.y+16<=T)
  -- Pan and width knobs are a cap plus a value-indexed frame over it (no generated pointer): hard left, stereo pan, centre, hard right.
  local pointers=0;local pointer=v.pointer;v.pointer=function() pointers=pointers+1 end
  local function art(pattern) -- first blit order and device-pixel extent of one image
    local o,x1,y1,x2,y2
    for i,b in ipairs(g.blits) do if g.images[b[1]]:match(pattern) then
      o=o or i;x1,y1=math.min(x1 or b[8],b[8]),math.min(y1 or b[9],b[9]);x2,y2=math.max(x2 or 0,b[8]+b[10]),math.max(y2 or 0,b[9]+b[11])
    end end
    return o,x1,y1,x2,y2
  end
  local function frame_of(pattern) for _,b in ipairs(g.blits) do if g.images[b[1]]:match(pattern) then return (b[5]-v.bitmaps.cache[pattern:match('(mcp_%a+_knob_stack)')].y)/b[6] end end end
  local function knob_check(id,cap,stack,frame,hit)
    local co,cx1,cy1,cx2,cy2=art(cap);local so,sx1,sy1,sx2,sy2=art(stack)
    assert(co and so and co<so,id..': cap first, frame over it')
    eq(frame_of(stack),frame)
    eq(sx1,hit.x*2);eq(sy1,hit.y*2);eq(sx2-sx1,52);eq(sy2-sy1,52)            -- the frame fills the 26 pt hit box
    assert(cx1<=sx1 and cy1<=sy1 and cx2>=sx2 and cy2>=sy2,id..': cap covers its frame')
    assert(math.abs((cx1+cx2)-(sx1+sx2))<=2 and math.abs((cy1+cy2)-(sy1+sy2))<=2,id..': cap centred on its frame')
  end
  h.a.values.D_PAN=-1;h.a.values.I_PANMODE=3;g.blits={};at(84,563);k=v.hits
  knob_check('hard left','_mcp_pan_knob_large%.png$','_mcp_pan_knob_stack%.png$',0,k.D_PAN)
  eq(art('mcp_width_knob'),nil);eq(art('mcp_wid_knob_stack'),nil)
  h.a.values.D_PAN=1;g.blits={};at(84,563);knob_check('hard right','_mcp_pan_knob_large%.png$','_mcp_pan_knob_stack%.png$',60,v.hits.D_PAN)
  h.a.values.D_PAN=0;g.blits={};at(84,563);knob_check('centre','_mcp_pan_knob_large%.png$','_mcp_pan_knob_stack%.png$',30,v.hits.D_PAN)
  h.a.values.I_PANMODE=5;h.a.values.D_PAN=-1;h.a.values.D_WIDTH=.85;g.blits={};at(84,563);k=v.hits
  box(k.D_PAN,14,T+35,26,26);box(k.D_WIDTH,47,T+35,26,26)                  -- 10+d/2 and 43+d/2 (d=8): two 26 pt knobs, pan left of width
  knob_check('stereo pan','_mcp_pan_knob_large%.png$','_mcp_pan_knob_stack%.png$',0,k.D_PAN)
  knob_check('stereo width','_mcp_width_knob_large%.png$','_mcp_wid_knob_stack%.png$',28,k.D_WIDTH) -- +85% of the -100..+100% frames
  h.a.values.I_PANMODE=6;h.a.values.D_DUALPANL=-1;h.a.values.D_DUALPANR=.4;g.blits={};at(84,563)
  eq(art('mcp_pan_knob'),nil);eq(art('mcp_wid_knob'),nil);eq(pointers,0)    -- dual pan is two bars, no knob art
  h.a.values.I_PANMODE=nil;h.a.values.D_PAN=0;h.a.values.D_WIDTH=nil;h.a.values.D_DUALPANL=nil;h.a.values.D_DUALPANR=nil
  v.pointer=pointer;g.blits={};at(84,563);k=v.hits
  for _,w in ipairs({78,84,86,96,120}) do
    for _,mode in ipairs({3,5,6}) do
      h.a.values.I_PANMODE=mode;at(w,700);k=v.hits
      local ids={'FX','I_FXEN','I_RECINPUT','INFX','I_RECMODE','B_PHASE','I_RECMON','I_RECARM','IO','B_MUTE','I_SOLO','name','D_VOL'}
      eq(v.layout.meter,true);ids[#ids+1]='meter'
      for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
      local order={}
      for _,id in ipairs(ids) do order[#order+1]=assert(k[id],id..' at '..w) end
      for i,a in ipairs(order) do
        assert(a.x>=0 and a.x+a.w<=w+.01 and a.y+a.h<=700.01,a.id..' leaves the strip at '..w)
        for j=i+1,#order do local b=order[j]
          assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w)
        end
      end
    end
  end
  h.a.values.I_PANMODE=3
  -- The meter takes the width the script's nchan_offs gives it; the fader and buttons keep their distance to it.
  at(96,563);eq(v.hits.meter.w,41);eq(v.hits.D_VOL.x,v.hits.meter.x+v.hits.meter.w+3)
  -- Master as the output strip: no input, arm or monitor rows, a mono/stereo switch in their place.
  v.options.output_strip=true;at(172,563);k=v.hits
  assert(k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:MONO'] and k['out:D_PAN']);eq(k['out:I_RECINPUT'],nil);eq(k['out:I_RECMON'],nil);eq(k['out:I_RECARM'],nil);eq(k['out:name'],nil)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[6 2 65 16%]','[6 2 64 16]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'/changed"')
  local f=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f:write(changed);f:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('Flat Madness: the macro\'s rows from the panel top and bottom, three strip widths, the meter taking extra width', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/flatmadness',mkdir=function(p) os.execute('mkdir -p "'..p..'"') end}
  -- CI and SI, Bright and Dark share one mixer script; each edition's own adjuster defaults come with it.
  for _,name in ipairs({'CI 5.1.0 Dark','CI 5.1.0 Bright','SI 5.1.0 Dark','SI 5.1.0 Bright'}) do
    local t=assert(Theme.resolve(home..'Flat Madness '..name..'.ReaperThemeZip',env),name);eq(t.layout,'flatmadness')
    eq(t.bright,name:find('Bright')~=nil);eq(t.param('saturncmcp',0),t.bright and 120 or 80);eq(t.row_height,16)
  end
  local theme=assert(Theme.resolve(home..'Flat Madness CI 5.1.0 Dark.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;v:frame() end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);eq(hit.y,y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);eq(hit.h,hh) end
  local function blit(pattern) -- the pieces of one image: first blit's slot, extent in device pixels
    local x1,y1,x2,y2,last
    for _,b in ipairs(g.blits) do if g.images[b[1]]:match(pattern) then
      x1,y1=math.min(x1 or b[8],b[8]),math.min(y1 or b[9],b[9]);x2,y2=math.max(x2 or 0,b[8]+b[10]),math.max(y2 or 0,b[9]+b[11]);last=b
    end end
    return x1,y1,x2,y2,last
  end
  -- The strip of the native screenshot: 94 pt wide, 314 pt panel (measured; the script's 320 pt frame hangs from the bottom).
  at(94,564);eq(#v.bitmaps.missing,0);eq(v.layout.L,314)
  local k,T=v.hits,250;local function B(y) return T+314-320+y end
  box(k.I_RECARM,7,T+8,18,20);box(k.I_RECMODE,25,T+8,20,20);box(k.I_RECMON,49,T+8,22,20);box(k.I_AUTOMODE,7,T+31,64,20)
  box(k.I_RECINPUT,7,T+54,64,20);box(k.name,0,T+78,94,18);box(k.FX,6,T+102,22,20);box(k.I_FXEN,28,T+102,18,20);box(k.INFX,46,T+102,26,20)
  box(k.D_PAN,6,T+124,20,20);box(k.meter,4,T+168,35,106);box(k.D_VOL,45,T+168,19,106)
  box(k.B_MUTE,68,T+166,20,18);box(k.I_SOLO,68,T+184,20,18);box(k.B_PHASE,70,B(252),17,17);box(k.IO,68,B(274),20,22)
  eq(k.fxadd2.y-k.fx1.y,16);assert(k.output.y+16<=T)
  -- Artwork as the mixer stacks it: the selected card art over the panel, 1 pt left of the strip's edge; a 13 pt slot in each 16 pt row;
  -- the fader's tall image from its cap's top down to the groove's end.
  local x1,y1,x2,y2=blit('mcp_adjust_bgsel%.png$');eq(x1,-2);eq(y1,T*2);eq(x2,186);eq(y2,(T+314)*2)
  x1,y1,x2,y2=blit('mcp_fxlist_empty%.png$');eq(x1,-3);eq(y1,32);eq(x2-x1,186)  -- the second row: the first holds the plug-in
  local _,_,_,_,cap=blit('mcp_volthumb%.png$');eq(cap[10],38);eq(cap[9]+cap[11],(T+168+106)*2)
  assert(blit('mcp_idxbg_sel%.png$'),'footer art');assert(blit('gloss%.png$'),'gloss over the button groups')
  -- Three widths of the script (80, 94, 114 pt): the columns keep their places and the meter takes what lies beyond.
  at(96,564);eq(v.hits.meter.w,37);eq(v.hits.D_VOL.x,47);eq(v.hits.B_MUTE.x,70)
  at(86,564);eq(v.hits.meter.w,29);eq(v.hits.D_VOL.x,37);eq(v.hits.B_MUTE.x,60)
  at(114,564);eq(v.hits.meter.w,55);eq(v.hits.D_VOL.x,65);eq(v.hits.B_MUTE.x,88)
  at(140,564);eq(v.hits.meter.w,81);eq(v.hits.B_MUTE.x,114)
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip, in one strip or two.
  for _,hgt in ipairs({409,454,600}) do
    for _,w in ipairs({80,86,94,96,114}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'FX','I_FXEN','INFX','I_RECARM','I_RECMODE','I_RECMON','I_AUTOMODE','I_RECINPUT','name','B_MUTE','I_SOLO','B_PHASE','IO','D_VOL','meter'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        if mode==6 then eq(k.D_PAN,nil) end
        local order={}
        for _,id in ipairs(ids) do order[#order+1]=assert(k[id],id..' at '..w) end
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.x>=k.meter.x+k.meter.w and k.IO.y+k.IO.h<=hgt)
      end
    end
  end
  h.a.values.I_PANMODE=3
  -- Master as the output strip: a track-style strip without the input and arm rows, a tall mono switch above routing, an unselected card.
  v.options.output_strip=true;g.blits={};at(188,564);k=v.hits
  assert(k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:D_PAN'] and k['out:I_AUTOMODE'])
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
  box(k['out:MONO'],94+68,B(220),20,50);box(k['out:IO'],94+68,B(274),20,22);assert(blit('mcp_adjust_bg%.png$'),'the unselected master draws the plain card')
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[3 172 20 22 0 1 0 1%]','[3 172 20 23 0 1 0 1]')
  assert(n>0);os.execute('mkdir -p "'..env.cache..'/changed"')
  local f=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f:write(changed);f:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('iconEX: the macro\'s rows from the panel top and bottom, the track colour only in the art\'s slot, selection as a cap', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/iconex',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  -- Dark, Hybrid and Light share one mixer macro; only colours differ (track number, selected name), read from it.
  local want={Dark={255,160},Hybrid={170,150},Light={170,150}}
  for _,name in ipairs({'Dark','Hybrid','Light'}) do
    local t=assert(Theme.resolve(home..'iconEX '..name..'.ReaperThemeZip',env),name);eq(t.layout,'iconex')
    eq(t.ix.idx_sel[1],want[name][1]);eq(t.ix.idx[1],want[name][2]);eq(t.ix.name_sel[1],name=='Light' and 96 or 230)
    eq(t.row_height,16);eq(t.font,'Helvetica Neue');eq(t.param('mcplabelbrightness_Df',0),name=='Light' and 100 or 175);eq(t.param('mcp_solid_color_Df',0),1)
  end
  eq(assert(Theme.resolve(home..'iconEX Dark.ReaperTheme',env)).layout,'iconex')
  local theme=assert(Theme.resolve(home..'iconEX Dark.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);eq(hit.y,y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);eq(hit.h,hh) end
  local function blit(pattern) -- the pieces of one image: extent in device pixels, last piece
    local x1,y1,x2,y2,last
    for _,b in ipairs(g.blits) do if g.images[b[1]]:match(pattern) then
      x1,y1=math.min(x1 or b[8],b[8]),math.min(y1 or b[9],b[9]);x2,y2=math.max(x2 or 0,b[8]+b[10]),math.max(y2 or 0,b[9]+b[11]);last=b
    end end
    return x1,y1,x2,y2,last
  end
  -- The strip of the native screenshot: 80 pt wide, 300 pt panel from 222 pt below the strip's top (hit boxes sit 1 pt left of the
  -- script's x, as the panel does).
  local T=220;local function B(y) return T+300-319+y end
  at(80,520);eq(#v.bitmaps.missing,0);eq(v.layout.L,300);local k=v.hits
  box(k.I_RECARM,7,T+8,18,20);box(k.I_RECMODE,25,T+8,20,20);box(k.I_RECMON,49,T+8,22,20);box(k.I_AUTOMODE,7,T+31,64,20)
  box(k.I_RECINPUT,7,T+54,64,20);box(k.name,0,T+78,80,18);box(k.FX,5,T+102,22,20);box(k.I_FXEN,27,T+102,18,20);box(k.INFX,46,T+102,26,20)
  box(k.D_PAN,6,T+124,20,20);box(k.meter,7,T+166,18,90);box(k.D_VOL,29,T+168,19,86)
  box(k.B_MUTE,54,T+166,20,18);box(k.I_SOLO,54,T+184,20,18);box(k.B_PHASE,56,B(256),17,17);box(k.IO,54,B(279),20,18)
  eq(k.fxadd2.y-k.fx1.y,16);assert(k.output.y+16<=T)
  -- Artwork: the panel art 1 pt left of the strip's edge and a point taller than the frame, the selected cap over it, the fader's tall image from its
  -- cap's top down to the groove's end (the cap's top row is the middle of the image).
  local x1,y1,x2,y2=blit('mcp_color_bg%.png$');eq(x1,-2);eq(y1,T*2);eq(x2,158);eq(y2,(T+301)*2)       -- (the synthetic gfx reads no guide pixels: no overhang)
  x1,y1,x2,y2=blit('mcp_sol1_bgsel%.png$');eq(x1,-2);eq(y1,T*2)
  local _,_,_,_,cap=blit('mcp_volthumb%.png$');eq(cap[10],39);eq(cap[8],58);eq(cap[9]+cap[11],(T+254)*2);eq(cap[5],v.bitmaps.cache.mcp_volthumb.height//2)
  -- The track's colour is one fill under the panel's top 160 pt, seen through the art's slot; nothing else takes it.
  local function fills(r,gg,b) -- rect calls drawn in one colour
    local out,cur={}
    for _,c in ipairs(g.calls) do
      if c[1]=='set' then cur=c elseif c[1]=='rect' and cur and math.abs(cur[2]*255-r)<1 and math.abs(cur[3]*255-gg)<1 and math.abs(cur[4]*255-b)<1 then out[#out+1]=c end
    end
    return out
  end
  local f=fills(68,68,68);eq(#f,1);eq(f[1][3],T*2);eq(f[1][5],320)          -- no colour: the theme's selected-track grey (col_seltrack)
  h.GetTrackColor=function() return 1 end                                   -- the host's stand-in colour is 204,179,49
  at(80,520);f=fills(204,179,49);eq(#f,1);eq(f[1][3],T*2);eq(f[1][5],320)
  h.GetTrackColor=function() return 0 end
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip, in one strip or two.
  for _,hgt in ipairs({409,454,600}) do
    for _,w in ipairs({80,86,96}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        eq(v.layout.L,math.max(300,math.min(320,hgt-220)))
        local ids={'FX','I_FXEN','INFX','I_RECARM','I_RECMODE','I_RECMON','I_AUTOMODE','I_RECINPUT','name','B_MUTE','I_SOLO','B_PHASE','IO','D_VOL','meter'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        if mode==6 then eq(k.D_PAN,nil) end
        local order={}
        for _,id in ipairs(ids) do order[#order+1]=assert(k[id],id..' at '..w) end
        for i,a in ipairs(order) do
          assert(a.x>=-1.01 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.x>=k.meter.x+k.meter.w and k.IO.y+k.IO.h<=hgt)
      end
    end
  end
  h.a.values.I_PANMODE=3
  -- Width beyond the native 80 pt goes to the meter; the fader and the button column move with it.
  at(96,520);eq(v.hits.meter.w,34);eq(v.hits.D_VOL.x,45);eq(v.hits.B_MUTE.x,70);eq(v.hits.FX.x,5)
  -- Master as the output strip: a track-style strip without the input and arm rows, a mono switch above routing, an unselected panel.
  v.options.output_strip=true;at(172,520);k=v.hits
  assert(k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:D_PAN'] and k['out:I_AUTOMODE'])
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
  box(k['out:MONO'],86+54+6,B(222),20,48);assert(k['out:MONO'].y>=k['out:I_SOLO'].y+18 and k['out:MONO'].y+48<=k['out:IO'].y)
  for _,b in ipairs(g.blits) do if g.images[b[1]]:match('mcp_sol1_bgsel%.png$') then assert(b[8]<172,'only the selected strip draws the cap') end end
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Hybrid and Light draw from their own art with the same rows.
  for _,name in ipairs({'Hybrid','Light'}) do
    local t2=assert(Theme.resolve(home..'iconEX '..name..'.ReaperThemeZip',env))
    local v2=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t2,{output_strip=false})
    g.ext_retina=2;g.w=160;g.h=1040;g.blits={};v2:frame();eq(#v2.bitmaps.missing,0);box(v2.hits.D_VOL,29,T+168,19,86)
  end
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('%[6 102 22 20%]','[6 102 22 21]')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('nvk_THEME: the script\'s top-down rows over a fader that takes what is left, bottom rows hung from the strip\'s end, one script for Dark and Light', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/nvk',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  -- Dark and Light ship the same rtconfig.txt (and the same mixer artwork); recognition reads the script, never the file name.
  for _,name in ipairs({'Dark','Light'}) do
    local t=assert(Theme.resolve(home..'nvk_THEME_'..name..'.ReaperThemeZip',env),name);eq(t.layout,'nvk')
    eq(t.row_height,16);eq(t.font,'Verdana');eq(t.param('mcp_PaddingSize_param',0),3);eq(t.param('color_SelectionOpacity_param',0),28)
    eq(assert(Theme.resolve(home..'nvk_THEME_'..name..'.ReaperTheme',env)).layout,'nvk')
  end
  local theme=assert(Theme.resolve(home..'nvk_THEME_Dark.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 86 pt wide, 525 pt tall, stereo pan. Every box is the script's rectangle at 200% (a 3 pt padding):
  -- the racks' box from y 30 (a fifth of the height), routing 3 pt below it, then automation, pan, fader (what is left), record row, mute row.
  h.a.values.I_PANMODE=5
  at(86,525);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.I_RECMODE,3,3,24,24);box(k.I_RECINPUT,27,3,54,24)
  box(k.fx1,3,30,78,16)
  box(k.IO,3,138,24,24);box(k.FX,30,138,24,24);box(k.I_FXEN,57,138,24,24);box(k.I_AUTOMODE,3,165,24,24)
  box(k.D_PAN,3,192,36,36);box(k.D_WIDTH,45,192,36,36)
  box(k.D_VOL,3,231,24,185);box(k.meter,30,231,51,185)
  box(k.INFX,3,419,24,24);box(k.I_RECARM,30,419,24,24);box(k.I_RECMON,57,419,24,24)
  box(k.B_MUTE,3,446,24,24);box(k.I_SOLO,30,446,24,24);box(k.B_PHASE,57,446,24,24);box(k.name,3,473,78,24)
  assert(k.D_VOL.bottom-k.D_VOL.top==185-28)
  -- The track's colour is the number pill's fill, nothing else (the host's stand-in colour is 204,179,49); a plain track gets the theme's grey.
  local function fills(r,gg,b)
    local out,cur={}
    for _,c in ipairs(g.calls) do
      if c[1]=='set' then cur=c elseif c[1]=='rect' and cur and math.abs(cur[2]*255-r)<1 and math.abs(cur[3]*255-gg)<1 and math.abs(cur[4]*255-b)<1 then out[#out+1]=c end
    end
    return out
  end
  local f=fills(150,150,150);eq(#f,1);eq(f[1][3],500*2);eq(f[1][4],78*2)       -- selected, no colour: the pill's grey
  h.GetTrackColor=function() return 1 end;at(86,525)
  f=fills(204,179,49);eq(#f,1);eq(f[1][3],500*2);eq(#fills(204,179,49),1)
  h.GetTrackColor=function() return 0 end
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip; the script's own rules decide what is shown.
  for _,hgt in ipairs({340,409,454,600}) do
    for _,w in ipairs({80,86,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'I_RECMODE','I_RECINPUT','fx1','output','INFX','I_RECARM','I_RECMON','B_MUTE','I_SOLO','B_PHASE','name','D_VOL','meter'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        if mode==6 then eq(k.D_PAN,nil) end
        local order={}
        for _,id in ipairs(ids) do
          if k[id] then order[#order+1]=k[id] else assert(id:match('^D_') and hgt<400,id..' missing at '..w..'x'..hgt) end -- only the pan row may be dropped, by the script's own rule
        end
        for _,id in ipairs({'FX','I_FXEN','IO','I_AUTOMODE'}) do if k[id] then order[#order+1]=k[id] end end
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt) -- inserts, sends and the pinned master send
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.h>=40,'fader too short at '..hgt)
      end
    end
  end
  h.a.values.I_PANMODE=3
  -- Over 420 pt the racks' box is a fifth of the height (the script's own rule).
  -- Below that limit the theme drops the box; the Inspector keeps it (a fifth of the height, at least 3 rows) and the fader gives up the room.
  at(86,409);assert(v.fx_box.rows+v.send_box.rows+1>=4);assert(math.abs(v.hits.IO.y-(30+409/5+3))<.01);box(v.hits.fx1,3,30,78,16)
  assert(v.hits.D_VOL.h>=80);assert(v.hits.fx1.action and v.hits.output.action)
  at(86,340);assert(v.fx_box.rows+v.send_box.rows+1>=3);box(v.hits.fx1,3,30,78,16);assert(v.hits.output.y+16<=30+340/5+.01)
  local b0=#h.writes;g.mouse_x,g.mouse_y=0,0;v.hits.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')  -- shift-click bypasses the insert
  at(86,454);box(v.hits.fx1,3,30,78,16);assert(math.abs(v.hits.IO.y-(30+454/5+3))<.01)
  at(86,600);assert(math.abs(v.hits.IO.y-(30+600/5+3))<.01)
  -- Width beyond the native 86 pt goes to the right-hand columns and the meter; the left column stays put.
  at(96,525);k=v.hits
  box(k.B_MUTE,3,446,24,24);box(k.I_SOLO,35,446,24,24);box(k.B_PHASE,67,446,24,24);box(k.meter,30,231,61,185);box(k.I_FXEN,67,138,24,24)
  -- Master as the output strip: no input, arm, polarity or name rows, a mono switch beside automation, the mute pair centred.
  v.options.output_strip=true;at(172,525);k=v.hits
  assert(k['out:B_MUTE'] and k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:D_PAN'] and k['out:I_AUTOMODE'] and k['out:D_VOL'])
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
  local mo=k['out:MONO'];assert(mo and math.abs(mo.y-k['out:I_AUTOMODE'].y)<.01 and mo.x>k['out:I_AUTOMODE'].x+24)
  local mu,so=k['out:B_MUTE'],k['out:I_SOLO'];assert(math.abs(mu.y-446)<.01 and math.abs(so.x-mu.x-27)<.01 and mu.x>86+10)
  assert(math.abs(k['out:IO'].y-(30+525/3+3))<.01) -- its box is a third of the height
  assert(math.abs(mu.x-(86+16))<.01,'measured: the native pair starts 16 pt into the strip');eq(k['out:D_WIDTH'],nil)
  h.master.values.I_PANMODE=5;at(172,525);k=v.hits   -- the master's second knob (width) in stereo pan, as in the native mixer
  box(k['out:D_PAN'],86+2,262,36,36);box(k['out:D_WIDTH'],86+44,262,36,36);h.master.values.I_PANMODE=nil
  -- Click through to the model.
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Light draws the same rows from the same script.
  local t2=assert(Theme.resolve(home..'nvk_THEME_Light.ReaperThemeZip',env))
  local v2=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t2,{output_strip=false})
  g.ext_retina=2;g.w=172;g.h=1050;g.blits={};v2:frame();eq(#v2.bitmaps.missing,0);box(v2.hits.D_VOL,3,231,24,185)
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('set mcpLargeButtonWidth%s+%+ %* scale 48','set mcpLargeButtonWidth + * scale 49')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('Horizon (Dark and Light): lists from the top, rows from the bottom, the meter and fader taking what is left, one script for both editions', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/horizon',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  -- Dark and Light ship the same rtconfig.txt; recognition reads the script, never the file name.
  for _,name in ipairs({'Horizon_Dark_Theme.ReaperThemeZip','Horizon_Dark_Theme.ReaperTheme','Horizon_Theme.ReaperThemeZip'}) do
    local t=assert(Theme.resolve(home..name,env),name);eq(t.layout,'horizon');eq(t.row_height,10);eq(t.font,'Arimo')
  end
  local theme=assert(Theme.resolve(home..'Horizon_Dark_Theme.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 62 pt wide, 527 pt tall, stereo pan (every box measured against it).
  h.a.values.I_PANMODE=5
  at(62,527);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.FX,4,4,53,9);box(k.I_FXEN,49,4,8,9);box(k.fx1,3,13.5,53.5,10);box(k.IO,4,167,53,9)
  box(k.D_PAN,10.75,178,20,20);box(k.D_WIDTH,30.75,178,20,20)
  box(k.D_VOL,30.5,211,26.5,163.5);box(k.meter,6.5,213.5,21.5,158.5)
  box(k.I_RECINPUT,2,389,57,16);box(k.INFX,2,405,12,16);box(k.I_RECMODE,12,405,47,16)
  box(k.B_PHASE,10,423,20,20);box(k.I_AUTOMODE,32,423,20,20);box(k.I_RECARM,10,445,21,20);box(k.I_RECMON,31,445,21,20)
  box(k.B_MUTE,10,467,21,20);box(k.I_SOLO,31,467,21,20);box(k.name,2,489,57,20)
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip; the racks stay clickable at every height.
  for _,hgt in ipairs({340,409,454,600}) do
    for _,w in ipairs({62,86,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL','meter','IO','FX'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt);order[#order+1]=k[id] end
        if mode==6 then eq(k.D_PAN,nil) end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.h>=40,'fader too short at '..hgt)
      end
    end
  end
  h.a.values.I_PANMODE=5
  -- A short strip gives the input rows up (the fader gives way first); the racks and mute/solo stay.
  at(62,340);assert(v.hits.I_RECINPUT==nil and v.hits.I_RECARM==nil and v.hits.B_MUTE and v.hits.fx1.action)
  local b0=#h.writes;g.mouse_x,g.mouse_y=0,0;v.hits.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  local vh=v.hits.D_VOL.h;at(62,600);assert(v.hits.I_RECINPUT and v.hits.I_RECARM and v.hits.D_VOL.h>vh)
  -- Wider strips share the extra width between the meter and the fader; the bottom rows stay centred.
  at(96,527);k=v.hits;assert(k.meter.w>21.5+10 and k.D_VOL.w>26.5+10);assert(math.abs((k.B_MUTE.x+k.I_SOLO.x+21)/2-96/2)<1.01)
  -- Master as the output strip: no input, arm or polarity, a mono switch in the polarity place, the same rows otherwise.
  v.options.output_strip=true;at(172,527);k=v.hits
  assert(k['out:B_MUTE'] and k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:D_PAN'] and k['out:I_AUTOMODE'] and k['out:D_VOL'])
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
  box(k['out:MONO'],108,445,20,20);box(k['out:I_AUTOMODE'],130,445,20,20);box(k['out:B_MUTE'],108,467,21,20);box(k['out:I_SOLO'],129,467,21,20)
  assert(k['out:D_VOL'].h>k.D_VOL.h,'the master has no input or record rows, so its fader is taller')
  -- Click through to the model.
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Light draws the same rows from the same script.
  local t2=assert(Theme.resolve(home..'Horizon_Theme.ReaperThemeZip',env))
  local v2=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t2,{output_strip=false})
  g.ext_retina=2;g.w=124;g.h=1054;g.blits={};v2:frame();eq(#v2.bitmaps.missing,0);box(v2.hits.D_VOL,30.5,211,26.5,163.5)
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('set idx_size(%s+)%* scale 16','set idx_size%1* scale 17')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('WT Imperial V5: the script\'s blocks from the top over a fader that takes what is left, a 400 pt group hung from the bottom, centred in wider strips', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/imperial',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  for _,name in ipairs({'WT_Imperial_V5_WIPsnapshot_build.ReaperThemeZip','WT_Imperial_V5_WIPsnapshot_build.ReaperTheme'}) do
    local t=assert(Theme.resolve(home..name,env),name);eq(t.layout,'imperial');eq(t.row_height,14)
  end
  for _,name in ipairs({'WT_Imperial.ReaperThemeZip','Imperial_LCS-mod-dark_v3.ReaperThemeZip'}) do -- the siblings write other rectangles: their own layout
    eq(assert(Theme.resolve(home..name,env),name).layout,'imperial2')
  end
  local theme=assert(Theme.resolve(home..'WT_Imperial_V5_WIPsnapshot_build.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 94 pt wide, 1092 pt tall (every box measured against it and the script).
  at(94,1092);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.meter,6,6,38,88);box(k.I_RECINPUT,4,100,85,11);box(k.IO,18,138,16,16);box(k.INFX,61,135,21,21)
  box(k.I_AUTOMODE,9,172,76,29);box(k.FX,10,201,73,38);box(k.I_FXEN,66,210,16,16);box(k.fx1,10,248,74,14)
  box(k.I_RECARM,50,511,34,22);box(k.I_RECMON,16,545,21,21);box(k.I_RECMODE,8,566,77,34);box(k.D_PAN,26,624,42,42)
  box(k.name,0,694,94,18);box(k.I_SOLO,47,725,35,35);box(k.D_VOL,22,774,30,306);box(k.B_PHASE,71,790,14,14);box(k.B_MUTE,71,826,14,14)
  -- The script's own height: the racks' box gives way to a fader 18 pt shorter (three rows are the floor).
  at(94,874);k=v.hits;box(k.I_AUTOMODE,9,172,76,22);box(k.FX,10,194,73,32);box(k.D_VOL,22,574,30,288);box(k.name,0,494,94,18)
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip; rack rows, pan, name, mute, solo and the fader stay at every height.
  for _,hgt in ipairs({340,409,454,600,874}) do
    for _,w in ipairs({86,94,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','B_PHASE','name','D_VOL'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        for _,id in ipairs({'meter','I_RECINPUT','INFX','IO','I_AUTOMODE','FX','I_RECARM','I_RECMON','I_RECMODE'}) do if k[id] then ids[#ids+1]=id end end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt);order[#order+1]=k[id] end
        if mode==6 then eq(k.D_PAN,nil) end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.h>=90,'fader too short at '..hgt)
        assert(math.abs((k.B_MUTE.x+14/2)-(w-94)/2-78)<.01,'the 94 pt arrangement is centred at '..w)
      end
    end
  end
  -- A short strip gives the blocks above the racks up (the fader gives way first); the racks, pan, name, solo and mute stay.
  h.a.values.I_PANMODE=3;at(94,340);k=v.hits
  assert(k.I_RECARM==nil and k.I_RECINPUT==nil and k.meter==nil and k.I_AUTOMODE==nil and k.FX==nil and k.B_MUTE and k.fx1.action)
  local vh=k.D_VOL.h;local b0=#h.writes;g.mouse_x,g.mouse_y=0,0;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  at(94,600);assert(v.hits.I_RECINPUT and v.hits.FX and v.hits.D_VOL.h>vh)
  at(94,1092);assert(v.hits.I_RECARM and v.hits.I_RECMODE and v.hits.I_AUTOMODE.h==29)
  -- Master as the output strip: no input, arm, record mode, polarity or name; a mono switch and solo, the same rows otherwise.
  v.options.output_strip=true;h.a.values.I_PANMODE=3;at(188,874);k=v.hits
  assert(k['out:B_MUTE'] and k['out:I_SOLO'] and k['out:IO'] and k['out:FX'] and k['out:D_PAN'] and k['out:I_AUTOMODE'] and k['out:D_VOL'] and k['out:MONO'] and k['out:meter'])
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
  box(k['out:MONO'],108,505,42,51);box(k['out:I_SOLO'],151,507,35,35)
  assert(k['out:D_VOL'].h>=k.D_VOL.h,'the master has no record rows, so its fader is at least as tall')
  for _,w in ipairs({86,96,120}) do -- the master's rows stay inside its strip and clear of each other at every width
    at(w*2,454);k=v.hits;local ids={'out:MONO','out:I_SOLO','out:D_VOL','out:B_MUTE','out:D_PAN','out:fx1'}
    for i,id in ipairs(ids) do local a=assert(k[id],id..' missing');assert(a.x>=w-.01 and a.x+a.w<=w*2+.01,id..' leaves its strip at '..w)
      for j=i+1,#ids do local b=k[ids[j]];assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w) end end
  end
  -- Click through to the model.
  v.options.output_strip=false;at(94,874)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('set mcp.solo(%s+)%[47 507 35 35','set mcp.solo%1[47 508 35 35')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('Older Imperial siblings (WT Imperial, Imperial LCS-mod dark): one layout on two sets of numbers, a printed background cut into bands, blocks dropping on short strips, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/imperial2',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  local specs={
    {key='wt',file='WT_Imperial',row=14,w=94,
     edits={'set mcp.solo(%s+)%[47 507 35 35','set mcp.solo%1[47 508 35 35','set master.mcp.mono(%s+)%[14 505 42 58','set master.mcp.mono%1[14 506 42 58'},
     native=function(k) -- the script's rectangles on the 94 x 874 design, bottom ones hung 220 pt lower (the screenshot's 1094 pt strip)
       box(k.meter,9,7,24,100);box(k.I_RECINPUT,44,98,40,10);box(k.IO,17,137,18,23);box(k.INFX,60,135,21,24);box(k.I_AUTOMODE,12,183,12,12);box(k.FX,11,211,21,24)
       box(k.I_FXEN,66,213,18,23);box(k.fx1,11,253,72,14);box(k.I_RECARM,50,513,34,22);box(k.I_RECMON,16,548,21,24);box(k.I_RECMODE,32,579,22,21)
       box(k.D_PAN,29,629,36,36);box(k.name,21,695,72,20);box(k.I_SOLO,47,727,35,35);box(k.B_PHASE,71,792,14,14);box(k.B_MUTE,71,828,14,14);box(k.D_VOL,22,776,30,306) end,
     rows={12,3},
     m5=function(k) box(k.D_PAN,18,620,58,12);box(k.D_WIDTH,18,667,58,12) end,
     m6=function(k) box(k.D_DUALPANL,12,637,27,27);box(k.D_DUALPANR,53,637,27,27) end,
     at874=function(k) box(k.I_AUTOMODE,12,183,12,12);box(k.FX,11,211,21,24);box(k.fx1,11,253,72,14);box(k.D_PAN,29,445,36,36);box(k.name,21,511,72,20);box(k.D_VOL,22,592,30,270);box(k.I_SOLO,47,543,35,35) end,
     master=function(k) box(k['out:meter'],138,21,78,131);box(k['out:IO'],206,579,18,23);box(k['out:I_AUTOMODE'],142,183,12,12);box(k['out:FX'],136,211,21,24)
       box(k['out:fx1'],132,253,89,14);box(k['out:D_PAN'],158,629,36,36);box(k['out:MONO'],132,725,42,51);box(k['out:I_SOLO'],182,727,35,35);box(k['out:B_MUTE'],200,828,14,14);box(k['out:D_VOL'],143,776,30,306) end},
    {key='lcs',file='Imperial_LCS-mod-dark_v3',row=12,w=70,
     edits={'set mcp.solo(%s+)%[40 507 24 24','set mcp.solo%1[40 508 24 24','set master.mcp.mono(%s+)%[64 506 42 56','set master.mcp.mono%1[64 507 42 56'},
     native=function(k) -- the base layout (70 pt strip, the unnamed layout REAPER shows as Default), rack following the strip's width
       box(k.meter,11,7,50,100);box(k.I_RECINPUT,7,493,53,9);box(k.IO,5,137,18,22);box(k.INFX,52,133,15,15);box(k.I_AUTOMODE,15,159,40,12);box(k.FX,2,174,21,24)
       box(k.I_FXEN,49,176,18,23);box(k.fx1,4,215,60,12);box(k.I_RECARM,30,523,34,22);box(k.I_RECMON,8,524,14,14);box(k.I_RECMODE,24,562,22,21)
       box(k.D_PAN,17,603,36,36);box(k.name,0,695,70,20);box(k.I_SOLO,40,727,24,24);box(k.B_PHASE,46,674,14,14);box(k.B_MUTE,5,727,24,24);box(k.D_VOL,20,776,30,306) end,
     rows={16,5},
     m5=function(k) box(k.D_PAN,6,605,58,12);box(k.D_WIDTH,6,640,58,12) end,
     m6=function(k) box(k.D_DUALPANL,6,608,27,27);box(k.D_DUALPANR,37,608,27,27) end,
     at874=function(k) box(k.I_AUTOMODE,15,159,40,12);box(k.FX,2,174,21,24);box(k.fx1,4,215,60,12);box(k.D_PAN,17,383,36,36);box(k.name,0,475,70,20);box(k.D_VOL,20,556,30,306);box(k.I_SOLO,40,507,24,24) end,
     master=function(k) box(k['out:meter'],138,21,78,131);box(k['out:IO'],206,579,18,23);box(k['out:I_AUTOMODE'],153,183,50,12);box(k['out:FX'],136,211,21,24)
       box(k['out:fx1'],132,253,89,12);box(k['out:D_PAN'],158,628,36,36);box(k['out:MONO'],182,726,42,50);box(k['out:B_MUTE'],132,728,35,33);box(k['out:D_VOL'],143,776,30,306);eq(k['out:I_SOLO'],nil) end},
  }
  for _,spec in ipairs(specs) do
    for _,ext in ipairs({'.ReaperThemeZip','.ReaperTheme'}) do
      local t=assert(Theme.resolve(home..spec.file..ext,env),spec.file..ext);eq(t.layout,'imperial2');eq(t.imp2,spec.key);eq(t.row_height,spec.row)
    end
    local theme=assert(Theme.resolve(home..spec.file..'.ReaperThemeZip',env))
    local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
    local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
    -- The native screenshot's strip: its width, 1094 pt tall, balance pan; every box is the script's rectangle (the rack's rows 14 or 12 pt).
    h.a.values.I_PANMODE=3;at(spec.w,1094);eq(spec.file..':'..table.concat(v.bitmaps.missing,','),spec.file..':');spec.native(v.hits);eq(v.fx_box.rows,spec.rows[1]);eq(v.send_box.rows,spec.rows[2])
    h.a.values.I_PANMODE=5;at(spec.w,1094);spec.m5(v.hits)
    h.a.values.I_PANMODE=6;at(spec.w,1094);spec.m6(v.hits);eq(v.hits.D_PAN,nil)
    -- The script's own height: the racks give up 18 pt steps of the fader first; the blocks stay.
    h.a.values.I_PANMODE=3;at(spec.w,874);spec.at874(v.hits)
    -- Pan modes, widths and heights: nothing overlaps or leaves the strip; rack rows, pan, name, mute, solo, polarity and the fader stay at every height.
    for _,hgt in ipairs({340,409,454,600,874,1094}) do
      for _,w in ipairs({86,94,96,120}) do
        for _,mode in ipairs({3,5,6}) do
          h.a.values.I_PANMODE=mode;at(w,hgt);local k=v.hits
          local ids={}
          for id in pairs(k) do ids[#ids+1]=id end
          table.sort(ids)
          for _,id in ipairs({'fx1','output','B_MUTE','I_SOLO','B_PHASE','name','D_VOL'}) do assert(k[id],id..' missing at '..w..'x'..hgt) end
          for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do assert(k[id],id..' missing at '..w..'x'..hgt) end
          if mode==6 then eq(k.D_PAN,nil) end
          assert(k.fx1.action and k.output.action)
          assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
          for i,a in ipairs(ids) do local A=k[a]
            assert(A.x>=0 and A.x+A.w<=w+.01 and A.y>=0 and A.y+A.h<=hgt+.01,a..' leaves the strip at '..w..'x'..hgt)
            for j=i+1,#ids do local B=k[ids[j]]
              assert(A.x+A.w<=B.x+.01 or B.x+B.w<=A.x+.01 or A.y+A.h<=B.y+.01 or B.y+B.h<=A.y+.01,a..' overlaps '..ids[j]..' at '..w..'x'..hgt)
            end
          end
          assert(k.D_VOL.h>=90,'fader too short at '..hgt)
        end
      end
    end
    -- A short strip gives the blocks above the racks up (the fader gives way first); the racks, pan, name, mute and solo stay.
    h.a.values.I_PANMODE=3;at(spec.w,340);local k=v.hits
    assert(k.I_RECARM==nil and k.I_RECINPUT==nil and k.meter==nil and k.I_AUTOMODE==nil and k.FX==nil and k.IO==nil and k.B_MUTE and k.B_PHASE and k.fx1.action)
    local vh=k.D_VOL.h;local b0=#h.writes;g.mouse_x,g.mouse_y=0,0;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
    at(spec.w,600);assert(v.hits.I_RECINPUT and v.hits.FX and v.hits.meter and v.hits.IO and v.hits.D_VOL.h>vh and v.hits.I_RECARM==nil)
    at(spec.w,1094);assert(v.hits.I_RECARM and v.hits.I_RECMODE and v.hits.I_AUTOMODE and v.hits.I_RECMON)
    -- Wider strips centre the arrangement (the LCS rack follows the width); a narrower one crops it without nudging more than its edges.
    at(96,454);if spec.key=='wt' then box(v.hits.B_MUTE,72,296,14,14) else box(v.hits.fx1,4,6,86,12);box(v.hits.B_MUTE,18,195,24,24) end
    at(86,454);if spec.key=='wt' then box(v.hits.B_MUTE,67,296,14,14);box(v.hits.name,17,163,69,20) else box(v.hits.fx1,4,6,76,12);box(v.hits.B_MUTE,13,195,24,24) end
    -- The master as the output strip (its own 118 pt background): mono switch, mute, solo only where the theme's master has one; no input, arm, record mode, polarity.
    v.options.output_strip=true;h.a.values.I_PANMODE=3;at(188,454);k=v.hits
    for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','name'}) do eq(k['out:'..id],nil) end
    for _,id in ipairs({'B_MUTE','D_PAN','D_VOL','MONO','fx1'}) do assert(k['out:'..id],id..' missing on the master') end
    at(236,1094);spec.master(v.hits)
    h.a.values.I_PANMODE=5;h.master.values.I_PANMODE=5;at(236,1094);k=v.hits;assert(k['out:D_PAN'] and k['out:D_WIDTH'])     -- the Inspector's other pan modes use the track's rectangles beside the master's knob
    for _,w in ipairs({86,96,120}) do for _,hgt in ipairs({340,454,874}) do for _,mode in ipairs({3,5,6}) do
      h.a.values.I_PANMODE=mode;h.master.values.I_PANMODE=mode;at(w*2,hgt);k=v.hits
      local ids={};for id in pairs(k) do if id:sub(1,4)=='out:' then ids[#ids+1]=id end end;table.sort(ids)
      for _,id in ipairs({'out:MONO','out:B_MUTE','out:D_VOL','out:fx1'}) do assert(k[id],id..' missing at '..w..'x'..hgt) end
      for i,id in ipairs(ids) do local A=k[id];assert(A.x>=w-.01 and A.x+A.w<=w*2+.01 and A.y>=0 and A.y+A.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
        for j=i+1,#ids do local B=k[ids[j]];assert(A.x+A.w<=B.x+.01 or B.x+B.w<=A.x+.01 or A.y+A.h<=B.y+.01 or B.y+B.h<=A.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt..'/'..mode) end end
    end end end
    h.master.values.I_PANMODE=nil;h.a.values.I_PANMODE=3
    -- Click through to the model (the track's solo; the master's mono and mute go through the same hits).
    v.options.output_strip=false;at(spec.w,1094)
    local before=#h.writes
    local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
    eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
    -- Recognised by its script: one changed rectangle in the track's or in the master's statements falls back to the generic strip.
    local function changed(pattern,repl)
      local c,n=theme.rtconfig:gsub(pattern,repl,1);assert(n==1,pattern)
      os.execute('mkdir -p \"'..env.cache..'/changed\"')
      local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(c);f2:close()
      return assert(Theme.resolve(env.cache..'/changed',env)).layout
    end
    eq(changed(spec.edits[1],spec.edits[2]),'generic');eq(changed(spec.edits[3],spec.edits[4]),'generic')
  end
end)

test('Theme Adjuster values are read live only while following REAPER\'s theme', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local params={{'LayoutA-verboseMcp',1},{'selDot',0}}
  h.ThemeLayout_GetParameter=function(i) local p=params[i+1];if p then return p[1],'',p[2],0,0,1 end;return nil end
  local App=dofile('inspector/app.lua')
  local app=App.new(h,g);assert(app:start());app:frame()
  eq(app.theme.live['LayoutA-verboseMcp'],1);eq(app.theme.param('selDot',1),0);eq(app.theme.param('absent',5),5)
  assert(app:load_path(REAPERTIPS));app:frame();eq(app.theme.live,nil)   -- a pinned theme uses its own defaults
  app:stop();eq(#h.writes,0)
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

test('pan modes expose bounded independent controls and refuse stale mode writes', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local m=dofile('inspector/model.lua').new(h)
  local env={cache=h.cache..'/pan',mkdir=h.RecursiveCreateDirectory}
  local Theme=dofile('inspector/theme.lua');local View=dofile('inspector/view.lua')
  local dir=h.GetResourcePath()..'/ColorThemes/'
  for _,theme in ipairs({assert(Theme.resolve(REAPERTIPS)),assert(Theme.resolve(dir..'Reapertips Theme.ReaperThemeZip',env)),
    assert(Theme.resolve(dir..'Default_6.0.ReaperThemeZip',env)),assert(Theme.resolve(dir..'Default_7.0.ReaperThemeZip',env)),
    assert(Theme.resolve(dir..'Neptune VI.ReaperThemeZip',env))}) do
    h.a.values.I_PANMODE=5;h.a.values.D_WIDTH=.77;h.master.values.I_PANMODE=6
    h.master.values.D_DUALPANL=-1;h.master.values.D_DUALPANR=1
    g.w=368;g.h=1400
    local v=View.new(h,g,m,theme);v:frame();eq(v.snapshot.D_WIDTH,.77)
    local pan,width=v.hits.D_PAN,v.hits.D_WIDTH
    assert(pan and width and pan.x+pan.w<=width.x,theme.layout)
    local left,right=v.hits['out:D_DUALPANL'],v.hits['out:D_DUALPANR']
    assert(left and right and left.w>left.h and left.y+left.h<=right.y,theme.layout)
    eq(v.hits['out:D_PAN'],nil)
    g.mouse_x=(width.x+width.w/2)*2;g.mouse_y=(width.y+5)*2;g.mouse_cap=1;v:frame()
    g.mouse_x=g.mouse_x-10;v:frame();g.mouse_cap=0;v:frame()
    assert(math.abs(h.a.values.D_WIDTH-.67)<1e-8);eq(h.a.values.D_PAN,0)
    g.mouse_x=(left.x+left.w/2)*2;g.mouse_y=(left.y+left.h/2)*2;g.mouse_cap=1;v:frame()
    g.mouse_x=g.mouse_x+left.w;v:frame();assert(h.master.values.D_DUALPANL>-.2);eq(h.master.values.D_DUALPANR,1)
    h.master.values.I_PANMODE=5;local n=#h.writes
    g.mouse_x=g.mouse_x+10;v:frame();eq(#h.writes,n);eq(v.drag,nil)
    g.mouse_cap=0;v:frame()
    assert(m:set(v.snapshot,'D_WIDTH',-4));eq(h.a.values.D_WIDTH,-1)
    assert(not m:set(v.snapshot,'D_DUALPANR',0))
  end
end)

test('Default 7 derivatives are detected by normal mixer structure', function()
  local h=dofile('tests/synthetic.lua').host();local Theme=dofile('inspector/theme.lua')
  local env={cache=h.cache..'/d7-derivatives',mkdir=h.RecursiveCreateDirectory}
  for _,name in ipairs({'Default_7.0_LCS_Flat-Anti-Theme.ReaperThemeZip','Default_7.0_WT_TheAntiTheme.ReaperTheme',
    'Default_7.0_WT_TheAntiTheme_custom.ReaperTheme','Default_7_Dark_7.ReaperTheme',
    'LCS_Flat-7.ReaperThemeZip','MK_Colored_Stripes_v5.3.ReaperThemeZip'}) do
    local theme=assert(Theme.resolve(h.GetResourcePath()..'/ColorThemes/'..name,env));assert(theme.layout=='default7',name)
  end
end)

test('Default 7 mixer colours follow simple aliases without overriding direct settings', function()
  local h=dofile('tests/synthetic.lua').host();local Theme=dofile('inspector/theme.lua')
  local env={cache=h.cache..'/bg-alias',mkdir=h.RecursiveCreateDirectory};local dir=h.GetResourcePath()..'/ColorThemes/'
  local mk=assert(Theme.resolve(dir..'MK_Colored_Stripes_v5.3.ReaperThemeZip',env))
  local stock=assert(Theme.resolve(dir..'Default_7.0.ReaperThemeZip',env))
  eq(stock.param('mcpBgColR',-1),129)
  for _,key in ipairs({'mcpBgColR','mcpBgColG','mcpBgColB'}) do eq(mk.param(key,-1),51) end
  mk.live={tcpBgColAll=76,mcpBgColG=0}
  eq(mk.param('mcpBgColR',-1),76);eq(mk.param('mcpBgColG',-1),0);eq(mk.param('mcpBgColB',-1),76)
  local d=env.cache..'/fixture';env.mkdir(d)
  local f=assert(io.open(d..'/rtconfig.txt','w'));f:write([[
set mcpBgColR loop
set loop mcpBgColR
set mcpBgColG bright
set mcpBgColG + bright 4
set mcpBgColB bright
define_parameter mcpBgColB 'Direct blue' 19 0 255
define_parameter bright 'Brightness' 51 0 255
]],stock.rtconfig:gsub('\ndefine_parameter mcpBgCol[RGB][^\r\n]*',''));f:close()
  local sample=assert(Theme.resolve(d))
  eq(sample.layout,'default7');eq(sample.param('mcpBgColR',-1),-1)
  eq(sample.param('mcpBgColG',-1),-1)
  eq(sample.param('mcpBgColB',-1),19)
end)

test('stock themes request their own font and draw Default 7 pan cap without enlargement', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua');local View=dofile('inspector/view.lua')
  local env={cache=h.cache..'/pan-art',mkdir=h.RecursiveCreateDirectory};local dir=h.GetResourcePath()..'/ColorThemes/'
  local v=View.new(h,g,dofile('inspector/model.lua').new(h),assert(Theme.resolve(dir..'Default_6.0.ReaperThemeZip',env)))
  g.w=184;v:frame()
  local function font(face) for _,c in ipairs(g.calls) do if c[1]=='setfont' and c[2]==1 and c[3]==face then return true end end end
  assert(font('Calibri'))
  g.calls={};g.blits={};v.theme=assert(Theme.resolve(dir..'Default_7.0.ReaperThemeZip',env));v:frame()
  assert(font('Inter'))
  local slot=v.bitmaps.cache.tcp_pan_knob_small.slot;local found=false
  for _,b in ipairs(g.blits) do if b[1]==slot then found=true;eq(b[6],b[10]);eq(b[7],b[11]) end end
  assert(found)
  assert(v.bitmaps.cache.tcp_pan_knob_stack,'stock Default 7 uses the theme marker stack')
  h.a.values.I_PANMODE=5;h.a.values.D_WIDTH=1;v:frame()
  assert(v.bitmaps.cache.mcp_width_knob_small,'the stereo width cap has distinct art')
end)

test('Default 7 family draws theme pan cap and value-indexed marker without a generated line', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua');local View=dofile('inspector/view.lua')
  local env={cache=h.cache..'/pan-frames',mkdir=h.RecursiveCreateDirectory}
  for _,item in ipairs({{'Default_7_Dark_7.ReaperTheme',25},{'Default_7.0_WT_TheAntiTheme.ReaperTheme',41},
    {'Default_7.0_LCS_Flat-Anti-Theme.ReaperThemeZip',41},{'Default_7.0_WT_TheAntiTheme_custom.ReaperTheme',41}}) do
    local theme=assert(Theme.resolve(h.GetResourcePath()..'/ColorThemes/'..item[1],env))
    local v=View.new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
    g.w=184;g.h=1400
    for _,mode in ipairs({3,5}) do
      h.a.values.I_PANMODE=mode;h.a.values.D_WIDTH=1
      for _,p in ipairs({-1,0,1}) do
        local pointers=0;v.pointer=function() pointers=pointers+1 end
        h.a.values.D_PAN=p;g.blits={};v:frame()
        local cap=assert(v.bitmaps.cache.tcp_pan_knob_small,item[1]..': cap')
        local stack=assert(v.bitmaps.cache.tcp_pan_knob_stack,item[1]..': marker stack')
        local drawn=false;local frame=math.floor((p+1)*(item[2]-1)/2+.5)
        for _,b in ipairs(g.blits) do
          if b[1]==stack.slot then eq(b[5],frame*40);eq(b[6],40);eq(b[7],40);eq(b[10],40);eq(b[11],40);drawn=true end
        end
        assert(drawn and cap.slot<stack.slot);eq(pointers,0)
      end
    end
  end
  eq(#h.writes,0)
end)

test('stereo width uses theme frames and paints shared backing before the pan face', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  local Theme=dofile('inspector/theme.lua');local View=dofile('inspector/view.lua')
  local env={cache=h.cache..'/width-frames',mkdir=h.RecursiveCreateDirectory};local dir=h.GetResourcePath()..'/ColorThemes/'
  g.w=188;g.h=1500;h.a.values.I_PANMODE=5
  for _,case in ipairs({{'Default_7.0.ReaperThemeZip','tcp_wid_knob_stack',25,true},
    {'LCS_Flat-7.ReaperThemeZip','mcp_wid_knob_stack',35},
    {'MK_Colored_Stripes_v5.3.ReaperThemeZip','mcp_wid_knob_stack',35},
    {'Reapertips Theme_Custom2.ReaperTheme','tcp_wid_knob_stack',73}}) do
    local theme=assert(Theme.resolve(dir..case[1],env))
    local v=View.new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
    for _,w in ipairs({-1,0,.33,1}) do
      g.blits={};h.a.values.D_WIDTH=w;v:frame()
      local a=assert(v.bitmaps.cache[case[2]],case[1]..': width stack')
      local marker,back,pan
      for i,b in ipairs(g.blits) do
        if b[1]==a.slot then marker=i;eq(b[5],a.y+math.floor((w+1)*(case[3]-1)/2+.5)*a.w) end
        if case[4] then
          if b[1]==v.bitmaps.cache.mcp_width_knob_small.slot then back=i end
          if b[1]==v.bitmaps.cache.tcp_pan_knob_small.slot then pan=i end
        end
      end
      assert(marker,case[1]..': width frame drawn')
      if case[4] then assert(back<pan and pan<marker,'backing must not cover the pan cap') end
    end
  end
  eq(#h.writes,0)
end)

test('dual-pan track refuses balance writes at model boundary', function()
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

test('ReaTools (Classic, Dark, DarkBlack): the script\'s 80 pt strip on a printed background hung from the bottom, racks kept at three rows by cutting rows from it, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/reatools',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  for _,ed in ipairs({'Classic','Dark','DarkBlack'}) do -- the editions' scripts share the geometry; only colours and art differ
    local t=assert(Theme.resolve(home..'ReaTools '..ed..' V2.49.2.ReaperThemeZip',env),ed);eq(t.layout,'reatools');eq(t.row_height,18)
    eq(assert(Theme.resolve(home..'ReaTools '..ed..' V2.49.2.ReaperTheme',env),ed).layout,'reatools')
  end
  local theme=assert(Theme.resolve(home..'ReaTools Dark V2.49.2.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 80 pt wide, 785 pt tall (the script's 957 pt design less 172 pt; every box measured against it and the script).
  at(80,785);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.fx1,3,20,73,18);box(k.send1,3,132,73,18);box(k.output,3,152,73,18);box(k.I_RECINPUT,5,192,69,18);box(k.I_RECMODE,5.75,210,55.25,17);box(k.INFX,61,210,12,17)
  box(k.I_AUTOMODE,5,245,69,17);box(k.FX,6,279,48,19);box(k.I_FXEN,54,276,21,28);box(k.D_PAN,23,304,34,36);box(k.I_RECMON,9,370,28,20);box(k.I_RECARM,41,370,28,20)
  box(k.I_SOLO,9,395,28,20);box(k.B_MUTE,41,395,28,20);box(k.D_VOL,12,422,28,235);box(k.meter,57,420.5,12.5,232);box(k.B_PHASE,22,670,31,26);box(k.name,4,697,73,15);box(k.IO,8,734,60,26)
  -- Stereo pan (a width knob) and dual pan (two bars of knobs): neither overlaps the other.
  h.a.values.I_PANMODE=5;at(80,785);k=v.hits;box(k.D_PAN,5,304,34,36);box(k.D_WIDTH,40,304,34,36)
  h.a.values.I_PANMODE=6;at(80,785);k=v.hits;box(k.D_DUALPANL,5,304,34,36);box(k.D_DUALPANR,40,304,34,36);eq(k.D_PAN,nil)
  -- Pan modes, widths and heights: nothing overlaps or leaves the strip; rack rows, pan, name, mute, solo and the fader stay at every height.
  for _,hgt in ipairs({340,409,454,600,785,957}) do
    for _,w in ipairs({86,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        for _,id in ipairs({'meter','I_RECINPUT','INFX','IO','I_AUTOMODE','FX','I_FXEN','I_RECARM','I_RECMON','I_RECMODE','B_PHASE'}) do if k[id] then ids[#ids+1]=id end end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt);order[#order+1]=k[id] end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt)
          end
        end
        assert(k.D_VOL.h>=90,'fader too short at '..hgt)
        assert(math.abs((k.B_MUTE.x+14)-(w-80)/2-55)<.01,'the 80 pt arrangement is centred at '..w) -- mute's left edge is 41 pt in
      end
    end
  end
  -- A short strip gives blocks up in the theme\'s own order (the fader first); the racks, pan, name, solo and mute stay, and a rack row acts.
  h.a.values.I_PANMODE=3;at(86,340);k=v.hits
  assert(k.I_RECARM==nil and k.I_RECINPUT==nil and k.I_AUTOMODE==nil and k.FX==nil and k.B_MUTE and k.D_PAN and k.fx1.action)
  local short=k.D_VOL.h;local b0=#h.writes;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  at(86,600);assert(v.hits.D_VOL.h>short);assert(v.hits.I_RECINPUT and v.hits.FX and v.hits.I_AUTOMODE and v.hits.D_VOL.h<235) -- 600 pt keeps every block and gives up fader only
  at(86,785);assert(v.hits.I_RECARM and v.hits.I_RECMODE and v.hits.I_AUTOMODE and v.hits.FX and v.hits.D_VOL.h==235)
  -- Master as the output strip: no input, arm, monitor, record mode, polarity or pan; a MONO switch, solo and mute, the same rows otherwise.
  v.options.output_strip=true;h.a.values.I_PANMODE=3;at(172,785);k=v.hits
  box(k['out:MONO'],95,209,68,17);box(k['out:I_AUTOMODE'],94,243.5,69,17);box(k['out:I_SOLO'],98,394,28,20);box(k['out:B_MUTE'],130,394,28,20);box(k['out:D_VOL'],91,421,28,235);box(k['out:IO'],98,732,60,27)
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','D_PAN','name'}) do eq(k['out:'..id],nil) end
  for _,hgt in ipairs({340,409,454,600,785}) do
    for _,w in ipairs({86,96,120}) do -- the master\'s rows stay inside its strip and clear of each other at every width and height
      at(w*2,hgt);k=v.hits;local ids={'out:MONO','out:I_SOLO','out:D_VOL','out:B_MUTE','out:fx1','out:output'}
      for i,id in ipairs(ids) do local a=k[id];if a then assert(a.x>=w-.01 and a.x+a.w<=w*2+.01 and a.y>=0 and a.y+a.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
        for j=i+1,#ids do local b=k[ids[j]];if b then assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt) end end end end
      assert(k['out:fx1'] and k['out:fx1'].action and k['out:B_MUTE'] and k['out:I_SOLO'] and k['out:D_VOL'],'master keeps its rack, mute, solo and fader at '..hgt)
    end
  end
  -- Click through to the model.
  v.options.output_strip=false;at(80,785)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('set mcp%.solo(%s+)%* scale %[9 567 28 20','set mcp.solo%1* scale [9 568 28 20')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)
test('paRt (Dark, Dimmed, Light): the script\'s 49 pt strip centred in wider ones, rows dropping from the bottom on short strips, the meter and fader taking what is left, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/part',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  for _,ed in ipairs({'Dark','Dimmed','Light'}) do -- one script, three sets of colours and art
    local t=assert(Theme.resolve(home..'paRt - '..ed..'.ReaperThemeZip',env),ed);eq(t.layout,'part');eq(t.row_height,17)
    assert(t.pt.track_bg and t.pt.select_bar and t.pt.zero,ed..' reads its own colours')
  end
  eq(assert(Theme.resolve(home..'paRt - Dark.ReaperTheme',env)).layout,'part')
  local theme=assert(Theme.resolve(home..'paRt - Dark.ReaperThemeZip',env))
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),theme,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 49 pt wide (48 and a 1 pt gap), 791 pt tall; every row measured against it (pixel columns and rows at 2 px per pt).
  at(49,791);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.fx1,5,4,40,17);box(k.I_RECINPUT,6,146.78,36,14);box(k.I_RECMODE,4,163.78,18,14);box(k.INFX,4,186.78,18,14);box(k.FX,4,203.78,21,14);box(k.I_FXEN,25,203.78,18,14)
  box(k.IO,4,226.78,18,14);box(k.B_PHASE,25,226.78,18,14);box(k.B_MUTE,4,243.78,18,14);box(k.I_SOLO,25,243.78,18,14);box(k.I_RECARM,4,266.78,18,14);box(k.I_RECMON,25,266.78,18,14)
  box(k.I_AUTOMODE,4,283.78,39,14);box(k.D_PAN,5,300.78,38,10);box(k.meter,5,327.78,16,413.22);box(k.D_VOL,28,326.78,12,415.22);box(k.name,0,773,48,18)
  -- Stereo pan (a width bar under the pan bar) and dual pan (two pan bars): neither overlaps the other.
  h.a.values.I_PANMODE=5;at(49,791);k=v.hits;box(k.D_PAN,5,300.78,38,10);box(k.D_WIDTH,5,313.78,38,10)
  h.a.values.I_PANMODE=6;at(49,791);k=v.hits;box(k.D_DUALPANL,5,300.78,38,10);box(k.D_DUALPANR,5,313.78,38,10);eq(k.D_PAN,nil)
  -- Heights, widths and pan modes: nothing overlaps or leaves the strip; the rack rows, pan, name, mute, solo and the fader stay at every height.
  for _,hgt in ipairs({340,409,454,600,791}) do
    for _,w in ipairs({86,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL','meter'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        for _,id in ipairs({'I_RECINPUT','INFX','IO','FX','I_FXEN','I_RECARM','I_RECMON','I_RECMODE','B_PHASE','I_AUTOMODE'}) do if k[id] then ids[#ids+1]=id end end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt);order[#order+1]=k[id] end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt..' mode '..mode)
          end
        end
        assert(k.D_VOL.h>=60,'fader too short at '..hgt)
        eq(k.B_MUTE.x,math.floor((w-1-39)/2)) -- the 39 pt rows are centred in the strip, 4 pt in on the native one
      end
    end
  end
  -- A short strip drops rows from the bottom up (automation first); the rack, mute, solo, pan, name and fader stay, and a rack row acts.
  h.a.values.I_PANMODE=3;at(86,340);k=v.hits
  assert(k.I_AUTOMODE==nil and k.I_RECARM==nil and k.B_MUTE and k.I_SOLO and k.D_PAN and k.name and k.D_VOL and k.fx1.action)
  local short=k.D_VOL.h;local b0=#h.writes;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  local kept=0;for _,hgt in ipairs({340,409,454,600,791}) do at(86,hgt);local n=0;for _,id in ipairs({'I_RECINPUT','I_RECMODE','INFX','FX','IO','B_MUTE','I_RECARM','I_AUTOMODE'}) do if v.hits[id] then n=n+1 end end;assert(n>=kept,'rows only come back as the strip grows');kept=n end
  at(86,791);assert(v.hits.I_RECARM and v.hits.I_RECMODE and v.hits.I_AUTOMODE and v.hits.INFX and v.hits.IO and v.hits.D_VOL.h>short)
  -- The master as the output strip: no input, arm, monitor, record mode, input FX, automation or name; FX, routing, a stereo/mono switch, mute and solo, the meter, the fader and two pan bars.
  v.options.output_strip=true;h.a.values.I_PANMODE=3;at(172,791);k=v.hits
  box(k['out:FX'],109,86.1,21,14);box(k['out:I_FXEN'],130,86.1,18,14);box(k['out:IO'],109,103.1,18,14);box(k['out:MONO'],130,103.1,18,14);box(k['out:B_MUTE'],109,120.1,18,14);box(k['out:I_SOLO'],130,120.1,18,14)
  for _,id in ipairs({'I_RECARM','I_RECMODE','I_RECMON','I_RECINPUT','INFX','B_PHASE','I_AUTOMODE','name'}) do eq(k['out:'..id],nil) end
  for _,hgt in ipairs({340,409,454,600,791}) do
    for _,w in ipairs({86,96,120}) do -- the master\'s rows stay inside its strip and clear of each other at every width and height
      at(w*2,hgt);k=v.hits;local ids={'out:MONO','out:I_SOLO','out:D_VOL','out:D_PAN','out:B_MUTE','out:FX','out:I_FXEN','out:IO','out:fx1','out:meter'}
      for i,id in ipairs(ids) do local a=k[id];assert(a,id..' missing at '..w..'x'..hgt);assert(a.x>=w-.01 and a.x+a.w<=w*2+.01 and a.y>=0 and a.y+a.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
        for j=i+1,#ids do local b=k[ids[j]];assert(b);assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt) end end
      assert(k['out:fx1'].action and k['out:D_VOL'].h>=60,'master keeps its rack and a fader at '..hgt)
    end
  end
  -- Click through to the model.
  v.options.output_strip=false;at(49,791)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed statement falls back to the generic strip.
  local changed,n=theme.rtconfig:gsub('(set VAL_mcp_h%s+)400','%1401')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)
test('Realogix: the script\'s 72 pt strip, racks kept at three rows by lowering the blocks above the fader, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/realogix',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  local t=assert(Theme.resolve(home..'Realogix.ReaperThemeZip',env));eq(t.layout,'realogix');eq(t.row_height,17)
  eq(assert(Theme.resolve(home..'Realogix.ReaperTheme',env)).layout,'realogix')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 72 pt wide, 805 pt tall (the script's 902 pt design less 97 pt), stereo pan: every box is the script's rectangle at that height.
  h.a.values.I_PANMODE=5;at(72,805);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.I_RECINPUT,5,306,50,18);box(k.INFX,55,306,16,19);box(k.FX,5,332,49,18);box(k.I_FXEN,54,332,14,18);box(k.I_AUTOMODE,5,358,70,18);box(k.IO,5,384,70,18)
  box(k.D_WIDTH,32,439,31,31);box(k.D_PAN,11,475,31,31);box(k.B_PHASE,44,536,22,20);box(k.D_VOL,2,553,29,181);box(k.meter,46,562,18,142)
  box(k.I_RECMON,33,713,15,18);box(k.I_RECARM,48,709,24,20);box(k.B_MUTE,6,740,30,20);box(k.I_SOLO,36,740,31,20);box(k.name,5,762,64,18)
  -- Balance pan is one knob; dual pan two knobs; below 800 pt stereo and dual pan are two bars.
  h.a.values.I_PANMODE=3;at(72,805);k=v.hits;assert(k.D_PAN and not k.D_WIDTH)
  h.a.values.I_PANMODE=6;at(72,805);k=v.hits;box(k.D_DUALPANL,11,475,31,31);box(k.D_DUALPANR,32,439,31,31);eq(k.D_PAN,nil)
  h.a.values.I_PANMODE=5;at(72,700);k=v.hits;box(k.D_PAN,1,365,72,19);box(k.D_WIDTH,1,385,72,19)
  -- Heights, widths and pan modes: nothing overlaps or leaves the strip; the rack rows, pan, name, mute, solo, polarity or arm and the fader stay at every height.
  for _,hgt in ipairs({340,409,423,424,454,534,575,600,633,723,785,805,900}) do
    for _,w in ipairs({86,96,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL','meter','I_RECARM','I_RECMON'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        for _,id in ipairs({'I_RECINPUT','INFX','FX','I_FXEN','I_AUTOMODE','IO','B_PHASE'}) do if k[id] then ids[#ids+1]=id end end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt..' mode '..mode);order[#order+1]=k[id] end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            if a.id~='meter' and b.id~='meter' then
              assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt..' mode '..mode)
            end
          end
        end
        assert(k.D_VOL.h>=100,'fader too short at '..hgt)
        eq(k.B_MUTE.x,6+(w-72)//2) -- the 72 pt arrangement is centred in a wider strip
      end
    end
  end
  -- A short strip lowers the blocks above the fader and then drops routing, automation, FX; the racks, pan, name, mute, solo and fader stay, and a rack row acts.
  h.a.values.I_PANMODE=3;at(86,340);k=v.hits
  assert(k.FX==nil and k.I_AUTOMODE==nil and k.B_MUTE and k.D_PAN and k.D_VOL and k.fx1.action)
  local short=k.D_VOL.h;local b0=#h.writes;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  at(86,805);assert(v.hits.I_RECINPUT and v.hits.FX and v.hits.I_AUTOMODE and v.hits.IO and v.hits.D_VOL.h==181 and v.hits.D_VOL.h>short)
  -- The master as the output strip: no input, arm, monitor, polarity or width; a mono switch in the arm slot; the rest as a track.
  v.options.output_strip=true;h.a.values.I_PANMODE=5;at(172,805);k=v.hits -- two strips need 172 pt: 86 each, the 72 pt arrangement 7 pt in
  box(k['out:MONO'],126,709,39,20);box(k['out:B_MUTE'],99,740,30,20);box(k['out:I_SOLO'],129,740,31,20);box(k['out:D_VOL'],95,553,29,181)
  for _,id in ipairs({'I_RECARM','I_RECMON','I_RECINPUT','INFX','B_PHASE','D_WIDTH','name'}) do eq(k['out:'..id],nil) end
  for _,hgt in ipairs({340,454,600,805}) do
    for _,w in ipairs({86,96,120}) do -- the master's rows stay inside its strip and clear of each other at every width and height
      at(w*2,hgt);k=v.hits;local ids={'out:MONO','out:I_SOLO','out:D_VOL','out:D_PAN','out:B_MUTE','out:fx1'} -- (the master's rack is inserts only)
      for i,id in ipairs(ids) do local a=k[id];assert(a,id..' missing at '..w..'x'..hgt);assert(a.x>=w-.01 and a.x+a.w<=w*2+.01 and a.y>=0 and a.y+a.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
        for j=i+1,#ids do local b=k[ids[j]];assert(b);assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt) end end
      assert(k['out:fx1'].action and k['out:D_VOL'].h>=100,'master keeps its rack and a fader at '..hgt)
    end
  end
  -- Click through to the model.
  v.options.output_strip=false;at(72,805)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip.
  local changed,n=t.rtconfig:gsub('set mcp%.solo(%s+)%[36 837 31 23','set mcp.solo%1[36 838 31 23')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

test('Default 3.0 and 4.0: the old stock strips, one layout on two geometries, racks kept at four rows, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/default34',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  local specs={
    {n=3,w=72,h=806,edit=function(rt) return rt:gsub('mcp_vupeakheight 4','mcp_vupeakheight 5') end,optional={},
     ref=function(k) -- the native strip (72 x 806 pt), balance pan: the measured rectangles
       box(k.B_MUTE,31,432.5,19.5,20);box(k.I_SOLO,50.5,432.5,20,20);box(k.name,4,455,63,15);box(k.B_PHASE,50.5,472.5,20,20);box(k.IO,50.5,492.5,20,20);box(k.I_AUTOMODE,50.5,512.5,20,20)
       box(k.FX,51.5,533.5,20,20);box(k.I_FXEN,50.5,553.5,20,12);box(k.I_RECARM,50.5,706.5,20,20);box(k.I_RECMON,50.5,726.5,20,20);box(k.I_RECMODE,50.5,746.5,20,20)
       box(k.D_VOL,2.5,472.5,22,292.5);box(k.D_PAN,9.5,769,53.5,16) end},
    -- (4.0's edit changes the first mute/solo rectangle, the default block's: the named layouts repeat it)
    {n=4,w=73,h=818,edit=function(rt) return rt:gsub('set mcp%.solo %+ mcp_column_anchor %[0 21 17 18','set mcp.solo + mcp_column_anchor [0 22 17 18',1) end,optional={'I_RECMODE','I_AUTOMODE','B_PHASE'},
     ref=function(k) -- the native strip (73 x 818 pt), balance pan: the script's rectangles at its 374 pt panel
       box(k.B_MUTE,48,549,17,18);box(k.I_SOLO,48,570,17,18);box(k.I_RECMON,48,591,17,12);box(k.I_RECMODE,48,603,17,22);box(k.I_AUTOMODE,48,628,17,26);box(k.B_PHASE,49,657,15,16)
       box(k.I_FXEN,3,447,23,14);box(k.FX,3,461,23,17);box(k.IO,30,447,39,31);box(k.D_PAN,4,509,30,30);box(k.D_VOL,9,563,17,228);box(k.I_RECARM,41,759,20,33) end},
  }
  for _,sp in ipairs(specs) do
    local t=assert(Theme.resolve(home..'Default_'..sp.n..'.0.ReaperThemeZip',env));eq(t.layout,'default34');eq(t.d34,sp.n);eq(t.row_height,14)
    eq(assert(Theme.resolve(home..'Default_'..sp.n..'.0.ReaperTheme',env)).layout,'default34')
    local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t,{output_strip=false})
    local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
    h.a.values.I_PANMODE=3;at(sp.w,sp.h);eq(#v.bitmaps.missing,0);sp.ref(v.hits)
    -- Stereo pan is two controls, dual pan two others; balance is one.
    h.a.values.I_PANMODE=5;at(sp.w,sp.h);assert(v.hits.D_PAN and v.hits.D_WIDTH and not v.hits.D_DUALPANL)
    h.a.values.I_PANMODE=6;at(sp.w,sp.h);assert(v.hits.D_DUALPANL and v.hits.D_DUALPANR and not v.hits.D_PAN)
    -- Heights, widths and pan modes: nothing overlaps or leaves the strip; the racks (four rows and a send), pan, name, mute, solo, arm and the fader stay.
    for _,hgt in ipairs({340,409,454,600,sp.h,900}) do
      for _,w in ipairs({86,96,120}) do
        for _,mode in ipairs({3,5,6}) do
          h.a.values.I_PANMODE=mode;at(w,hgt);local k=v.hits
          local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL','meter','I_RECARM','I_RECMON','FX','I_FXEN','IO'}
          for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
          for _,id in ipairs(sp.optional) do if k[id] then ids[#ids+1]=id end end
          local order={}
          for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt..' mode '..mode);order[#order+1]=k[id] end
          assert(k.fx1.action and k.output.action)
          assert(v.fx_box.rows+v.send_box.rows+1>=4,'racks keep four rows at '..hgt)
          for i,a in ipairs(order) do
            assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
            for j=i+1,#order do local b=order[j]
              if a.id~='meter' and b.id~='meter' and not (a.id=='D_VOL' or b.id=='D_VOL') then -- (the fader's hit box is its whole groove)
                assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt..' mode '..mode)
              end
            end
          end
          assert(k.D_VOL.h>=100,'fader too short at '..hgt)
        end
      end
    end
    -- Optional rows only come back as the strip grows (a taller strip never hides what a shorter one shows).
    h.a.values.I_PANMODE=3
    local kept=0;for _,hgt in ipairs({340,409,454,600,sp.h}) do at(86,hgt);local n=0;for _,id in ipairs({'I_RECMODE','I_AUTOMODE','B_PHASE','I_RECMON','FX','IO'}) do if v.hits[id] then n=n+1 end end;assert(n>=kept,'rows only come back as the strip grows');kept=n end
    at(86,340);local short=v.hits.D_VOL.h;local b0=#h.writes;v.hits.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
    at(86,sp.h);assert(v.hits.D_VOL.h>short,'the fader is shorter on a short strip')
    -- The master as the output strip: no arm, monitor, record mode, phase or solo; a mono switch; FX, routing, mute, pan, fader, meter and its inserts.
    v.options.output_strip=true;h.a.values.I_PANMODE=3
    for _,hgt in ipairs({340,409,454,600,sp.h}) do
      for _,w in ipairs({86,96,120}) do
        at(w*2,hgt);local k=v.hits;local ids={'out:MONO','out:B_MUTE','out:D_VOL','out:D_PAN','out:FX','out:IO','out:fx1','out:meter'}
        for _,id in ipairs({'I_RECARM','I_RECMON','I_RECMODE','B_PHASE','I_SOLO','name'}) do eq(k['out:'..id],nil) end
        for i,id in ipairs(ids) do local a=k[id];assert(a,id..' missing at '..w..'x'..hgt);assert(a.x>=w-.01 and a.x+a.w<=w*2+.01 and a.y>=0 and a.y+a.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
          for j=i+1,#ids do local b=k[ids[j]];assert(b);if id~='out:meter' and ids[j]~='out:meter' and id~='out:D_VOL' and ids[j]~='out:D_VOL' then assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt) end end end
        assert(k['out:fx1'].action and k['out:D_VOL'].h>=100,'master keeps its rack and a fader at '..hgt)
      end
    end
    -- Click through to the model.
    v.options.output_strip=false;at(sp.w,sp.h)
    local before=#h.writes
    local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
    eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
    -- Recognised by its own script: one changed statement or rectangle falls back to the generic strip.
    local changed,n=sp.edit(t.rtconfig)
    assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed'..sp.n..'\"')
    local f2=assert(io.open(env.cache..'/changed'..sp.n..'/rtconfig.txt','w'));f2:write(changed);f2:close()
    eq(assert(Theme.resolve(env.cache..'/changed'..sp.n,env)).layout,'generic')
  end
end)

test('Echolot (FeedTheCat mod): the script\'s 102 pt strip, racks kept at three rows by lowering the blocks above the fader, narrower and wider strips, the master as the output strip', function()
  local fake=dofile('tests/synthetic.lua');local h,g=fake.host(),fake.gfx()
  h.GetOS=function() return 'macOS-arm64' end
  local Theme=dofile('inspector/theme.lua')
  local home=os.getenv('HOME')..'/Library/Application Support/REAPER/ColorThemes/'
  local env={cache=h.cache..'/echolot',mkdir=function(p) os.execute('mkdir -p \"'..p..'\"') end}
  local t=assert(Theme.resolve(home..'Echolot_FTC.ReaperThemeZip',env));eq(t.layout,'echolot');eq(t.row_height,23)
  eq(assert(Theme.resolve(home..'Echolot_FTC.ReaperTheme',env)).layout,'echolot')
  local v=dofile('inspector/view.lua').new(h,g,dofile('inspector/model.lua').new(h),t,{output_strip=false})
  local function at(w,hgt) g.ext_retina=2;g.w=w*2;g.h=hgt*2;g.blits={};g.calls={};v:frame() end
  local function box(hit,x,y,w,hh) assert(hit,'missing box');assert(math.abs(hit.x-x)<.01,hit.id..' x '..hit.x);assert(math.abs(hit.y-y)<.01,hit.id..' y '..hit.y);assert(math.abs(hit.w-w)<.01,hit.id..' w '..hit.w);assert(math.abs(hit.h-hh)<.01,hit.id..' h '..hit.h) end
  -- The native screenshot's strip: 102 pt wide, 791 pt tall (the script's 702 pt design plus 89 pt), stereo pan: every box is the script's rectangle at that height.
  h.a.values.I_PANMODE=5;at(102,791);eq(#v.bitmaps.missing,0);local k=v.hits
  box(k.FX,22,2,74,16);box(k.I_FXEN,5,3,14,14);box(k.fx1,6,20,92,23);box(k.IO,4,451,94,16);box(k.B_PHASE,5,472,20,20);box(k.I_AUTOMODE,29,472,20,20)
  box(k.B_MUTE,5,496,20,20);box(k.I_SOLO,29,496,20,20);box(k.I_RECARM,53,496,20,20);box(k.I_RECMON,77,496,20,20)
  box(k.D_PAN,34,521,34,34);box(k.D_WIDTH,72,526,24,27);box(k.D_VOL,40,566,22,157);box(k.meter,68,576,26,127);box(k.name,6,741,90,16)
  -- Balance pan is one knob; dual pan two; width exists only in stereo pan.
  h.a.values.I_PANMODE=3;at(102,791);k=v.hits;assert(k.D_PAN and not k.D_WIDTH)
  h.a.values.I_PANMODE=6;at(102,791);k=v.hits;assert(k.D_DUALPANL and k.D_DUALPANR and not k.D_PAN)
  -- Heights, widths and pan modes: nothing overlaps or leaves the strip; the rack rows, pan, name, mute, solo, arm, monitor and the fader stay at every height.
  for _,hgt in ipairs({340,409,454,600,791,900}) do
    for _,w in ipairs({86,96,102,120}) do
      for _,mode in ipairs({3,5,6}) do
        h.a.values.I_PANMODE=mode;at(w,hgt);k=v.hits
        local ids={'fx1','output','B_MUTE','I_SOLO','name','D_VOL','meter','I_RECARM','I_RECMON'}
        for _,id in ipairs(mode==6 and {'D_DUALPANL','D_DUALPANR'} or mode==5 and {'D_PAN','D_WIDTH'} or {'D_PAN'}) do ids[#ids+1]=id end
        for _,id in ipairs({'FX','I_FXEN','IO','B_PHASE','I_AUTOMODE'}) do if k[id] then ids[#ids+1]=id end end
        local order={}
        for _,id in ipairs(ids) do assert(k[id],id..' missing at '..w..'x'..hgt..' mode '..mode);order[#order+1]=k[id] end
        assert(k.fx1.action and k.output.action)
        assert(v.fx_box.rows+v.send_box.rows+1>=3,'racks keep 3 rows at '..hgt)
        for i,a in ipairs(order) do
          assert(a.x>=0 and a.x+a.w<=w+.01 and a.y>=0 and a.y+a.h<=hgt+.01,a.id..' leaves the strip at '..w..'x'..hgt)
          for j=i+1,#order do local b=order[j]
            if a.id~='meter' and b.id~='meter' then
              assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,a.id..' overlaps '..b.id..' at '..w..'x'..hgt..' mode '..mode)
            end
          end
        end
        assert(k.D_VOL.h>=100,'fader too short at '..hgt)
      end
    end
  end
  -- A short strip lowers the blocks above the fader, then drops routing, polarity and automation (never the reverse as the strip grows); a rack row acts.
  h.a.values.I_PANMODE=3;at(86,340);k=v.hits
  assert(k.FX==nil and k.IO==nil and k.B_PHASE==nil and k.B_MUTE and k.D_PAN and k.D_VOL and k.fx1.action)
  local short=k.D_VOL.h;local b0=#h.writes;k.fx1.action(8);assert(#h.writes>b0,'a rack row acts on a short strip')
  local kept=0;for _,hgt in ipairs({340,409,454,600,791}) do at(86,hgt);local n=0;for _,id in ipairs({'FX','IO','B_PHASE','I_AUTOMODE'}) do if v.hits[id] then n=n+1 end end;assert(n>=kept,'rows only come back as the strip grows');kept=n end
  at(86,791);assert(v.hits.FX and v.hits.IO and v.hits.B_PHASE and v.hits.D_VOL.h==157 and v.hits.D_VOL.h>short)
  -- The master as the output strip (two strips need 172 pt): no phase, arm, monitor or name box; a mono switch; mute, solo, automation, pan, fader and its inserts.
  v.options.output_strip=true;h.a.values.I_PANMODE=3
  for _,hgt in ipairs({340,454,600,791}) do
    for _,w in ipairs({86,96,120}) do
      at(w*2,hgt);k=v.hits;local ids={'out:MONO','out:I_SOLO','out:D_VOL','out:D_PAN','out:B_MUTE','out:I_AUTOMODE','out:fx1'} -- (the master's rack is inserts only)
      for _,id in ipairs({'I_RECARM','I_RECMON','B_PHASE','name','output'}) do eq(k['out:'..id],nil) end
      for i,id in ipairs(ids) do local a=k[id];assert(a,id..' missing at '..w..'x'..hgt);assert(a.x>=w-.01 and a.x+a.w<=w*2+.01 and a.y>=0 and a.y+a.h<=hgt+.01,id..' leaves its strip at '..w..'x'..hgt)
        for j=i+1,#ids do local b=k[ids[j]];assert(b);assert(a.x+a.w<=b.x+.01 or b.x+b.w<=a.x+.01 or a.y+a.h<=b.y+.01 or b.y+b.h<=a.y+.01,id..' overlaps '..ids[j]..' at '..w..'x'..hgt) end end
      assert(k['out:fx1'].action and k['out:D_VOL'].h>=100,'master keeps its rack and a fader at '..hgt)
    end
  end
  -- Click through to the model.
  v.options.output_strip=false;h.a.values.I_PANMODE=5;at(102,791)
  local before=#h.writes
  local hit=v.hits.I_SOLO;g.mouse_x=(hit.x+5)*2;g.mouse_y=(hit.y+5)*2;g.mouse_cap=1;v:frame();g.mouse_cap=0;v:frame()
  eq(#h.writes,before+1);eq(h.writes[#h.writes][2],'I_SOLO')
  -- Recognised by its script: one changed rectangle falls back to the generic strip (as does the original edition's different script).
  local changed,n=t.rtconfig:gsub('(set mcp%.solo h<103 %[0%] h<224 %[29 )25','%126')
  assert(n==1);os.execute('mkdir -p \"'..env.cache..'/changed\"')
  local f2=assert(io.open(env.cache..'/changed/rtconfig.txt','w'));f2:write(changed);f2:close()
  eq(assert(Theme.resolve(env.cache..'/changed',env)).layout,'generic')
end)

for _, t in ipairs(tests) do
  local ok, err = xpcall(t[2], debug.traceback)
  if ok then passed = passed + 1; print('PASS '..t[1]) else print('FAIL '..t[1]..'\n'..err) end
end
print(('%d/%d offline tests passed'):format(passed,#tests))
os.exit(passed == #tests and 0 or 1)
