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
-- Flat Madness 5 (CI and SI, Bright and Dark): one mixer macro, drawMCP, in three strip widths (80, 94 and 114 pt).
-- Rows hang from the panel top, the lower rows from its bottom. The editions' mixer scripts are identical; their
-- Theme Adjuster defaults and art differ. Any changed rectangle falls back to the generic strip.
local function flatmadness_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'macro drawMCP scale fontsize hugestate meterbridge',
    'tracknch>3 [94 folderincrease 0 mcp_minheight 92 80] hugestate=1 [114 folderincrease 0 mcp_minheight 112 100] [80 folderincrease 0 mcp_minheight 78 66]',
    'set mspwidBP * scale [80 94 114]', 'set mcp.extmixer.mode [0]',
    'set mcp.recarm * scale folderstate=1 recarm_adjust [8 8 20 20]', 'set mcp.recmode * scale folderstate=1 recmode_adjust [26 8 20 20]',
    'set mcp.recmon * scale folderstate=1 recmon_adjust [50 8 22 20]', 'set mcp.recinput * scale folderstate=1 + recinput_adjust [0 0 0 0] [8 54 64 20]',
    'set mcp.env * scale [8 31 64 20]', 'set mcp.fx * scale [7 102 22 20]', 'set mcp.fxbyp * scale [29 102 18 20]', 'set mcp.fxin * scale [46 102 27 20]',
    'set mcp.pan * scale trackpanmode<4 [7 124 20 20] [7 124 68 10]', 'set mcp.pan.label * scale trackpanmode>3 [0] [29 124 44 20]',
    'set mixerwidth [6 136 68 10]', 'set labelpoints * scale [78 18]', 'set mcp.label [0 labelpoints{0} mcp.size{0} labelpoints{1}]',
    'set mcp_column_anchor w=mspwidBP{2} [86 102] w=mspwidBP{1} [66 102] [52 102]',
    'set mcp_meter_main h<mcp_flipBP{0} [6 156 30 30 0 0 0 0] w=mspwidBP{2} [5 158 55 122 0 0 0 1] w=mspwidBP{1} [5 158 35 122 0 0 0 1] [5 158 23 122 0 0 0 1]',
    'set mcp.meter * scale + mcp_meter_main [0 10 0 -10]',
    'set mcpvol_main w=mspwidBP{2} [66 168 19 112 0 0 0 1] w=mspwidBP{1} [46 168 19 112 0 0 0 1] [32 168 19 112 0 0 0 1]',
    'set mcpvol_label_main w=mspwidBP{2} [48 278 32 22 0 1 0 1] w=mspwidBP{1} [28 278 32 22 0 1 0 1] [14 278 32 22 0 1 0 1]',
    'set mcp.mute * scale h<mcp_flipBP{0} + mcp_column_anchor [-14 64 18 20] + mcp_column_anchor [3 64 20 18]',
    'set mcp.solo * scale h<mcp_flipBP{0} + mcp_column_anchor [4 64 18 20] + mcp_column_anchor [3 82 20 18]',
    'set mcp.phase * scale h<mcpphaseBP{0} [0] + mcp_column_anchor [5 150 17 17 0 1 0 1]',
    'set mcp.io * scale h<mcpphaseBP{1} [0] + mcp_column_anchor [3 172 20 22 0 1 0 1]',
    'set mcp.trackidx * scale [0 300 mcp_width{0} 20 0 1 0 1]',
    'set mcp.custom.trackcolor * scale + [0 0 -8 0] mcp_solid_color=3 [3 152 mcp.size{0} 8] [3 148 mcp.size{0} 9]',
    'set master.mcp.mono * scale [95 220 20 50 0 1 0 1]', 'set master.mcp.mute + master_mcp_column_anchor * scale [1 22 20 18]',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- iconEX (Dark, Hybrid, Light): one mixer macro, drawMCP, a fixed 80 pt strip with a 300 pt panel. Rows hang from the panel top,
-- the lower ones from its bottom. The editions' macros differ only in colours (read in `finish`); any changed rectangle falls back.
local function iconex_of(cfg)
  local script=' '..cfg:gsub(';[^\\r\\n]*',''):gsub('\\\\%s*[\\r\\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'macro drawMCP scale fontsize hugestate narrow lttype', 'drawMCP 2 2 0 0 _Df',
    'set mcp.size * scale narrow=1 [50 518 0 300 450] [mcp_width{0} 320 0 mcp_minheight mcp_width{4} mcp_width{5}]',
    'hugestate=1 [114 folderincrease 0 mcp_minheight 112 100] [80 folderincrease 0 mcp_minheight 78 60]',
    'set mcp.custom.colrcover * scale [0 0 300 160]',
    'set mcp.custom.trackcolor * scale mcp_solid_color##lttype=3 [0 152 mcp.size{0} 12] [0 150 mcp.size{0} 5]',
    'set mcp.custom.colorbg mcp_solid_color##lttype=1 mcp_colorbg_main [0]', 'set mcp.custom.sol1bg mcp_solid_color##lttype=2 mcp_sol1bg_main [0]',
    'set mcp.custom.sol1bgsel mcp_solid_color##lttype<=2 mcp_sol1bg_mainsel [0]', 'set mcp.custom.adjustbgsel mcp_solid_color##lttype=3 mcp_adjustbg_mainsel [0]',
    'set mcp.trackidx * scale [0 300 mcp_width{0} 20 0 1 0 1]', 'set labelpoints * scale [78 18]', 'set mcp.label [0 labelpoints{0} mcp.size{0} labelpoints{1}]',
    'set mcp_column_anchor w=mspwidBP{2} [86 102] w=mspwidBP{1} [66 102] [52 102]',
    'set mcp.mute * scale h<mcp_flipBP{0} + mcp_column_anchor [-14 64 18 20] + mcp_column_anchor [3 64 20 18]',
    'set mcp.solo * scale h<mcp_flipBP{0} + mcp_column_anchor [4 64 18 20] + mcp_column_anchor [3 82 20 18]',
    'set mcp.recarm * scale folderstate=1 recarm_adjust [8 8 20 20]', 'set mcp.recmode * scale folderstate=1 recmode_adjust [26 8 20 20]',
    'set mcp.recmon * scale folderstate=1 recmon_adjust [50 8 22 20]', 'set mcp.recinput * scale folderstate=1 + recinput_adjust [0 0 0 0] [8 54 64 20]',
    'set mcp.env * scale [8 31 64 20]', 'set mcp.fx * scale [6 102 22 20]', 'set mcp.fxbyp * scale [28 102 18 20]', 'set mcp.fxin * scale [46 102 27 20]',
    'set mcp.pan * scale trackpanmode<4 mcppanswitch [6 124 68 10]', 'set mcppanswitch mcppanslider##lttype=1 [6 126 68 20] [7 124 20 20]',
    'set labelmcpswitch mcppanslider##lttype=1 mcp.pan * scale [29 124 44 20]', 'set mixerwidth [6 136 68 10]',
    'set mcp_meter_main h<mcp_flipBP{0} [6 156 30 30 0 0 0 0] w=mspwidBP{2} [5 158 55 118 0 0 0 1] w=mspwidBP{1} [5 158 35 118 0 0 0 1] [8 156 18 118 0 0 0 1]',
    'set mcp.meter * scale + mcp_meter_main [0 10 0 -10]',
    'set mcpvol_main w=mspwidBP{2} [66 168 19 106 0 0 0 1] w=mspwidBP{1} [46 168 19 106 0 0 0 1] [30 168 19 106 0 0 0 1]', 'set mcp.volume.margin * scale [0 10 0 10]',
    'set mcpvol_label_main w=mspwidBP{2} [40 280 44 18 0 1 0 1] w=mspwidBP{1} [20 280 44 18 0 1 0 1] [6 279 44 18 0 1 0 1]',
    'set mcp.phase * scale h<mcpphaseBP{0} [0] + mcp_column_anchor [5 154 17 17 0 1 0 1]', 'set mcp.io * scale h<mcpphaseBP{1} [0] + mcp_column_anchor [3 177 20 18 0 1 0 1]',
    'set master.mcp.mono * scale [95 220 20 50 0 1 0 1]',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  -- Per-edition colours: the track number (selected, other) and the name's selected colour.
  local function rgb(pattern) local r,g,b=script:match(pattern) if r then return {tonumber(r),tonumber(g),tonumber(b)} end end
  local p='%[(%d+) (%d+) (%d+)%]'
  return {idx_sel=rgb(' set mcp%.trackidx%.color %?recarm %[%d+ %d+ %d+%] %?track_selected '..p),
    idx=rgb(' set mcp%.trackidx%.color %?recarm %[%d+ %d+ %d+%] %?track_selected %[%d+ %d+ %d+%] '..p),
    name_sel=rgb(' set mcp%.label%.color track_selected=1 '..p)}
end
-- nvk_THEME (Dark and Light share one rtconfig.txt): `drawMcp` and `drawMasterMcp`, one 86 pt strip written as top-down rows (ext mixer box,
-- routing, automation, pan) over a fader/meter section whose height is what is left above the bottom-anchored rows. Their own overstep rule
-- drops rows on short strips. Recognised by the exact statements the layout draws; anything changed falls back to the generic strip.
local function nvk_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  if not (script:find(' macro drawMcp scale Layout ',1,true) and script:find(' macro drawMasterMcp scale Layout ',1,true)) then return false end
  for _,s in ipairs({
    'set mcpX_margin * scale mcp_PaddingSize_param{0}',
    'set mcpXStartingMargin + * scale mcp_PaddingSize_param{0} scale==1 1 scale==1.5 1 scale==2 2',
    'set mcpSizeWidth + + * scale [72] * 2 mcpXStartingMargin{0} * 2 mcpX_margin{0}',
    'set mcpRealWidth - w scale==1 2 scale==1.5 2 scale==2 4',
    'set mcp.custom.idxSection - - + [mcpXStartingMargin mcpMainSection{3} mcpRealWidth] * scale [0 -22 0 22] * 2 [0 0 mcpX_margin] [0 mcpYStartingMargin]',
    'set mcp.custom.labelSection - + [mcp.custom.idxSection mcp.custom.idxSection mcp.custom.idxSection] * scale [0 -24 0 24] [0 mcpY_margin]',
    'set mcp.mute + - [mcpXStartingMargin mcp.custom.labelSection{1}] [0 mcpY_margin] * scale [0 -24 24 24]',
    'set mcp.solo + + mcp.mute [mcp.mute{2}] [mcpX_margin]',
    'set mcp.phase + + mcp.solo [mcp.solo{2}] [mcpX_margin]',
    'set mcp.fxin ?mcpHideRecMisc{0} [0] - mcp.mute + [0 mcpY_margin] [0 mcp.mute{3}]',
    'set mcp.recarm ?mcpHideRecMisc{0} [0] - mcp.solo + [0 mcpY_margin] [0 mcp.solo{3}]',
    'set mcp.recmon ?mcpHideRecMisc{0} [0] - mcp.phase + [0 mcpY_margin] [0 mcp.phase{3}]',
    'set mcp.custom.recarmBG + + mcp.recarm [0 0 mcp.recmon{2}] [0 0 mcpX_margin]',
    'set mcpRecInputSection mcpMainSection{3}<=mcpTopSecHeightTh{0} [0] - + [mcpXStartingMargin mcpY_margin mcpRealWidth] * scale [0 0 0 24] * 2 [0 0 mcpX_margin]',
    'set mcp.recmode ?mcpHideRecMisc{0} [0] + [mcpRecInputSection{0} mcpRecInputSection{1} 0 mcpRecInputSection{3}] * scale [0 0 24]',
    'set mcp.recinput + [mcp.recmode{0} mcp.recmode{1} mcpRecInputWidth{0} mcp.recmode{3}] [mcp.recmode{2}]',
    'set mcp.extmixer.mode [1]',
    'set mcpExtMixerHeightLimit * scale 420',
    'set mcpExtmixerH mcpMainSection{3}<=mcpExtMixerHeightLimit{0} [0] / mcpMainSection{3} mcpMainSection{3}>extmixerHeightFactorThreshscaled{0} extmixerHeightFactorMaxparam extmixerHeightFactorMinparam',
    'set mcp.extmixer.position + + [mcpXStartingMargin mcpRecInputSection{1} mcpExtmixerW{0} mcpExtmixerH{0} 0 0 0 0] [0 mcpRecInputSection{3}] mcpMainSection{3}>mcpExtMixerHeightLimit{0} [0 mcpY_margin]',
    'set mcp.io + + + [mcpXStartingMargin{0} mcp.extmixer.position{1}] * scale [0 0 24 24] [0 mcpY_margin] [0 mcp.extmixer.position{3}]',
    'set mcpLargeButtonWidth + * scale 48 mcpX_margin',
    'set mcp.custom.fx_background + + + [mcp.io{0} mcp.io{1} mcpLargeButtonWidth{0}] * scale [0 0 0 24] [mcp.io{2}] [mcpX_margin]',
    'set mcp.fx + [mcp.custom.fx_background{0} mcp.custom.fx_background{1}] * scale [0 0 24 24]',
    'set mcp.fxbyp + + [mcp.custom.fx_background{0} mcp.custom.fx_background{1}] * scale [-25 0 24 24] [mcp.custom.fx_background{2}]',
    'set mcp.env + + + [mcpXStartingMargin{0} mcp.io{1}] * scale [0 0 24 24] [0 mcpY_margin] [0 mcp.io{3}]',
    'set mcp.custom.custom_fx + + mcp.env [mcp.env{2}] [mcpX_margin]',
    'set mcp.custom.custom_fx2 + + mcp.custom.custom_fx [mcp.custom.custom_fx{2}] [mcpX_margin]',
    'set mcp.pan + + [mcpPanX{0} mcp.env{1} mcpPanWidthW{0} mcpPanWidthW{0}] [0 mcp.env{3}] [0 mcpY_margin]',
    'set mcp.pan trackpanmode==6 + + + [mcpPanX{0} mcp.env{1} mcp.custom.idxSection{2}] [0 mcp.env{3}] [0 mcpY_margin] * scale [0 0 0 16] .',
    'set mcp.width + + mcp.pan [mcpPanWidthDistance{0}] [mcp.pan{2}]',
    'set mcp.width trackpanmode==6 + + mcp.pan [0 mcp.pan{3}] [0 mcpY_margin] .',
    'set mcpVolumeAboveNeighbour ?isOverstepping_mcp.fx{0} mcp.extmixer.position{0}>1 mcp.extmixer.position mcpRecInputSection ?isOverstepping_mcp.env{0} mcp.fx ?isOverstepping_mcp.pan{0} mcp.env mcp.width',
    'set mcpVolumeHeight - mcpVolumeBelowNeighbour{1} + + + * 2 mcpY_margin mcpVolumeAboveNeighbour{1} mcpVolumeAboveNeighbour{3} * scale [0 4]',
    'set mcpVolumeSection mcpMainSection{3}<=mcpVolSecHeightTh{0} [0] - + [mcpVolumeSectionX{0} mcpVolumeBelowNeighbour 0 mcpVolumeHeight{0}] * scale [0 0 24] + [0 mcpY_margin] [0 mcpVolumeHeight{0}]',
    'set mcp.meter + + [mcpVolumeSection mcpVolumeSection mcpLargeButtonWidth{0} mcpVolumeSection] [mcpVolumeSection{2}] [mcpX_margin]',
    'set mmcpXStartingMargin + * scale master_mcp_mPaddingSize_param{0} 1',
    'set mmcpSizeWidth + + * scale [72] * 2 mmcpXStartingMargin{0} * 2 mmcpX_margin{0}',
    'set master.mcp.custom.idxSection - - + [mmcpXStartingMargin h mmcpMSWidthNoBlackMargin] * scale [0 -22 0 22] * 2 [0 0 mmcpX_margin] [0 mmcpYStartingMargin]',
    'set master.mcp.custom.firstRow - + + [0 master.mcp.custom.idxSection{1}] / [mmcpMSWidth] 2 * scale [-42 -24 84 24] [0 mmcpY_margin]',
    'set firstButton + [mmcpXStartingMargin master.mcp.custom.firstRow{1}] * scale [0 0 24 24]',
    'set master.mcp.mute - + [mmcpMuteX{0} master.mcp.custom.firstRow{1}] * scale [-24 -24 24 24] [0 mmcpY_margin]',
    'set mmcpExtmixerH h<=mmcpExtMixerHeightLimit{0} [0] / h h>extmixerHeightFactorThresh{0} masterExtmixerHeightFactorMaxparam masterExtmixerHeightFactorMinparam',
    'set master.mcp.io + + + [mmcpXStartingMargin{0} mmcpIOAboveNB{1}] * scale [0 0 24 24] [0 mmcpY_margin] [0 mmcpIOAboveNB{3}]',
    'set master.mcp.env + + + [mmcpXStartingMargin{0} master.mcp.io{1}] * scale [0 0 24 24] [0 mmcpY_margin] [0 master.mcp.io{3}]',
    'set master.mcp.mono + + master.mcp.custom.fx_background [0 master.mcp.custom.fx_background{3}] [0 mmcpY_margin]',
    'set mmcpVolumeHeight - mmcpVolumeBelowNeighbour{1} + + + * 2 mmcpY_margin mmcpVolumeAboveNeighbour{1} mmcpVolumeAboveNeighbour{3} * scale [0 4]',
    'set master.mcp.volumeSection - + [firstButton{0} mmcpVolumeBelowNeighbour 0 mmcpVolumeHeight{0}] * scale [0 0 24] + [0 mmcpY_margin] [0 mmcpVolumeHeight{0}]',
    'set master.mcp.meter [secondButton{0} master.mcp.volumeSection{1} mmcpLargeButtonWidth{0} master.mcp.volumeSection{3}]',
    'set yLimit - mcp.mute{1} * scale 128',
    'set yLimit - master.mcp.mute{1} * scale 128',
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
  if cfg:find('macro%s+drawMCP%s') and flatmadness_of(cfg) then return 'flatmadness' end
  if cfg:find('macro%s+drawMCP%s+scale%s+fontsize%s+hugestate%s+narrow') then
    local ix=iconex_of(cfg)
    if ix then return 'iconex',nil,nil,nil,nil,nil,nil,ix end
  end
  if cfg:find('macro%s+drawMcp%s+scale%s+Layout') and nvk_of(cfg) then return 'nvk' end
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
  colors.col_tcp_text = named('col_tcp_text') -- the mixer's volume readout, where its script names no colour
  t.row_height = math.max(12,math.min(26,row)); t.rtconfig = cfg; t.colors = colors
  t.layout,t.stock6,t.recarm_y,t.label_h,t.compact6,t.full_art,t.gray80,t.ix = layout_of(cfg)
  if t.full_art or t.layout=='csixsx' then t.csix = csix_colors(cfg) end
  if t.layout=='frxst' then t.send_row_height = math.max(12,math.min(30,tonumber(cfg:match('set%s+mcp%.sendlist%.font%s+%[%s*%d+%s+(%d+)')) or 27)) end
  if t.layout=='mydaw' then
    t.row_height,t.send_row_height = 15,18 -- written as scaled variables in its script
    -- Its 200% layout names the theme's Arial faces: bold 24 px labels, regular 20 px inserts, regular 24 px input.
    t.font,t.fonts = 'Arial',{main={15,true},list={12.5},sends={15,true},header={15}}
    -- Most of its mixer art exists only at one size; REAPER shows that pixel for pixel at any display scale.
    t.unscaled_base = true
  end
  if t.layout=='flatmadness' then
    -- Its lists are 16 pt rows (32 px at 200%); every mixer label is Helvetica Neue bold: user_font6 (24 px) for lists, input, pan
    -- and volume text, user_font2 (28 px) for the name and track number (gfx sizes that render as large as the mixer's).
    t.row_height,t.send_row_height = 16,16
    t.bright = cfg:find('\n%s*set%s+bright%s+1') ~= nil -- the input field's text is lighter in the Bright editions
    t.font,t.fonts = 'Helvetica Neue',{main={12.2,true},list={12.2,true},sends={12.2,true},header={14.7,true},bold={14.7,true}}
  end
  if t.layout=='iconex' then
    -- Lists are 16 pt rows; every label is Helvetica Neue bold: user_font6 (24 px) for lists, input and pan, user_font2 (28 px) for the
    -- name, readout and track number (the sizes Flat Madness's mixer, which names the same fonts, was measured at).
    t.row_height,t.send_row_height = 16,16
    t.font,t.fonts = 'Helvetica Neue',{main={12.2,true},list={12.2,true},sends={12.2,true},header={14.7,true},bold={14.7,true}}
  end
  if t.layout=='nvk' then
    -- Lists are 16 pt rows (fx insert height parameter); every label is Verdana regular: user_font10 (24 px) for lists, user_font12 (27 px)
    -- for the name, input and track number; the meter's scale is a narrow sans (measured). Most mixer art exists only at its 200% size or only in the base folder, drawn 1:1.
    t.row_height,t.send_row_height = 16,16
    t.font,t.fonts = 'Verdana',{main={12.3,false,'Arial Narrow'},list={15.2},sends={15.2},header={17.2},bold={15.9}}
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
  if t.layout=='flatmadness' or t.layout=='iconex' then source = (source:gsub('\n[ \t]+define_parameter','\ndefine_parameter')) end -- its definitions are indented
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
  if t.layout=='nvk' then t.row_height=math.max(16,math.min(40,t.param('mcp_fx_insert_height_param',16)));t.send_row_height=t.row_height end -- its Theme Adjuster row height
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
