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
-- 80gray's mixer: a flat script (no macros) built from rows, with its colours written inline.
-- Editions differ only in those colours, so they are read here and the geometry is recognised.
local function gray80_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  local function has(s) return script:find(' '..s..' ',1,true) end
  if not (has('set mcp_narrow dw>60 0 1') and has('set row_top_height ?mcp_narrow 102 43')
    and has('set row_bottom_height ?mcp_narrow 29 16') and has('set row_trackidx_height 16')
    and has('set mcp.volume ?dw !mcp_volume_use_knob [2 row_slider 16 row_slider_height 0 0 0 1] 0 0')
    and has('set mcp_meter_pos + [20 row_slider 23 row_slider_height 0 0 1 1] * rs 1')
    and has('set mcp.mute !mcp_narrow + [26 __y 18 18 0 0 0 0] + * ls 1 * rs 1 .')
    and has('set mcp.fx !mcp_narrow + [-5 __y 22 18 0 0 0 0] + * ls 0.5 * rs 0.5 .')
    and has('set mcp.recarm !mcp_narrow + [28 __y 14 14 0 1 0 1] + * ls 1 * rs 1 .')
    and has('set mcp.pan trackpanmode<=4 [2 __y __w 14 0 0 0 0] 0')) then return nil end
  local rgb='%[(%d+) (%d+) (%d+)%]'
  local function triple(r,g,b) if r then return {tonumber(r),tonumber(g),tonumber(b)} end end
  local function two(pattern)
    local a,b,c,d,e,f=script:match(pattern)
    return triple(a,b,c),triple(d,e,f)
  end
  local t={}
  t.bg,t.bg_sel=two(' set mcp_bg_color track_selected==0 '..rgb..' '..rgb..' ')
  t.idx_sel,t.idx=two(' dynamiccolor mcp%.trackidx%.color "%?track_selected '..rgb..' '..rgb..'" ')
  t.on_light,t.on_dark=two(' set element %?trackcolor_valid luma>=140 '..rgb..' '..rgb..' color ')
  t.bar_sel,t.bar=two(' set mcp_indicator_color .- %?track_selected '..rgb..' '..rgb..' declare_custom_rect mcp%.custom%.rect2 ')
  t.label=triple(script:match(' set mcp%.label%.color '..rgb..' '))
  t.readout=triple(script:match(' set mcp%.meter%.readout%.color %[(%d+) (%d+) (%d+) '))
  t.loudness=triple(script:match(' set mcp%.meter%.rmsreadout%.color '..rgb:sub(1,-3)..' 0%] '))
  t.line=triple(script:match(' front mcp%.custom%.rect3 .- set __c '..rgb..' '))
  t.send_row=tonumber(script:match(' set mcp%.sendlist%.font %[%d+ (%d+) '))
  return t
end
-- theFRXST: a fixed 124 pt strip with the name on top and a rounded control panel anchored to the bottom.
local function frxst_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  local function has(s) return script:find(' '..s..' ',1,true) end
  return has('set mcp.size [124 344]') and has('set mcp.extmixer.position + low_marg2 [4 26 118 26 0 0 0 1]')
    and has('set mcp.fx h<373 [0] [7 59 25 25 0 1 0 1]') and has('set mcp.io h<373 [0] [94 59 22 25 0 1 0 1]')
    and has('set mcp.recinput h<350 [0] [7 84 80 25 0 1 0 1]') and has('set mcp.recmon h<324 [0] [9 109 106 25 0 1 0 1]')
    and has('set mcp.pan h<252 [0] [13 169 36 21 0 1 0 1]') and has('set mcp.width h<226 [0] [13 194 36 21 0 1 0 1]')
    and has('set mcp.mute h<168 [0] [13 262 36 25 0 1 0 1]') and has('set mcp.recarm h<132 [0] [13 312 36 25 0 1 0 1]')
    and has('set mcp.volume h<132 [4 318 70 25 0 1 0 1] h<290 [52 90 22 246 0 0 0 1] [52 145 22 191 0 1 0 1]')
    and has('set mcp.meter h<290 [76 90 38 247 0 0 0 1] [76 145 38 191 0 1 0 1]')
    and has('set mcp.custom.panelbg h<375 [4 83 116 258 0 0 0 1] [4 54 116 287 0 1 0 1]')
    and has('set mcp.custom.panelbg.color !track_selected [0 0 0 0 38 38 38 255] ?track_selected [0 0 0 0 64 64 64 255]')
    and has('set master.mcp.volume h<148 [4 318 50 25 0 1 0 1] h<347 [49 90 22 246 0 0 0 1] [49 88 22 249 0 1 0 1]')
    and has('set master.mcp.mono h<290 [0] [12 138 35 25 0 1 0 1]') and true or false
end
-- Mydaw: an Ableton-style strip written as macros. Top rows hang from the top of the panel, the
-- button column and name from the bottom, and the fader's triangle rides the right of a thin meter.
local function mydaw_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  local function has(s) return script:find(' '..s..' ',1,true) end
  return has('set mcp.size [sp6{0} s380{0}]') and has('set mcp.extmixer.mode [0]')
    and has('set low_ident * sp6{0} 0.33') and has('set meter_x * sp6{0} 0.66') and has('set low_button_y + maxfol_global{0} s321{0}')
    and has('set mcp.fx [s4{0} fx_ident{0} s24{0} s15{0} 0 0 0 0]') and has('set fxbyp_x - sp6{0} s29{0}')
    and has('set mcp.recinput h_maxind{x}<s100{0} [0] + button_position [s4{0} s7{0} wide_ctrl_w{0} s15{0} 0 0 0 0]')
    and has('set mcp.io + button_position [s4{0} s45{0} wide_ctrl_w{0} s15{0} 0 0 0 0]')
    and has('set mcp.meter [meter_x{0} meter_y{0} meter_w{0} meter_h{0} 0 0 0 1]')
    and has('set mcp.volume [mcp_vol_x{0} mcp_y{0} s22{0} meter_h{0} 0 0 0 1]')
    and has('set mcp.mute h_maxind{x}<s242{0} [0] + low_button_ident [low_ident{0} sm47{0} s25{0} s25{0} 0 1 0 1]')
    and has('set mcp.phase h_maxind{x}<s214{0} [0] + low_button_ident [low_ident{0} sm18{0} s25{0} s15{0} 0 1 0 1]')
    and has('set mcp.solo h_maxind{x}<s195{0} [0] + low_button_ident [low_ident{0} s1{0} s25{0} s15{0} 0 1 0 1]')
    and has('set mcp.recarm h_maxind{x}<s176{0} [0] + low_button_ident [low_ident{0} s20{0} s25{0} s15{0} 0 1 0 1]')
    and has('set mcp.label + mcpind [0 s359{0} label_w{0} s21{0} 0 1 0 1]')
    and has('set master_chw s120{0}') and has('set master.mcp.meter [meter_x{0} meter_y{0} meter_w{0} meter_h{0} 0 0 0 1]')
    and has('set master.mcp.mono h_maxind{x}<s176{0} [0] + low_button_ident [low_ident{0} s20{0} s25{0} s15{0} 0 1 0 1]')
    and has('set s380 * Scale 380') and has('set sm47 * Scale -47') and true or false
end
-- CSIX AE-Narrow and SX (six editions, one mixer macro): a control panel anchored to the bottom, every
-- control hung from its section or from the meter's width, which grows with `nchan_offs`. The wide form is
-- recognised by the exact rectangles the layout draws; anything changed falls back to the generic strip.
local function csixsx_of(cfg)
  local body=('\n'..cfg:gsub(';[^\r\n]*','')):match('\n[ \t]*macro[ \t]+drawMcp[ \t]+scale[ \t]*[\r\n]+([%s%S]-)\n[ \t]*[Ee]nd[Mm]acro%f[%W]')
  local script=body and ' '..body:gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  if not script then return false end
  for _,s in ipairs({
    'set fx_sec + [sidebar_sec{2} 0 mcp.size{0}] * scale [0 0 0 33]',
    '* scale !panLabelsMode{0} h<hide_pan_s{0} [0 0 0 0] [0 0 0 35] [0 0 0 45]',
    '* scale h<hide_input_s{0} [0 4 0 30] h<hide_inputFX_s{0} [0 -1 0 46] !labelsMode{0} [0 -1 0 58] [0 -3 0 56]',
    'set bot_sec_height ?mcp_control_align{0} + * scale 47 * mcp_maxfolderdepth{0} mcp_indent_s + * scale 47 * folderdepth mcp_indent_s',
    '+ * scale [76 371 0 220] * scale !track_selected !mcp_fxembed{0} [0] [0] [0]',
    'set nchan_offs ?meterExpMode{0} * - tracknch 2 mcp_meterExp_s{0} [0]',
    'set padding * scale stretch_sec_height{0}<padding_reduction_h{0} stretch_sec_height{0}<padding_reduction_h{1} [0 2] [0 3] [0 4]',
    'set mcp.fx + [fx_sec 0 nchan_offs_twothird{0}] * scale ?narrowMode{0} [4 8 28 20] [5 8 37 20]',
    'set mcp.fxbyp + + [mcp.fx mcp.fx nchan_offs_third{0}] [mcp.fx{2}] * scale ?narrowMode{0} [0 0 19 20] [0 0 29 20]',
    '[7 6 63 9] [7 12 63 9] width_visible{0}!=0 + [nchan_offs_half{0}] * scale !panLabelsMode{0} [10 2 26 26] [10 2 26 26] + [nchan_offs_half{0}] * scale !panLabelsMode{0} [26 2 26 26] [26 2 26 26]',
    '[7 16 63 9] [7 22 63 9] width_visible{0}!=0 + [nchan_offs_half{0}] * scale !panLabelsMode{0} [43 2 26 26] [43 2 26 26] [0]',
    'width_visible{0}==2 + [nchan_offs_half{0}] * scale [19 -11 40 9] + [nchan_offs_half{0}] * scale [5 28 35 10] + [nchan_offs_half{0}] * scale [21 28 35 10]',
    '[7 33 63 9] width_visible{0}!=0 + [nchan_offs_half{0}] * scale !panLabelsMode{0} [0] [43 31 30 9] [0]',
    'set mcp.recinput h<hide_input_s{0} [0] + [in_sec in_sec nchan_offs{0}] * scale ?narrowMode{0} width_visible{0}==3 [0] [6 2 43 16] [6 2 65 16]',
    '+ [mcp.recinput mcp.recinput] * scale [0 16 30 12] + [mcp.recinput mcp.recinput] * scale [0 16 30 12]',
    '[mcp.fxin{0} mcp.fxin] * scale [32 0 11 12]', '* scale [43 0 11 12]', '* scale [54 0 11 12]',
    'set mcp.recmode + + [in_sec in_sec] [0 mcp.fxin{3}] * scale + ?narrowMode{0} [6 16 41 16] [6 16 41 16] ?mcp.fxin{1} [0 2] [0 1]',
    'set mcp.phase + + + [mcp.recmode mcp.recmode] * scale ?narrowMode{0} [29 0 16 17] [29 0 16 17]',
    '+ [stretch_sec stretch_sec nchan_offs{0} stretch_sec] * scale !labelsMode{0} [4 4 25 -8] [4 23 25 -27]',
    'set mcp.recarm !recSec{0} [0] + * scale [0 0 36 24] ?narrowMode{0} - + [mcp.meter{2}] [stretch_sec stretch_sec] * scale [3 17 0] + - [stretch_sec stretch_sec] * scale [-19 17] [mcp.meter{2}]',
    'set mcp.recmon !recSec{0} [0] + + [0 padding] [mcp.recarm mcp.recarm] * scale [9 20 21 20]',
    'set mcp.mute + * scale ?recSec{0} [8 44 21 20] [8 20 21 20]',
    'set mcp.solo + + [0 padding] [mcp.mute mcp.mute] * scale ?narrowMode{0} [0 18 19 18] [0 21 21 20]',
    '+ [stretch_sec stretch_sec mcp.meter{2} mcp.meter{3}] * scale !labelsMode{0} [1 0 22 0] [1 0 22 0]',
    '+ + + * [1 1 scale 1] [mcp.meter{2} mcp.solo{1} 22 stretch_sec] * scale ?labelsMode{0} [4 -9 0 -25] [4 -26 0 -8] [sidebar_sec{2} 0] * scale !recSec{0} [1 4] [1 -20]',
    'set mcp_env_hide_h * scale ?narrowMode{0} [90 90] [126 136]',
    '+ + [mcp.mute stretch_sec] * scale !labelsMode{0} [1 -20 21 14] [1 -30 21 24]',
    'set mcp_io_hide_h * scale ?narrowMode{0} [90] [100]',
    '* scale !labelsMode{0} [-1 23 23 22] [-1 23 23 22]',
    'set mcp.label.margin + [0 0 0 0 0.5] * scale [4 2 4 7]',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- The 6-style mixer macro, comments dropped and whitespace collapsed, for exact `has(...)` matching.
local function mcp_script(cfg)
  local body=('\n'..cfg:gsub(';[^\r\n]*','')):match('\n[ \t]*macro[ \t]+drawMcp[ \t]+scale[ \t]*[\r\n]+([%s%S]-)\n[ \t]*endmacro%f[%W]')
  return body and ' '..body:gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
end
-- CSIX editions share one mixer script but write their own text colours into it: peak readout,
-- volume readout (selected, other), track number (selected, other) and the name's default colour.
local function csix_colors(cfg)
  local script=mcp_script(cfg) or ''
  local function rgbs(key)
    local list={}
    for r,g,b in (script:match(' set '..key:gsub('%p','%%%0')..' (.-) set ') or ''):gmatch('%[(%d+) (%d+) (%d+)[%] ]') do
      list[#list+1]={tonumber(r),tonumber(g),tonumber(b)}
    end
    return list
  end
  local function pair(list) if #list>=2 then return list[#list-1],list[#list] end return list[1] end
  -- Meter scale lettering over unlit lanes: the last rgba of the non-armed choice.
  local function rgba(key)
    local last
    for r,g,b,a in (script:match(' set '..key:gsub('%p','%%%0')..' (.-) set ') or ''):gmatch('%[(%d+) (%d+) (%d+) (%d+)[%] ]') do last={tonumber(r),tonumber(g),tonumber(b),tonumber(a)} end
    return last
  end
  local readout=rgbs('mcp.meter.readout.color')
  local c={readout=readout[#readout],scale=rgba('mcp.meter.scale.color.unlit.top')}
  c.vol_sel,c.vol=pair(rgbs('mcp.volume.label.color'))
  c.idx_sel,c.idx=pair(rgbs('mcp.trackidx.color'))
  -- Only the plain `?track_selected [r g b] [r g b]` form (the Theme Adjuster's default choice) is read.
  local p={(cfg:match('[Mm]acro%s+trackLabelColor%s+element(.-)[Ee]nd[Mm]acro') or ''):match('%?track_selected%s+%[(%d+)%s+(%d+)%s+(%d+)%]%s+%[(%d+)%s+(%d+)%s+(%d+)%]')}
  if p[1] then c.name_sel,c.name={tonumber(p[1]),tonumber(p[2]),tonumber(p[3])},{tonumber(p[4]),tonumber(p[5]),tonumber(p[6])} end
  return c
end
local function layout_of(cfg)
  if cfg:sub(1,600):find('Reapertips',1,true) then
    -- v1.95 redesigned the mixer strip (new sizes and artwork, a sidebar option); v1.90 and earlier share the first layout.
    return cfg:find('define_parameter%s+mcp_sidebar_w') and 'reapertips2' or 'reapertips'
  end
  -- Detect the normal mixer form, not the optional narrow strip flow or the file name.
  local mixer=('\n'..cfg):match('\n[ \t]*macro[ \t]+drawMcp[ \t]+thisLayout[^\r\n]*([%s%S]-)\n[ \t]*endmacro%f[%W]')
  if mixer and mixer:find('mcpForm{0}==3',1,true)
    and mixer:find('set%s+mcp%.custom%.sectionPan%s') and mixer:find('set%s+mcp%.custom%.sectionTop%s')
    and mixer:find('Layout##thisLayout##-mcpNormalShowSecPan',1,true)
    and mixer:find('Layout##thisLayout##-mcpNormalShowRoute',1,true) then
    return 'default7'
  end
  -- Recognise the 6-style normal mixer, allowing only the verified small variations.
  local script=mcp_script(cfg)
  if script then
    local function has(s) return script:find(' '..s..' ',1,true) end
    local recarm_y=tonumber(script:match(' set mcp%.recarm %+ %* scale %[0 (%-?%d+) 36 24%] %?narrowMode{0} '))
    local label_h=tonumber(script:match(' %[0 0 %-14 27%] %[0 0 0 (%d+)%] %[0 bot_sec mcp%.size{0}%] '))
    if (label_h==26 or label_h==27)
      and has('set fx_sec + [sidebar_sec{2} 0 mcp.size{0}] * scale [0 0 0 33]')
      and has('set pan_sec + [sidebar_sec{2} fx_sec{3} mcp.size{0}] * scale !panLabelsMode{0} h<hide_pan_s{0} [0 0 0 6] [0 0 0 28] [0 0 0 48]') then
      local fx='set mcp.fx + [fx_sec 0 nchan_offs_twothird{0}] * scale ?narrowMode{0} [4 7 28 20] [7 7 '
      local vol='set mcp.volume ?narrowMode{0} + - + [stretch_sec stretch_sec] [nchan_offs_half stretch_sec{3}] * scale [-4 21] * scale [0 0 '
      local mute='set mcp.mute + + [0 padding] [mcp.recmon mcp.recmon] * scale [0 19 '
      local solo='set mcp.solo + + [0 padding] [mcp.mute mcp.mute] * scale [0 21 '
      if (recarm_y==0 or recarm_y==-2) and has(fx..'43 20]') and has(vol..'21 21]')
        and has(mute..'21 20]') and has(solo..'21 20]') and has('* scale [0 16 75 12]') then
        return 'reapertips',true,recarm_y,label_h
      end
      -- Verified compact 6-style geometry (PhaseLab 1.3/2.0), not a filename alias.
      if label_h==27 and has(fx..'42 20]') and has(vol..'20 20]')
        and has(mute..'20 20]') and has(solo..'20 20]') and has('* scale [0 16 76 12]')
        and has('set mcp.recarm + * scale [0 0 20 20] ?narrowMode{0} - + [mcp.meter{2}] [stretch_sec stretch_sec] * scale [-8 16] + - [stretch_sec stretch_sec] * scale [-36 16] [mcp.meter{2}]')
        and has('set mcp.recmon + + [0 padding] [mcp.recarm mcp.recarm] * scale [0 19 21 20]') then
        return 'reapertips',true,1,label_h,true
      end
    end
    -- CSIX-BASIC: a 6-derived mixer with its own geometry. It keeps the generic arrangement but
    -- its artwork is known to fit it, so it is loaded without the experimental switch.
    if has('set pan_sec + [sidebar_sec{2} fx_sec{3} mcp.size{0}] * scale !panLabelsMode{0} h<hide_pan_s{0} [0 0 0 0] [0 0 0 36] [0 0 0 45]')
      and has('set mcp.fx + [fx_sec 0 nchan_offs_twothird{0}] * scale ?narrowMode{0} [4 8 28 20] [5 8 37 20]')
      and has('set mcp.recmon !recSec{0} [0] + + [0 padding] [mcp.recarm mcp.recarm] * scale [9 20 21 20]') then
      return 'generic',nil,nil,nil,nil,true
    end
  end
  if csixsx_of(cfg) then return 'csixsx' end
  if not cfg:find('macro%s+drawMcp') and cfg:find('custom_mcp_paneltopleft',1,true) and frxst_of(cfg) then return 'frxst' end
  if cfg:find('macro%s+drawDefaultMCP%s') and mydaw_of(cfg) then return 'mydaw' end
  if not cfg:find('macro%s+drawMcp') and cfg:find('set mcp_narrow',1,true) then
    local gray=gray80_of(cfg)
    if gray then return 'gray80',nil,nil,nil,nil,nil,gray end
  end
  return 'generic'
end
local function finish(t, cfg, inis)
  local row = tonumber(cfg:match('define_parameter%s+mcp_list_row_h%s+[^\r\n]-[\'\"]%s+(%d+)'))
    or tonumber(cfg:match('set%s+mcp%.fxlist%.font[^\r\n]-%[%s*%d+%s+(%d+)')) or 17
  -- List/meter text colours live in the .ReaperTheme (0x00BBGGRR); the first file that names a colour wins.
  local colors = {}
  local function named(key)
    local n
    for _,ini in ipairs(inis) do
      n = tonumber(ini:match('[\r\n]'..key..'%s*=%s*(-?%d+)'))
      if n then break end
    end
    if n then n = n & 0xFFFFFF; return {n & 255, (n >> 8) & 255, (n >> 16) & 255} end
  end
  for key,fallback in pairs(M.COLORS) do colors[key] = named(key) or fallback end
  -- Track panel colour under the mixer artwork (selected, unselected); optional, no built-in default.
  colors.col_seltrack, colors.col_seltrack2, colors.col_mixerbg = named('col_seltrack'), named('col_seltrack2'), named('col_mixerbg')
  t.row_height = math.max(12,math.min(26,row)); t.rtconfig = cfg; t.colors = colors
  t.layout,t.stock6,t.recarm_y,t.label_h,t.compact6,t.full_art,t.gray80 = layout_of(cfg)
  if t.full_art or t.layout=='csixsx' then t.csix = csix_colors(cfg) end
  if t.layout=='frxst' then t.send_row_height = math.max(12,math.min(30,tonumber(cfg:match('set%s+mcp%.sendlist%.font%s+%[%s*%d+%s+(%d+)')) or 27)) end
  if t.layout=='mydaw' then
    t.row_height,t.send_row_height = 15,18 -- written as scaled variables in its script
    -- Its 200% layout names the theme's Arial faces: bold 24 px labels, regular 20 px inserts, regular 24 px input.
    t.font,t.fonts = 'Arial',{main={15,true},list={12.5},sends={15,true},header={15}}
    -- Most of its mixer art exists only at one size; REAPER shows that pixel for pixel at any display scale.
    t.unscaled_base = true
  end
  if t.layout=='csixsx' then
    -- Its 200% fonts: Roboto 10 pt for labels and input, 15 pt for the name; Roboto Condensed regular 12 pt for the volume
    -- readout and track number (gfx sizes that render about as large as the mixer's). The inserts and sends use
    -- mcp.fxlist/sendlist.font 11 = user_font10, Roboto 400 at 20 px (measured in the native mixer; gfx 12.5 renders it); the
    -- pinned 'Master send' row takes the 'list' role, so both roles stay identical.
    t.font,t.fonts = 'Roboto',{main={10.3},list={12.5},header={15,false,'Roboto Condensed'},bold={12.4,false,'Roboto Condensed'},sends={12.5}} -- name: font 14 = user_font13, Roboto Condensed 24 px
  end
  if t.gray80 and t.gray80.send_row then t.send_row_height = math.max(12,math.min(26,t.gray80.send_row)) end
  -- Stock mixer faces are declared in the theme's serialized LOGFONT. Only the first
  -- null-terminated face is needed; ignore trailing bytes left from previous settings.
  if t.stock6 or t.layout=='default7' then
    for _,ini in ipairs(inis) do
      local hex=ini:match('[\r\n]lb_font%s*=%s*(%x+)')
      if hex and #hex>=58 then
        local face=hex:sub(57,120):gsub('(%x%x)',function(pair) return string.char(tonumber(pair,16)) end):match('^([^%z]+)%z')
        if face and not face:find('%c') then t.font=face;break end
      end
    end
  end
  -- The theme's own defaults for the values its layout script uses (colour variants differ only in these).
  local source = '\n'..cfg
  t.version = tonumber(source:match('\nset theme_version%s+(%d+)')) or 1
  local function direct_param(name)
    if t.live and t.live[name] ~= nil then return t.live[name] end
    local literal = name:gsub('%p','%%%0') -- names such as "LayoutA-verboseMcp" contain pattern characters
    return tonumber(source:match('\ndefine_parameter%s+'..literal.."%s+'[^']*'%s+(%-?%d+)"))
      or tonumber(source:match('\ndefine_parameter%s+'..literal..'%s+"[^"]*"%s+(%-?%d+)'))
  end
  -- Only mixer background channels use this fallback. An alias must be a single,
  -- unambiguous assignment to another setting; do not evaluate WALTER expressions.
  local aliases={}
  if t.layout=='default7' then
    for line in cfg:gmatch('[^\r\n]+') do
      local key,rhs=line:gsub(';.*',''):match('^%s*set%s+([%w_%-]+)%s+(.+)$')
      if key then
        if aliases[key]~=nil then aliases[key]=false
        else aliases[key]=rhs:match('^([%a_][%w_%-]*)%s*$') or false end
      end
    end
  end
  t.param = function(name, fallback)
    local value=direct_param(name)
    if value~=nil then return value end
    if t.layout=='default7' and name:match('^mcpBgCol[RGB]$') then
      local seen={[name]=true}
      local target=aliases[name]
      while target and not seen[target] do
        seen[target]=true
        value=direct_param(target)
        if value~=nil then
          if type(value)=='number' and value>=0 and value<=255 then return value end
          break
        end
        target=aliases[target]
      end
    end
    return fallback
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
        if found then if v[1] == '' and t.unscaled_base then found.scale = variants[1][2] end return found end
      end
    else
      local found = describe(join(t.dir,(v[1] ~= '' and v[1]..'/' or '')..name..'.png'),v[2])
      if found then if v[1] == '' and t.unscaled_base then found.scale = variants[1][2] end return found end
    end
  end
end
return M
