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
-- Horizon (Dark and Light share one rtconfig.txt and every mixer image; `themeoption` and the .ReaperTheme colours are what differ): one
-- drawMcp macro, with a master that reuses the track's own rectangles. Rows hang from the top (lists, IO, pan), the lower block from the
-- bottom (input, buttons, name, number) and the meter and fader take what is left. Recognised by the statements that place those rows;
-- anything changed falls back to the generic strip.
local function horizon_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'set m_space_w * scale mcp_space_w',
    'set m_space_h * scale mcp_space_h',
    'set mcp.size + * scale folderstate==1 [mcp_size_folder] [mcp_size_A] * 2 [m_space_w]',
    'set idx_size * scale 16',
    'set label_size * scale 20',
    'set top_w * scale 2',
    'set top_h * scale 2',
    'set mcp.trackidx - [0 h w idx_size] + [0 idx_size 1] [0 mcp_start]',
    'set mcp.label + - - [0 mcp.trackidx w label_size] [0 label_size 1] [0 m_space_h] - [m_space_w] * 2 [0 0 m_space_w]',
    'set top_block - [m_space_w m_space_w w h] + + [0 0 1] * 2 [0 0 m_space_w] + + [0 0 0 idx_size] + [0 0 0 label_size] + [0 0 0 mcp_align] [0 0 0 input_block] + [0 0 0 m_space_w] * 2 [0 0 0 m_space_h]',
    'set mcp_fx_block - + [top_block top_block top_block mcp_list_h] [top_w top_h] * 2 [0 0 top_w]',
    'set extmixer_max + * 2 top_w + * 2 el_size + * 4 mcp_list_h * 5 m_space_h',
    'set extmixer_size - * * 0.01 mcp_ext_size top_block{3} extmixer_max',
    'set extmixer_size extmixer_size<extmixer_min 0 extmixer_size',
    'set mcp_io_block + + + [top_block top_block top_block mcp_list_h] [0 m_space_h] + [0 mcp_fx_block{3}] !mcp_ext_free extmixer_hide>0 [0 extmixer_size] 0 0 - [top_w top_h] * 2 [0 0 top_w]',
    'set pan_wid_block + + [top_block mcp_io_block top_block el_size] + [0 mcp_io_block{3}] [0 m_space_h] - [top_w] * 2 [0 0 top_w]',
    'set mcp_pan_value_block ?mcp_values_parm + + [top_block pan_wid_block top_block mcp_list_h] + [0 pan_wid_block{3}] [0 m_space_h] - [top_w] * 2 [0 0 top_w] 0',
    'set vol_meter_block_size - + + top_block [top_w top_h] + * ?mcp_values_parm 4 3 [0 m_space_h] + * ?mcp_values_parm 3 2 [0 mcp_list_h] + [0 extmixer_block{3}] [0 el_size] + * 2 [0 0 top_w top_h] + * ?mcp_values_parm 5 3 [0 0 0 m_space_h] + * ?mcp_values_parm 4 2 [0 0 0 mcp_list_h] + [0 0 0 extmixer_block{3}] [0 0 0 el_size]',
    'set buttons_block_size + * 3 el_size * 2 m_space_h',
    'set input_block_size * 2 thi_shelf_h_size',
    'set middle_indent + buttons_block_size + input_block_size m_space_h',
    'set top_block - top_block + [0 0 0 middle_indent] [0 0 0 m_space_h]',
    'set hide_vol_met_size + * scale 100 * 2 m_space_h',
    'set hide_one ?unrec_align_t 1 trackidx==0 1 vol_meter_block{3}<hide_vol_met_size 1 0',
    'set hide_one_size + [0 0 0 input_block_size] [0 0 0 m_space_h]',
    'set hide_two ?unrec_align_t 1 trackidx==0 1 vol_meter_block{3}<hide_vol_met_size 1 0',
    'set hide_two_size + [0 0 0 el_size] [0 0 0 m_space_h]',
    'set hide_thi vol_meter_block{3}<hide_vol_met_size 1 0',
    'set vol_value_block ?mcp_values_parm + + [top_block vol_meter_block top_block mcp_list_h] + [0 vol_meter_block{3}] [0 m_space_h] - [top_w] * 2 [0 0 top_w] 0',
    'set mcp.fx mcp_fx_block',
    'set mcp.fxbyp - + [mcp.fx mcp.fx fxbyp_size mcp.fx] [mcp.fx{2}] [fxbyp_size]',
    'set mcp.io mcp_io_block',
    'set mcp.extmixer.position + extmixer_block [-1 1 4 -2]',
    'set mcp.fxlist.font + [mcp_list_font] + [0 mcp_list_h] [0 2]',
    'set mcp.pan ?hide_five 0 ?top_block + [pan_wid_block pan_wid_block] + trackpanmode<=3 + [0 0 el_size el_size] - * 0.5 [pan_wid_block{2}] * 0.5 [el_size] + trackpanmode==5 - + [0 0 el_size el_size] - * 0.5 [pan_wid_block{2}] * 0.5 [el_size] * scale [10] trackpanmode==6 + * scale [0 0 40 10] - * 0.5 [pan_wid_block{2}] * scale [20] 0 0 0 0',
    'set mcp.width ?hide_five 0 ?top_block + [pan_wid_block pan_wid_block] + trackpanmode==5 + - + [0 0 el_size el_size] - * 0.5 [pan_wid_block{2}] * 0.5 [el_size] * scale [10] [mcp.pan{2}] trackpanmode==6 + * scale [0 10 40 10] - * 0.5 [pan_wid_block{2}] * scale [20] 0 0 0 0',
    'set mcp.pan.label ?hide_all 0 ?mcp_values_parm trackpanmode<=3 mcp_pan_value_block - mcp_pan_value_block * 0.5 [0 0 mcp_pan_value_block] 0 0',
    'set mcp.width.label ?hide_all 0 trackpanmode>=5 + mcp.pan.label [mcp.pan.label{2}] 0',
    'set mtl * [1 1 0.5 1] vol_meter_block',
    'set meter_el - mtl [0 0 meter_el_fix]',
    'set mcp.meter ?hide_all 0 + meter_el scale==1 [2 2 -4 -4] scale==1.5 [3 3 -6 -6] [4 4 -8 -8]',
    'set vol_resize meter_el{3}<=vol_resize_s 1 0',
    'set mcp.volume + + meter_el [meter_el{2}] [meter_el_fix]',
    'set mcp.volume ?hide_all 0 !vol_resize mcp.volume - + [mcp.volume mcp.volume el_size el_size] * 0.5 [mcp.volume{2} mcp.volume{3}] * 0.5 [el_size el_size]',
    'set volume_borders - - + + mcp.volume [2] [0 volume_spaces] [0 0 3] * 2 [0 0 0 volume_spaces]',
    'set volume_top_side - volume_borders * 0.719 [0 0 0 volume_borders]',
    'set volume_down_side - + volume_borders [0 volume_top_side{3}] [0 0 0 volume_top_side]',
    'set mcp.volumebgline.custom - + [volume_borders volume_borders 2 volume_borders] * 0.5 [volume_borders{2}] [1]',
    'set input_block !hide_one + [top_block top_block top_block] + [0 top_block{3}] + [0 m_space_h] [0 0 0 input_block_size] 0',
    'set buttons_block_w * 2 el_size_m',
    'set buttons_block + + [top_block top_block] + [0 0 buttons_block_w] + + [0 top_block{3}] trackidx==0 0 ?hide_one 0 [0 input_block_size] + * ?hide_one 1 2 [0 m_space_h] [0 0 0 buttons_block_size] - * 0.5 [top_block{2}] + * 0.5 [buttons_block_w] [2]',
    'set mcp.mute ?hide_all 0 + [buttons_block buttons_block el_size_m el_size] - [0 buttons_block{3}] [0 el_size]',
    'set mcp.solo ?hide_all 0 + [mcp.mute mcp.mute el_size_m el_size] [mcp.mute{2}]',
    'set mcp.recarm ?unrec 0 !hide_two - [buttons_block mcp.mute el_size_m el_size] + [0 mcp.mute{3}] [0 m_space_h] 0',
    'set mcp.recmon ?unrec 0 !hide_two + [mcp.recarm mcp.recarm el_size_m el_size] [mcp.recarm{2}] 0',
    'set mcp.phase !hide_thi - [buttons_block mcp.mute el_size el_size] !hide_two + * 2 [0 mcp.mute{3}] * 2 [0 m_space_h] + [0 mcp.mute{3}] [0 m_space_h] 0',
    'set mcp.env !hide_thi + [mcp.phase mcp.phase el_size el_size] + [mcp.phase{2}] * scale [2] 0',
    'set mcp.recinput ?unrec 0 !hide_one [input_block input_block input_block input_block] 0',
    'set mcp.fxin ?unrec 0 !hide_one + + [input_block mcp.recinput 0 thi_shelf_h_size] * scale [0 0 12] [0 thi_shelf_h_size{3}] 0',
    'set mcp.recmode ?unrec 0 !hide_one - + [mcp.fxin mcp.fxin input_block thi_shelf_h_size] - [mcp.fxin{2}] * scale [2 0 -2] [0 0 mcp.fxin{2}] 0',
    'macro drawMcp scale layout alt',
    'macro drawMasterMcp scale',
    'set master.mcp.size + * scale [mcp_size_master] * 2 [m_space_w]',
    'set master.mcp.mute mcp.mute',
    'set master.mcp.mono mcp.phase',
    'set master.mcp.io mcp_io_block',
    'set master.mcp.meter mcp.meter',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- ReaTools (Classic, Dark, DarkBlack): `drawMcp` and `drawMasterMcp`, one fixed 80 pt strip (the 200% layout's numbers halved) whose lower 607 pt is one
-- printed background hung from the bottom, with the racks' box above it taking what is left. The three editions' mixer scripts are the same
-- (their Theme Adjuster defaults, text colours and art differ; DarkBlack lacks one 100%-only statement, which the 200% layout does not use). Recognised by the exact statements the layout draws; anything changed falls back
-- to the generic strip.
local function reatools_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'macro drawMcp scale',
    'macro drawMasterMcp scale',
    'set mcp.custom.mcpBgBox scale{0}==1 [3 18 73 331 0 0 0 1] scale{0}==2 [6.5 36 146 662.5 0 0 0 1]',
    'set mcp.custom.mcpBgBox.color [0 0 0 0 10 10 10 96]',
    'set mcp.custom.topline * scale [0 0 80 4]',
    'set mcp.custom.sidebg_L scale{0}==1 [1 15 2 334 0 0 0 1] scale{0}==2 [2 30 5 669 0 0 0 1]',
    'set mcp.size * scale [80 957 80 629]',
    'set mcp.custom.fixline * scale [0 955 84 2 0 1 0 1]',
    'set mcp.custom.colorlb * scale p8>=1 [0] [1 940 78 12 0 1 0 1]',
    'set mcp.custom.colorlb2 * scale p8>=1 [0] [1 3 78 12]',
    'set mcp.extmixer.mode [1]',
    'set mcp.extmixer.position * scale [3 20 73 330 0 0 0 1]',
    'set mcp.fxlist.font scale{0}==1 [1 18] scale{0}==2 [8 36]',
    'set mcp.sendlist.font scale{0}==1 [1 18] scale{0}==2 [8 36]',
    'set mcp.recinput scale{0}==1 [5 364 69 17 0 1 0 1] scale{0}==2 [10 728 138 36 0 1 0 1]',
    'set mcp.recmode os_type==0 scale{0}==1 [5 382 57 17 0 1 0 1] scale{0}==2 [11 765 114 34 0 1 0 1]',
    'set mcp.recmode os_type==3 scale{0}==1 [5 382 57 17 0 1 0 1] scale{0}==2 [11.5 765 114 34 0 1 0 1]',
    'set mcp.recmode os_type==4 scale{0}==1 [5 382 57 17 0 1 0 1] scale{0}==2 [11.5 765 114 34 0 1 0 1]',
    'set mcp.env scale{0}==1 [5 417 69 17 0 1 0 1] scale{0}==2 [10 834 138 34 0 1 0 1]',
    'set mcp.fx scale{0}==1 [6 451 48 19 0 1 0 1] scale{0}==2 [12 903 96 38 0 1 0 1]',
    'set mcp.fxin scale{0}==1 [62 382 12 17 0 1 0 1] scale{0}==2 [123 765 24 34 0 1 0 1]',
    'set mcp.fxbyp scale{0}==1 [54 448 21 28 0 1 0 1] scale{0}==2 [108 897 42 56 0 1 0 1]',
    'set mcp.custom.knobmn * scale trackpanmode<=3 [3 478 73 34 0 1 0 1] trackpanmode>=5 [0]',
    'set mcp.custom.knobst * scale trackpanmode<=3 [0] trackpanmode>=5 [3 478 73 34 0 1 0 1]',
    'set mcp.pan scale{0}==1 trackpanmode<=3 [17 473 46 46 0 1 0 1] trackpanmode>=5 [-1 473 46 46 0 1 0 1]',
    'set mcp.pan scale{0}==2 trackpanmode<=3 [44 952 72 72 0 1 0 1] trackpanmode>=5 [8 952 72 72 0 1 0 1]',
    'set mcp.custom.mnp scale{0}==2 os_type==0 trackpanmode<=3 [30 1050 36 18 0 1 0 1] trackpanmode==5 [0] trackpanmode==6 [0]',
    'set mcp.custom.mnp scale{0}==2 os_type==3 trackpanmode<=3 [30 1048 36 18 0 1 0 1] trackpanmode==5 [0] trackpanmode==6 [0]',
    'set mcp.pan.label * scale trackpanmode<=3 [41 519 32 14 0 1 0 1] trackpanmode==5 [9 519 32 14 0 1 0 1] trackpanmode==6 [9 519 32 14 0 1 0 1]',
    'set mcp.width scale{0}==1 trackpanmode<=3 [0] trackpanmode>=5 [34 473 46 46 0 1 0 1]',
    'set mcp.width scale{0}==2 trackpanmode<=3 [0] trackpanmode>=5 [78 952 72 72 0 1 0 1]',
    'set mcp.width.label * scale trackpanmode<=3 [0] trackpanmode==5 [42 519 31 14 0 1 0 1] trackpanmode==6 [42 519 31 14 0 1 0 1]',
    'set mcp.recmon * scale [9 542 28 20 0 1 0 1]',
    'set mcp.recarm * scale [41 542 28 20 0 1 0 1]',
    'set mcp.solo * scale [9 567 28 20 0 1 0 1]',
    'set mcp.mute * scale [41 567 28 20 0 1 0 1]',
    'set mcp.volume scale{0}==1 [11 593 29 235 0 1 0 1] scale{0}==2 [24 1188 56 470 0 1 0 1]',
    'set mcp.volume.label * scale [5 831 41 15 0 1 0 1]',
    'set mcp.meter * scale p4>0 [57 592 17 233 0 1 0 1] [57 592 13 233 0 1 0 1] ?recarm p10>=1 [42 592 32 233 0 1 0 1] [0]',
    'set mcp.phase * scale [22 842 31 26 0 1 0 1]',
    'set mcp.label * scale [4 869 73 15 0 1 0 1]',
    'set mcp.trackidx * scale [0 349 80 607 0 1 0 1]',
    'set mcp.io * scale [8 906 60 26 0 1 0 1]',
    'set master.mcp.custom.coloridxbg scale{0}==1 [0 15 80 942 0 0 0 1] scale{0}==2 [0 30 160 1883 0 0 0 1]',
    'set master.mcp.custom.idx * scale [0 350 80 609 0 1 0 1]',
    'set master.mcp.custom.label2 * scale [0 942 79 13 0 1 0 1]',
    'set master.mcp.size * scale [80 959 80 629]',
    'set master.mcp.extmixer.position * scale [3 20 73 325 0 0 0 1]',
    'set master.mcp.menubutton * scale [5 365 69 17 0 1 0 1]',
    'set master.mcp.mono * scale [6 383 68 17 0 1 0 1]',
    'set master.mcp.env scale{0}==1 [5 418 69 17 0 1 0 1] scale{0}==2 [11 835 138 34 0 1 0 1]',
    'set master.mcp.fx scale{0}==1 [6 451 48 19 0 1 0 1] scale{0}==2 [12 903 96 38 0 1 0 1]',
    'set master.mcp.fxbyp scale{0}==1 [54 448 21 28 0 1 0 1] scale{0}==2 [108 897 42 56 0 1 0 1]',
    'set master.mcp.solo * scale [9 568 28 20 0 1 0 1]',
    'set master.mcp.mute * scale [41 568 28 20 0 1 0 1]',
    'set master.mcp.volume * scale [2 595 29 235 0 1 0 1]',
    'set master.mcp.volume.label * scale [5 834 41 15 0 1 0 1]',
    'set master.mcp.meter * scale [31 594 39 234 0 1 0 1]',
    'set master.mcp.label * scale [3 869 73 17 0 1 0 1]',
    'set master.mcp.io * scale [9 906 60 27 0 1 0 1]',
    'set master.mcp.meter p5>=1 * scale [28 594 45 234 0 1 0 1]',
    'drawMcp 2.0',
    'drawMasterMcp 2.0',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- paRt (Dark, Dimmed, Light): `MAC_DrawMcp` and its helper macros, one script for every display scale and strip width (the layout follows the 200% numbers
-- the screenshot shows, at the script's default Theme Adjuster values). The editions share the whole script and differ only in their `THEME_color_*`
-- constants, which finish() reads. Recognised by the statements below; anything changed falls back to the generic strip.
local function part_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'set VAL_Unit SCALE>2 2 SCALE>1 2 1',
    'set VAL_Pad SCALE>=2 6 SCALE>1 4 2',
    'set VAL_Border SCALE>=2.5 2 SCALE>=2 2 1',
    'set VAL_Button SCALE>=2.5 [45 35] SCALE>=2.25 [41 32] SCALE>=2 [36 28] SCALE>=1.75 [32 25] SCALE>=1.5 [27 21] SCALE>=1.25 [23 18] [18 14]',
    'set VAL_Knob SCALE>=2.5 45 SCALE>=2.25 41 SCALE>=2 36 SCALE>=1.75 32 SCALE>=1.5 27 SCALE>=1.25 23 18',
    'set VAL_MCP_Label SCALE>=2.5 35 SCALE>=2.25 32 SCALE>=2 28 SCALE>=1.75 24 SCALE>=1.5 21 SCALE>=1.25 18 14',
    'set VAL_insert_slot SCALE>=2.5 42 SCALE>=2.25 38 SCALE>=2 34 SCALE>=1.75 31 SCALE>=1.5 26 SCALE>=1.25 21 16',
    'set VAL_Fader SCALE>=2.5 [31 7 25 5] SCALE>=2.25 [29 6 22 4] SCALE>=2 [24 6 20 4] SCALE>=1.75 [22 6 18 3] SCALE>=1.5 [19 4 15 3] SCALE>=1.25 [17 3 13 2] [12 3 10 2]',
    'set VAL_mcp_inserts_min_h + VAL_rounding_constant{0} - * SCALE 30 VAL_rounding_constant{0}',
    'set VAL_mcp_w_button_slim + VAL_Unit{0} VAL_Button{0}',
    'set VAL_mcp_w_button_wide + VAL_Unit{0} + * 2 VAL_Button{0} VAL_mcp_spacing_x{0}',
    'set VAL_mcp_w_button_large + VAL_Unit{0} + * 4 VAL_Button{0} * 3 VAL_mcp_spacing_x{0}',
    'MAC_DrawMcp_Setup_Track SCALE "mcp" "track"',
    'MAC_DrawMcp_Label_Track SCALE "mcp" "track"',
    'MAC_DrawMcp_Inserts SCALE "mcp" "track"',
    'MAC_DrawMcp_Buttons_Track SCALE "mcp" "track"',
    'MAC_DrawMcp_Meter_Top SCALE "mcp" "track"',
    'MAC_DrawMcp_Faders_Top SCALE "mcp" "track"',
    'MAC_DrawMcp_Meter_Bottom SCALE "mcp" "track"',
    'MAC_DrawMcp_Meter_Format_Track SCALE "mcp" "track"',
    'MAC_DrawMcp_Faders_Bottom SCALE "mcp" "track"',
    'MAC_DrawMcp_Size SCALE "mcp" "track"',
    'MAC_DrawMcp_Setup_Master SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Label_Master SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Inserts SCALE "master.mcp" "master"',
    'MAC_DrawMcp_PostInsert_Master SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Buttons_Master SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Meter_Top SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Faders_Top SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Meter_Bottom SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Meter_Format_Master SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Faders_Bottom SCALE "master.mcp" "master"',
    'MAC_DrawMcp_Size SCALE "master.mcp" "master"',
    'set VAL_mcp_h 400',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 4 WALTER_ELEMENT PARAMETER_SECTION "recmode" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 8 WALTER_ELEMENT PARAMETER_SECTION "fxin" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 16 WALTER_ELEMENT PARAMETER_SECTION "fx" 1',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 32 WALTER_ELEMENT PARAMETER_SECTION "io" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 64 WALTER_ELEMENT PARAMETER_SECTION "phase" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 128 WALTER_ELEMENT PARAMETER_SECTION "mute" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 256 WALTER_ELEMENT PARAMETER_SECTION "solo" 1',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 512 WALTER_ELEMENT PARAMETER_SECTION "recarm" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 1024 WALTER_ELEMENT PARAMETER_SECTION "recmon" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 2048 WALTER_ELEMENT PARAMETER_SECTION "env" 1',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 2 WALTER_ELEMENT PARAMETER_SECTION "fx" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 4 WALTER_ELEMENT PARAMETER_SECTION "io" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 8 WALTER_ELEMENT PARAMETER_SECTION "mono" 1',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 16 WALTER_ELEMENT PARAMETER_SECTION "mute" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 32 WALTER_ELEMENT PARAMETER_SECTION "solo" CUR_Linebreak',
    'MAC_DrawMcp_Buttons_SingleButton SCALE 64 WALTER_ELEMENT PARAMETER_SECTION "env" 1',
    'macro MAC_DrawMcp SCALE',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- Realogix (a Logic-style theme): a flat mixer script, one fixed 72 pt strip (115 pt master) of design height 902 (973) whose rectangles hang from the bottom,
-- with the racks' box hung from the top; the height thresholds h1-h14 (and the pan mode) decide what shows. Not a Default 6/7 derivative (no
-- shared macros or section rectangles), so it is recognised by the statements that place its blocks and colour its text.
local function realogix_of(cfg)
  local script=' '..cfg:gsub(';[^\\r\\n]*',''):gsub('\\\\%s*[\\r\\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'set h1 339', 'set h2 363', 'set h3 389', 'set h4 414', 'set h5 mcp_wantextmix>1 423 421', 'set h6 464', 'set h7 505', 'set h8 563', 'set h13 723', 'set h14 800',
    'set h9 555', 'set h10 587', 'set h11 622', 'set h12 652', 'set sends_offs mcp_wantextmix>1 70 0', 'set pan_mode h>h14{0} 2 trackpanmode>4 1 0',
    'set pan_offs pan_mode{0}==2 60 0', 'set mcp.size [72 902]', 'set mcp.trackidx + [-1 880 73 20 0 1 0 1] folder_offs', 'set mcp.label [5 859 64 18 0 1 0 1]',
    'set mcp.label.margin [5 0 5 0 0.5]', 'set mcp.label.color ?recarm [207 95 95] [160 160 160]', 'set mcp.mute [6 837 31 23 0 1 0 1]', 'set mcp.solo [36 837 31 23 0 1 0 1]',
    'set mcp.recarm [47 806 33 23 0 1 0 1]', 'set mcp.recmon [33 810 15 18 0 1 0 1]', 'set mcp.meter + [45 658 20 144 0 1 0 1] inf_offs',
    'set mcp.volume - [2 650 29 181 0 1 0 1] / [p5{0}] 2', 'set mcp.volume.label h>h4{0} [8 621 72 42 0 1 0 1]', 'set mcp.volume.label.color ?track_selected [22 22 22] [17 17 17]',
    'set mcp.phase h>h4{0} [44 633 22 20 0 1 0 1]', 'set mcp.pan h>330 [21 596 31 31 0 1 0 1]', 'set mcp.pan h>h4{0} [21 572 31 31 0 1 0 1]',
    'set mcp.pan h>h0{0} pan_mode{0}==1 [1 592 72 19 0 1 0 1]', 'set mcp.pan h>h4{0} pan_mode{0}==1 [1 567 72 19 0 1 0 1]', 'set mcp.pan pan_mode{0}==2 - mcp.pan [10]',
    'set mcp.pan.label h>h0{0} [6 633 61 18 0 1 0 1]', 'set mcp.pan.label h>h4{0} [6 609 61 18 0 1 0 1]', 'set mcp.pan.label.color [91 181 54]',
    'set mcp.width h>h4{0} [32 536 31 31 0 1 0 1]', 'set mcp.width h>328 pan_mode{0}==1 [1 612 72 19 0 1 0 1]', 'set mcp.width h>h4{0} pan_mode{0}==1 [1 587 72 19 0 1 0 1]',
    'set mcp.width pan_mode{0}==0 [0]', 'set mcp.width.label h>394 [5 532 63 18 0 1 0 1]', 'set mcp.width.label h>h4{0} [5 507 63 18 0 1 0 1]',
    'set mcp.width.label.color [198 176 64]', 'set mcp.width.label pan_mode{0}<1 [0]',
    'set mcp.recinput h>h0{0} [6 633 61 18 0 1 0 1]', 'set mcp.recinput h>h4{0} [6 609 61 18 0 1 0 1]', 'set mcp.recinput h>h13{0} [5 470 62 18 0 1 0 1]',
    'set mcp.recinput h>h14{0} [5 403 62 18 0 1 0 1]', 'set mcp.recinput.color [102 165 215]', 'set mcp.recinput !recarm h<=h13{0} [0]',
    'set mcp.fxin h>h0{0} [55 633 16 19 0 1 0 1]', 'set mcp.fxin h>h4{0} [55 609 16 19 0 1 0 1]', 'set mcp.fxin h>h14{0} [55 403 16 19 0 1 0 1]', 'set mcp.fxin !recarm h<h14{0} [0]',
    'set mcp.io h>h1{0} [5 567 70 18 0 1 0 1]', 'set mcp.io h>h4{0} [5 543 70 18 0 1 0 1]', 'set mcp.io h>h5{0} [0]', 'set mcp.io h>h7{0} [5 542 70 18 0 1 0 1]', 'set mcp.io h>h14{0} [5 541 70 18 0 1 0 1]',
    'set mcp.env h>h2{0} [5 543 70 18 0 1 0 1]', 'set mcp.env h>h4{0} [5 518 70 18 0 1 0 1]', 'set mcp.env h>h5{0} [0]', 'set mcp.env h>h6{0} [5 542 70 18 0 1 0 1]',
    'set mcp.env h>h7{0} [5 518 70 18 0 1 0 1]', 'set mcp.env h>h14{0} [5 515 70 18 0 1 0 1]',
    'set mcp.fx h>h3{0} [5 519 70 18 0 1 0 1]', 'set mcp.fx h>h4{0} [5 493 70 18 0 1 0 1]', 'set mcp.fx h>h5{0} [0]', 'set mcp.fx h>h8{0} [5 494 70 18 0 1 0 1]', 'set mcp.fx h>h14{0} [5 489 70 18 0 1 0 1]',
    'set mcp.fxbyp h>h3{0} [54 519 14 18 0 1 0 1]', 'set mcp.fxbyp h>h4{0} [54 493 14 18 0 1 0 1]', 'set mcp.fxbyp h>h5{0} [0]', 'set mcp.fxbyp h>h8{0} [54 494 14 18 0 1 0 1]', 'set mcp.fxbyp h>h14{0} [54 489 14 18 0 1 0 1]',
    'set mcp.extmixer.mode [1]', 'set mcp.extmixer.position h>h5{0} [5 10 64 549 0 0 0 1]', 'set mcp.extmixer.position h>h6{0} [5 10 64 525 0 0 0 1]',
    'set mcp.extmixer.position h>h7{0} [5 10 64 501 0 0 0 1]', 'set mcp.extmixer.position h>h8{0} [5 10 64 477 0 0 0 1]', 'set mcp.extmixer.position h>h13{0} [5 10 64 453 0 0 0 1]',
    'set mcp.extmixer.position h>h14{0} [5 10 64 445 0 0 0 1]', 'set mcp.io - mcp.io pan_offs@y', 'set mcp.env - mcp.env pan_offs@y', 'set mcp.fx - mcp.fx pan_offs@y',
    'set mcp.fxbyp - mcp.fxbyp pan_offs@y', 'set mcp.extmixer.position - mcp.extmixer.position pan_offs@h', 'set mcp.fxlist.margin [6 0 5 0 0.5]', 'set mcp.fxlist.font [4 17 0 0 2]',
    'set mcp.sendlist.margin [5 0 5 0]', 'set mcp.sendlist.font [4 17 0 0 2]',
    'set master.mcp.size [115 973]', 'set master.mcp.mute [09 921 31 23 0 1 0 1]', 'set master.mcp.mono [39 921 37 23 0 1 0 1]', 'set master.mcp.solo [75 921 31 23 0 1 0 1]',
    'set master.mcp.volume [8 885 100 23 0 1 0 1]', 'set master.mcp.volume.label [7 862 101 21 0 1 0 1]', 'set master.mcp.volume.label.color [102 165 215]',
    'set master.mcp.meter [8 654 99 194 0 1 0 1]', 'set master.mcp.menubutton h<364 mcp_iconsize=0 [7 620 108 18 0 1 0 1]', 'set master.mcp.menubutton h>h2{0} [0]',
    'set master.mcp.menubutton h>h6{0} [7 623 108 18 0 1 0 1]', 'set master.mcp.pan.label h>h9{0} [7 594 101 19 0 1 0 1]', 'set master.mcp.pan.label.color [91 181 54]',
    'set master.mcp.pan h>h9{0} [43 544 31 31 0 1 0 1]', 'set master.mcp.io h>h1{0} [7 622 108 18 0 1 0 1]', 'set master.mcp.io h>h4{0} [7 597 108 18 0 1 0 1]', 'set master.mcp.io h>h4{0} [0]',
    'set master.mcp.io h>h11{0} [7 507 108 18 0 1 0 1]', 'set master.mcp.env h>379 [7 598 108 18 0 1 0 1]', 'set master.mcp.env h>h4{0} [0]', 'set master.mcp.env h>h10{0} [7 507 108 18 0 1 0 1]',
    'set master.mcp.env h>h11{0} [7 481 108 18 0 1 0 1]', 'set master.mcp.fx h>405 [7 574 108 18 0 1 0 1]', 'set master.mcp.fx h>h4{0} [7 547 108 18 0 1 0 1]', 'set master.mcp.fx h>h4{0} [0]',
    'set master.mcp.fx h>h12{0} [7 455 108 18 0 1 0 1]', 'set master.mcp.fxbyp h>405 [88 574 19 18 0 1 0 1]', 'set master.mcp.fxbyp h>h4{0} [88 547 19 18 0 1 0 1]', 'set master.mcp.fxbyp h>h4{0} [0]',
    'set master.mcp.fxbyp h>h12{0} [88 455 19 18 0 1 0 1]', 'set master.mcp.extmixer.position h>h4{0} [6 10 104 632 0 0 0 1]', 'set master.mcp.extmixer.position h>h6{0} [6 10 104 604 0 0 0 1]',
    'set master.mcp.extmixer.position h>h9{0} [6 10 104 520 0 0 0 1]', 'set master.mcp.extmixer.position h>h10{0} [6 10 104 488 0 0 0 1]', 'set master.mcp.extmixer.position h>h11{0} [6 10 104 463 0 0 0 1]',
    'set master.mcp.extmixer.position h>h12{0} [6 10 104 437 0 0 0 1]', 'set master.mcp.fxlist.margin [6 0 5 0 0.5]', 'set master.mcp.sendlist.margin [5 0 5 0]',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
-- WT Imperial V5 (default mixer layout): `draw_mcp` and `draw_mcp_master` in a fixed 94 pt strip (118 pt master) of design size 874: a 400 pt group
-- (name, solo, fader, polarity/mute, number) hung from the bottom and blocks stacked from the top (meter and input panel, automation, FX, the racks'
-- box, record mode, record arm and monitor, pan), which the script drops in a fixed order when the racks' box would be too small. Recognised by the
-- statements that place those blocks and colour its text; the sibling Imperial themes write other rectangles and fall back to the generic strip.
-- Echolot (mawi's theme; FeedTheCat's mod is the edition checked): a flat mixer script (no macros, so not a Default 6/7 derivative) for a 102 pt strip of design
-- height 702: the racks' box from the top, everything else hung from the bottom, blocks hidden by the panel's height. Recognised by the statements that place
-- the blocks, the lists' rows and the name colours; the original edition's script (shipped as rtconfig_bak.txt) writes other rectangles and falls back to generic.
local function echolot_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'set mcp.size [102 702]', 'set mcp.trackidx + [6 672 90 16 0 1 0 1] folder_offs', 'set mcp.trackidx.color [189 189 193 255 0 0 0 0]', 'set mcp.label [6 652 90 16 0 1 0 1]',
    'set mcp.label.color tcp.label.color', 'set tcp.label.color ?track_selected [31 31 31 255 230 189 125 255] [0 0 0 0 38 40 41 255]',
    'set mcp.volume.label h<120 [0] [6 630 90 16 0 1 0 1]', 'set mcp.volume.label.color h<224 [198 203 206 255 38 40 41 200] [198 203 206 255 0 0 0 0]',
    'set mcp.volume h<224 mcp.volume.label [40 477 22 157 0 1 0 1]', 'set mcp.meter h<80 [0] h<224 [6 6 90 15 0 0 0 0] [67 486 28 129 0 1 0 1]',
    'set mcp.pan.label h<138 [0] h<170 trackpanmode<6 [6 613 45 13 0 1 0 1] [6 613 45 13 0 1 0 1] h<224 trackpanmode<6 [6 613 90 13 0 1 0 1] [6 613 45 13 0 1 0 1] h<275 [0] trackpanmode<6 [2 464 98 13 0 1 0 1] [2 464 49 13 0 1 0 1]',
    'set mcp.pan h<170 mcp.pan.label h<224 trackpanmode<6 [34 581 34 34 0 1 0 1] [12 581 34 34 0 1 0 1] h<275 [0] trackpanmode<6 [34 432 34 34 0 1 0 1] [12 432 34 34 0 1 0 1]',
    'set mcp.width.label h<138 [0] h<170 trackpanmode<6 [51 613 45 13 0 1 0 1] [51 613 45 13 0 1 0 1] h<224 trackpanmode<6 [0] [51 613 45 13 0 1 0 1] h<275 [0] trackpanmode<6 [0] [51 464 49 13 0 1 0 1]',
    'set mcp.width h<170 mcp.width.label h<224 trackpanmode<6 [72 586 24 27 0 1 0 1] [56 581 34 34 0 1 0 1] h<275 [0] trackpanmode<6 [72 437 24 27 0 1 0 1] [56 432 34 34 0 1 0 1]',
    'set mcp.mute h<103 [0] h<224 [5 25 20 20 0 0 0 0] h<300 [0] [5 407 20 20 0 1 0 1]', 'set mcp.solo h<103 [0] h<224 [29 25 20 20 0 0 0 0] h<300 [0] [29 407 20 20 0 1 0 1]',
    'set mcp.recarm h<194 [0] h<224 [53 49 20 20 0 0 0 0] h<300 [0] [53 407 20 20 0 1 0 1]', 'set mcp.recmon h<194 [0] h<224 [77 49 20 20 0 0 0 0] h<300 [0] [77 407 20 20 0 1 0 1]',
    'set mcp.phase h<194 [0] h<224 [5 49 20 20 0 0 0 0] h<324 [0] [5 383 20 20 0 1 0 1]', 'set mcp.env h<194 [0] h<224 [29 49 20 20 0 0 0 0] h<324 [0] [29 383 20 20 0 1 0 1]',
    'set mcp.recmode [0]', 'set mcp.extmixer.mode [1]', 'set mcp.extmixer.position [6 20 92 342 0 0 0 1]', 'set mcp.fx h<358 [0] [86 5 10 10 0 0 0 0]',
    'set mcp.fxbyp h<358 [0] [6 5 10 10 0 0 0 0]', 'set mcp.io h<343 [0] [86 364 10 10 0 1 0 1]', 'set col_width / 84 mcp_fx_columns',
    'set mcp.fxlist.font [16 23 col_width{0} 300 0 0 0 0]', 'set mcp.fxlist.margin [4 0 4 0 0.5]', 'set mcp.sendlist.font [16 23]', 'set mcp.sendlist.margin [4 0 2 0 0]',
    'set master.mcp.size + mcp.size [100]', 'set master.mcp.volume.label h<101 [0] [6 630 90 16 0 1 0 1]', 'set master.mcp.volume h<224 master.mcp.volume.label [40 477 22 157 0 1 0 1]',
    'set master.mcp.meter [102 5 94 684 0 0 0 1]', 'set master.mcp.mute h<83 [0] h<224 [5 5 20 20 0 0 0 0] h<300 [0] [5 407 20 20 0 1 0 1]',
    'set master.mcp.solo h<83 [0] h<224 [29 5 20 20 0 0 0 0] h<300 [0] [29 407 20 20 0 1 0 1]', 'set master.mcp.menubutton h<83 [0] h<224 [77 5 20 20 0 0 0 0] mcp.phase',
    'set master.mcp.mono h<174 [0] h<224 [5 29 20 20 0 0 0 0] mcp.recmon', 'set master.mcp.env h<174 [0] h<224 [29 29 20 20 0 0 0 0] mcp.recarm',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return true
end
local function imperial_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  for _,s in ipairs({
    'set need_extmix_h + 4 mcp_wantextmix<=2 38 mcp_wantextmix==3 68 mcp_wantextmix==4 40 mcp_wantextmix==5 61 mcp_wantextmix==6 73 mcp_wantextmix==7 87',
    'set have_extmix_h - - - - - - - h 400 block_top{h} block_auto{h} block_fx{h} block_recmode{h} block_monitor{h} block_pan{h}', 'set lost_extmixer have_extmix_h{0}<need_extmix_h{0} 1 0',
    'set block_extmixer + + [0 block_top{h}] [0 block_auto{h}] [0 block_fx{h}]',
    'set block_extmixer - - - - - [0 block_extmixer 74 h] [0 0 0 400] [0 0 0 block_extmixer{1}] [0 0 0 block_recmode{h}] [0 0 0 block_monitor{h}] [0 0 0 block_pan{h}]', 'macro draw_mcp', 'set mcp.size [94 874 0 397]',
    'set h_delta - h mcp.size{y}', 'set block_top [0 0 0 172]', 'set block_auto h<dividers_hide{0} [0 0 0 22] [0 0 0 29]', 'set block_fx [0 0 0 45]', 'set block_monitor [0 0 0 71]',
    'set block_recmode h<dividers_hide{0} [0 0 0 26] [0 0 0 38]', 'set block_pan [0 0 0 93]', 'set block_auto ?lost_extmixer{0} [0] [0 block_top{h} 94 block_auto{h}]',
    'set block_fx ?lost_extmixer{0} [0] + [0 block_auto{h} 94 block_fx] [0 block_top{h}]', 'set block_recmode ?lost_extmixer{0} [0] + - - [0 h] [0 400] [0 block_pan{h}] * [0 -1 0 1] block_recmode{h}',
    'set block_monitor ?lost_extmixer{0} [0] + - - - [0 h] [0 400] [0 block_recmode{h}] [0 block_pan{h}] * [0 -1 0 1] block_monitor{h}', 'set block_top ?lost_extmixer{0} [0] [0 0 94 block_top]',
    'set block_pan ?lost_extmixer{0} [0] + - [0 h] [0 400] * [0 -1 0 1] block_pan{h}', 'set mcp.volume.label block_top{h}<1 [0] [52 22 37 7]', 'set mcp.volume.label.color [30 150 168]', 'set mcp.meter block_top{h}<1 [0] [6 6 38 88]',
    'set mcp.meter.readout.color [168 103 80 150 224 110 79 255]', 'set mcp.meter.scale.color.unlit.top ?recarm [255 0 0 255 0 0 0 255] [64 22 0 0]', 'set mcp.meter.scale.color.unlit.bottom ?recarm [255 0 89 255 0 0 0 255] [33 0 10 0]',
    'set mcp.recinput block_top{h}<1 [0] [4 100 85 11]', 'imageshift mcp.recinput recarm 2 2', 'set mcp.recinput.color ?recarm [255 60 60] [66 113 127]', 'set mcp.io block_top{h}<1 [0] [18 138 16 16]',
    'set mcp.fxin block_top{h}<1 [0] [61 135 21 21]', 'set mcp.env block_auto{h}<1 [0] + [0 block_auto] block_auto{h}<27 [9 0 76 23] [9 0 76 30]', 'set mcp.fx block_fx{h}<1 [0] + [0 block_fx] block_auto{h}<27 [10 0 73 32] [10 0 73 38]',
    'set mcp.fxbyp block_fx{h}<1 [0] + [0 block_fx] block_auto{h}<27 [66 3 16 16] [66 9 16 16]', 'set mcp.extmixer.position + block_extmixer [10 2 0 -2]', 'set mcp.recmon block_monitor{h}<1 [0] + [0 block_monitor] [16 55 21 21]',
    'set mcp.recarm block_monitor{h}<1 [0] + [0 block_monitor] [50 21 34 22]', 'set mcp.recmode block_recmode{h}<1 [0] + [0 block_recmode] block_recmode{h}<38 [8 0 77 33] [8 4 77 35]',
    'set mcp.pan block_pan{h}<1 [0] + [0 block_pan] trackpanmode<4 [26 25 42 42] trackpanmode==6 [12 35 28 28] [9 23 75 19]', 'set mcp.pan.fadermode trackpanmode==5 [0] [1]', 'set mcp.pan.color [204 204 204 255]',
    'set mcp.pan.label block_pan{h}<1 [0] + [0 block_pan] trackpanmode<4 [31 74 32 10] trackpanmode==6 [11 72 30 10] [51 7 31 10]', 'set mcp.pan.label.color [30 150 168]',
    'set mcp.width block_pan{h}<1 [0] + [0 block_pan] trackpanmode==5 [9 65 75 19] trackpanmode==6 [53 35 28 28] [0]', 'set mcp.width.fadermode trackpanmode==6 [1] [0]',
    'set mcp.width.label block_pan{h}<1 [0] + [0 block_pan] trackpanmode==5 [51 49 32 10] trackpanmode==6 [51 72 32 10] [0]', 'set mcp.width.label.color [30 150 168]', 'set mcp.label [0 476 94 18 0 1 0 1]',
    'imageshift mcp.label trackcolor_valid 3 3', 'imageshift mcp.label recarm 2 3', 'set mcp.label.margin [5 1 5 1 0.5]',
    'set mcp.label.color ?recarm [255 180 180] ?trackcolor_valid + [trackcolor_r trackcolor_g trackcolor_b] [100 100 100] [128 251 255]', 'set mcp.volume [22 556 30 306 0 1 0 1]', 'set mcp.phase [71 572 14 14 0 1 0 1]',
    'set mcp.mute [71 608 14 14 0 1 0 1]', 'set mcp.solo [47 507 35 35 0 1 0 1]', 'set mcp.trackidx [56 851 29 17 0 1 0 1]', 'set mcp.trackidx.color ?recarm [200 30 30] [204 204 204]', 'macro draw_mcp_master',
    'set master.mcp.size [118 874 0 397]', 'set block_top h<meter_h{x} [0 0 0 0] [0 0 94 174]', 'set block_auto h<auto_h{x} [0 0 0 0] h<auto_s{x} [11 block_top{h} 94 22] [11 block_top{h} 94 29]',
    'set block_monitor h<monitor_h{x} [0 0 0 0] [0 0 0 109]', 'set block_pan h<pan_h{x} [0 0 0 0] [0 0 0 93]',
    'set block_insert - - - - + + [0 block_top{h}] [0 block_auto{h} 94 476] [0 0 0 h_delta] [0 0 0 block_top{h}] [0 0 0 block_auto{h}] [0 0 0 block_monitor{h}] [0 0 0 block_pan{h}]',
    'set block_pan + + + [0 block_top{h}] [0 block_auto{h}] [0 block_insert{h}] [12 block_monitor{h} 94 block_pan]', 'set master.mcp.meter block_top{h}<1 [0] [13 13 92 150]', 'set master.mcp.volume.label [32 478 79 13 0 1 0 1]',
    'set master.mcp.env block_auto{h}<1 [0] + [block_auto block_auto] block_auto{h}<27 [9 0 76 23] [9 0 76 30]', 'set master.mcp.fx block_insert{h}<1 [0] h<fx_h{x} [0] + [0 block_insert] block_auto{h}<27 [21 0 73 32] [21 0 73 38]',
    'set master.mcp.fxbyp block_insert{h}<1 [0] h<fx_h{x} [0] + [0 block_insert] block_auto{h}<27 [80 3 16 16] [80 9 16 16]',
    'set master.mcp.extmixer.position block_insert{h}<1 [0] + [0 block_insert 0 block_insert] h<fx_h{x} [10 2 98 -6] master.mcp.fx{h}<38 [10 41 98 -45] [10 47 98 -51]', 'set master.mcp.io block_monitor{h}<1 [0] [82 346 16 16 0 1 0 1]',
    'set master.mcp.label block_monitor{h}<1 [0] [0 475 3 3 0 1 0 1]', 'set master.mcp.pan block_pan{h}<1 [0] + [block_pan block_pan] trackpanmode<4 [26 25 42 42] trackpanmode==6 [12 35 28 28] [9 23 75 19]',
    'set master.mcp.pan.fadermode trackpanmode==5 [0] [1]', 'set master.mcp.pan.label block_pan{h}<1 [0] + [block_pan block_pan] trackpanmode<4 [31 74 32 10] trackpanmode==6 [11 72 30 10] [51 7 31 10]',
    'set master.mcp.width block_pan{h}<1 [0] + [block_pan block_pan] trackpanmode==5 [9 65 75 19] trackpanmode==6 [53 35 28 28] [0]', 'set master.mcp.width.fadermode trackpanmode==6 [1] [0]',
    'set master.mcp.width.label block_pan{h}<1 [0] + [block_pan block_pan] trackpanmode==5 [51 49 32 10] trackpanmode==6 [51 72 32 10] [0]', 'set master.mcp.solo [64 507 35 35 0 1 0 1]', 'set master.mcp.mute [82 608 14 14 0 1 0 1]',
    'set master.mcp.menubutton [76 638 26 32 0 1 0 1]', 'set master.mcp.mono [14 505 42 58 0 1 0 1]', 'set master.mcp.volume [25 556 30 306 0 1 0 1]', 'set dividers_hide 960', 'set meter_h 638', 'set auto_s 912', 'set auto_h 887',
    'set fx_h 770', 'set monitor_h 912', 'set pan_h 729',
  }) do
    if not script:find(' '..s..' ',1,true) then return false end
  end
  return script:find(" draw_mcp Layout 'a1-- Default' draw_mcp ",1,true)~=nil
end
-- Older Imperial siblings (WT Imperial and Imperial LCS-mod dark v3): one mixer script skeleton with two sets of numbers, the unnamed base layout
-- of each (`clear mcp.*` / `clear master.mcp.*` up to the first named layout). Recognised by these exact statements (rectangles and the text colours the
-- layout draws); the Inspector reads its geometry from them too. Anything changed, or the base missing, falls back to the generic strip.
local IMPERIAL_OLD={
  wt={track=[[
size [94 874]
meter tracknch<3 [9 7 24 100 0 0 0 0] [2 7 42 100 0 0 0 0]
recinput [44 98 40 10 0 0 0 0]
recinput.color ?recarm [255 160 72] [78 91 102]
trackidx [2 479 17 13 0 1 0 1]
trackidx.color ?recarm [255 100 100] [163 171 179]
label [21 475 72 20 0 1 0 1]
label.color [80 80 80]
volume [22 556 30 306 0 1 0 1]
volume.label [47 21 36 7 0 0 0 0]
volume.label.color [80 100 117]
pan trackpanmode<4 [29 409 36 36 0 1 0 1] trackpanmode==6 [12 417 27 27 0 1 0 1] [18 400 58 12 0 1 0 1]
pan.color [204 204 204 255]
pan.label trackpanmode<4 [31 457 32 10 0 1 0 1] trackpanmode==6 [9 455 30 10 0 1 0 1] [12 416 30 10 0 1 0 1]
pan.label.color [108 118 123]
width trackpanmode==5 [18 447 58 12 0 1 0 1] trackpanmode==6 [53 417 27 27 0 1 0 1] [0]
width.label trackpanmode==5 [11 432 32 10 0 1 0 1] trackpanmode==6 [51 455 32 10 0 1 0 1] [0]
width.label.color [108 118 123]
io [17 137 18 23 0 0 0 0]
fxin [60 135 21 24 0 0 0 0]
fx [11 211 21 24 0 0 0 0]
fxbyp [66 213 18 23 0 0 0 0]
env [12 183 12 12 0 0 0 0]
recarm [50 293 34 22 0 1 0 1]
recmon [16 328 21 24 0 1 0 1]
recmode [32 359 22 21 0 1 0 1]
phase [71 572 14 14 0 1 0 1]
mute [71 608 14 14 0 1 0 1]
solo [47 507 35 35 0 1 0 1]
extmixer.position [11 253 72 16 0 0 0 1]
]],master=[[
size [118 874]
meter [20 21 78 131 0 0 0 0]
volume.label [56 158 36 7 0 0 0 0]
volume.label.color [80 100 117]
env [24 183 12 12 0 0 0 0]
fx [18 211 21 24 0 0 0 0]
fxbyp [79 213 18 23 0 0 0 0]
io [88 359 18 23 0 1 0 1]
pan [40 409 36 36 0 1 0 1]
pan.label [42 457 32 10 0 1 0 1]
pan.label.color [108 118 123]
label !0 [0 475 117 20 0 1 0 1]
label.color [160 160 160]
solo [64 507 35 35 0 1 0 1]
mute [82 608 14 14 0 1 0 1]
menubutton [76 638 26 32 0 1 0 1]
mono [14 505 42 58 0 1 0 1]
volume [25 556 30 306 0 1 0 1]
extmixer.position [14 253 89 16 0 0 0 1]
]]},
  lcs={track=[[
size [70 874]
meter tracknch<3 [11 7 50 100 0 0 0 0] [2 7 42 100 0 0 0 0]
recinput [7 273 53 9 0 1 0 01]
recinput.color ?recarm [255 160 72] [78 91 102]
trackidx [17 457 20 10 0 1 0 1]
trackidx.color ?recarm [200 0 0] [215 215 215]
label [-1 475 71 20 0 1 0 1]
label.color [30 30 30]
volume [20 556 30 306 0 1 0 1]
volume.label [14 543 36 7 0 1 0 1]
volume.label.color [150 170 184]
pan trackpanmode<4 [17 383 36 36 0 1 0 1] trackpanmode==6 [6 388 27 27 0 1 0 1] [6 385 58 12 0 1 0 1]
pan.color [204 204 204 255]
pan.label trackpanmode<4 [16 430 38 10 0 1 0 1] trackpanmode==6 [5 427 27 10 0 1 0 1] [6 403 27 10 0 1 0 1]
pan.label.color [108 118 123]
width trackpanmode==5 [6 420 58 12 0 1 0 1] trackpanmode==6 [37 388 27 27 0 1 0 1] [0]
width.label trackpanmode==5 [37 403 27 10 0 1 0 1] trackpanmode==6 [37 427 27 10 0 1 0 1] [0]
width.label.color [108 118 123]
io [5 137 18 23 0 0 0 0]
fxin [52 133 15 15 0 0 0 0]
fx [2 174 21 24 0 0 0 0]
fxbyp [49 176 18 23 0 0 0 0]
env [15 159 40 12 0 0 0 0]
recarm [30 303 34 22 0 1 0 1]
recmon [8 304 14 14 0 1 0 1
recmode [24 342 22 21 0 1 0 1]
phase [46 454 14 14 0 1 0 1]
mute [5 507 24 24 0 1 0 1]
solo [40 507 24 24 0 1 0 1]
extmixer.position [4 215 60 52 0 0 1 1]
]],master=[[
size [118 874]
meter [20 21 78 131 0 0 0 0]
volume.label [56 158 36 7 0 0 0 0]
volume.label.color [80 100 117]
env [35 183 50 12 0 0 0 0]
fx [18 211 21 24 0 0 0 0]
fxbyp [79 213 18 23 0 0 0 0]
io [88 359 18 23 0 1 0 1]
pan trackpanmode<=4 [40 408 36 36 0 1 0 1] [40 408 36 36 0 1 0 1]
pan.label [42 457 32 10 0 1 0 1]
pan.label.color trackpanmode<=4 [108 118 123] [218 118 123]
label [7 475 102 20 0 1 0 1]
label.color [30 30 30]
mute [14 508 35 33 0 1 0 1]
menubutton [76 603 26 32 0 1 0 1]
mono [64 506 42 56 0 1 0 1]
volume [25 556 30 306 0 1 0 1]
extmixer.position [14 253 89 102 0 0 0 1]
]]},
}
local function imperial_old_of(cfg)
  local script=' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '
  local function base(start) -- the statements between `clear ...` and the first named layout
    local a=script:find(' '..start..' ',1,true)
    if a then return script:sub(a,(script:find(" Layout '",a,true) or #script)+1) end
  end
  local track,master=base('clear mcp.*'),base('clear master.mcp.*')
  if not (track and master) then return nil end
  for name,set in pairs(IMPERIAL_OLD) do
    local ok=true
    for _,part in ipairs({{'mcp.',set.track,track},{'master.mcp.',set.master,master}}) do
      for key,tail in part[2]:gmatch('(%S+) ([^\n]+)') do
        if not part[3]:find(' set '..part[1]..key..' '..tail..' ',1,true) then ok=false end
      end
    end
    if ok then return name end
  end
end
-- REAPER's old stock themes. 3.0's rtconfig holds fourteen settings and no WALTER at all (REAPER's built-in positions apply), so there is no
-- rectangle to recognise it by: it is this exact script and nothing else. 4.0 is recognised by its default mixer block (the statements up to
-- its first named layout, in which the strip, pan, name, button column, fader and meter rectangles all sit).
local DEFAULT3=' use_pngs 1 tcp_showborders 0 mcp_showborders 0 tcp_vupeakwidth 2 mcp_vupeakheight 4 mcp_mastervupeakheight 4 mcp_altmeterpos 0 use_overlays 0 transport_showborders 1 tcp_vol_zeroline 85000000 tcp_pan_zeroline 67000000 mcp_vol_zeroline 85000000 mcp_pan_zeroline 67000000 trans_speed_zeroline 99999999 '
local DEFAULT4=[[
set mcp.size [73 319]
front mcp.width.label mcp.pan.label mcp.recmon mcp.volume.label
set mcp.folder folderstate<0 [66 300 7 18 0 1 0 1] [0 300 18 18 0 1 0 1]
set mcp.label [1 35 70 18 0 0 0 0]
set mcp.label.margin [2 0 2 0 0.5]
set mcp.label.color ?recarm [255 87 87] [184 184 184]
set mcp_column_anchor [48 105]
set mcp.mute + mcp_column_anchor [0 0 17 18 0 0 0 0]
set mcp.solo + mcp_column_anchor [0 21 17 18 0 0 0 0]
set mcp.recmon + mcp_column_anchor h>273 [0 42 17 14 0 0 0 0] [0 42 17 14 0 0 0 0]
set mcp.recmode + mcp_column_anchor h>273 [0 54 17 22 0 0 0 0] [0]
set mcp.env + mcp_column_anchor h>283 [0 79 17 26 0 0 0 0] h>273 [0 79 17 14 0 0 0 0] h>233 [0 59 17 14 0 0 0 0] [0]
set mcp.phase + mcp_column_anchor h>283 [1 108 15 16 0 0 0 0] h>273 [1 96 15 16 0 0 0 0] h>251 [1 76 15 16 0 0 0 0] [0]
set mcp.recarm [41 260 20 33 0 1 0 1]
set mcp.meter.vu.div [2 1]
set mcp.meter h>273 [27 123 12 166 0 0 0 1] [27 112 12 177 0 0 0 1]
set mcp.meter.readout.color [255 255 255 140 255 255 255 200]
set mcp.volume h>273 [9 119 17 173 0 0 0 1] [9 108 17 184 0 0 0 1]
set mcp.volume.label h>273 [7 105 35 14 0 0 0 0] [7 105 35 3 0 0 0 0]
set mcp.volume.label.color [179 179 179]
set mcp.volume.label.margin h>273 [1 5 0 0 0.5] [52 5 53 0 0.5]
set mcp.pan trackpanmode>=4 [6 62 18 18 0 0 0 0] [4 65 30 30 0 0 0 0]
set mcp.pan.color [51 51 51 191 0 0 0 0]
set mcp.pan.label trackpanmode>=4 [24 63 41 16 0 0 0 0] [31 72 34 16 0 0 0 0]
set mcp.pan.label.color [221 224 224]
set mcp.pan.label.margin [0 0 3 0 1]
set mcp.width trackpanmode>=4 [6 82 18 18 0 0 0 0] [0]
set mcp.width.color [255 255 255 225 0 0 0 0]
set mcp.width.label trackpanmode>=4 [24 83 41 16 0 0 0 0] [0]
set mcp.width.label.color [221 224 224]
set mcp.width.label.margin [0 0 3 0 1]
set mcp.io ?recarm [30 18 39 16 0 0 0 0] [30 3 39 31 0 0 0 0]
set mcp.fx [3 17 23 17 0 0 0 0]
set mcp.fxbyp [3 3 23 14 0 0 0 0]
set mcp.fxin ?recarm [30 3 39 14 0 0 0 0] [0]
set mcp.extmixer.mode [0]
set mcp.trackidx [19 300 35 18 0 1 0 1]
set mcp.trackidx.margin [0 3 0 5 0.5]
set mcp.trackidx.color ?recarm [200 0 0] [67 69 69]
]]
local function default34_of(cfg)
  local script=(' '..cfg:gsub(';[^\r\n]*',''):gsub('\\%s*[\r\n]',' '):gsub('%s+',' ')..' '):gsub('%s+',' ')
  if script==DEFAULT3 then return 3 end
  local a=script:find(' clear mcp.* ',1,true)
  local block=a and script:sub(a,(script:find(' Layout ',a,true) or #script)+1)
  if not block then return nil end
  for stmt in DEFAULT4:gmatch('[^\n]+') do
    if not block:find(' '..stmt..' ',1,true) then return nil end
  end
  return 4
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
  if cfg:find('macro%s+drawMcp%s+scale%s+layout%s+alt') and horizon_of(cfg) then return 'horizon' end
  if cfg:find('macro%s+drawMcp%s+scale%s') and reatools_of(cfg) then return 'reatools' end
  if cfg:find('macro%s+MAC_DrawMcp%s') and part_of(cfg) then return 'part' end
  if not cfg:find('macro%s+draw') and cfg:find('set mcp.size [72 902]',1,true) and realogix_of(cfg) then return 'realogix' end
  if not cfg:find('macro%s+draw') and cfg:find('set mcp.size [102 702]',1,true) and echolot_of(cfg) then return 'echolot' end
  if cfg:find('macro%s+draw_mcp%s') and imperial_of(cfg) then return 'imperial' end
  local old=not cfg:find('macro%s+draw_mcp') and imperial_old_of(cfg)
  if old then return 'imperial2',nil,nil,nil,nil,nil,nil,nil,old end
  if not cfg:find('macro%s+drawMcp') and cfg:find('set mcp_narrow',1,true) then
    local gray=gray80_of(cfg)
    if gray then return 'gray80',nil,nil,nil,nil,nil,gray end
  end
  local d34=default34_of(cfg)
  if d34 then return 'default34',nil,nil,nil,nil,nil,nil,nil,nil,d34 end
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
  t.layout,t.stock6,t.recarm_y,t.label_h,t.compact6,t.full_art,t.gray80,t.ix,t.imp2,t.d34 = layout_of(cfg)
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
  if t.layout=='imperial' then
    -- 14 pt list cells (its fx/send list art is 14 rows a state; the 21 the generic reader finds is commented out). The mixer's faces are Tahoma
    -- (lb_font, 9 px: lists, readouts, input), Calibri 13 (name) and Calibri 16 bold (number), which REAPER shows in a Helvetica-like substitute
    -- (measured against the native screenshot: em 13 and 16 pt). The art exists only in the base folder and is drawn at the display's density.
    t.row_height,t.send_row_height = 14,14
    t.font,t.fonts = 'Tahoma',{main={11.4},list={11.4},sends={11.4},header={16.5,false,'Arial'},bold={20.3,true,'Arial'}}
  end
  if t.layout=='imperial2' then
    -- The geometry the layout draws, parsed from the recognised statements: `o[kind][key]` is the list of [numbers] in the order they are written
    -- (a pan-mode condition picks one of them). Lists are 14 pt cells (WT) or 12 pt rows (the LCS script's `mcp.fxlist.font [2 12]`) on the same 14 row
    -- art; the faces are Tahoma (lb_font) and Arial, which REAPER shows in Helvetica-like substitutes (em sizes measured as for V5).
    local o={}
    for kind,body in pairs(IMPERIAL_OLD[t.imp2]) do
      o[kind]={}
      for key,tail in body:gmatch('(%S+) ([^\n]+)') do
        local list={};for inner in tail:gmatch('%[([%d%s%.%-]+)') do local r={};for n in inner:gmatch('%-?[%d%.]+') do r[#r+1]=tonumber(n) end;list[#list+1]=r end
        o[kind][key]=list
      end
    end
    t.old=o
    t.row_height=t.imp2=='lcs' and 12 or 14;t.send_row_height=t.row_height
    t.font,t.fonts = 'Tahoma',{main={11.4},list={11.4},sends={11.4},header={13.9,false,'Arial'},bold={13.6,true,'Arial'}}
    if t.imp2=='lcs' then t.fonts.list,t.fonts.sends={13.9,true,'Arial'},{13.9,true,'Arial'} end -- its lists use font #2, Arial bold
  end
  if t.layout=='reatools' then
    -- Lists are 18 pt rows (fxlist.font [8 36]); every mixer label is Arial bold: user_font7 (16 px) for lists, pan and value text and the track number,
    -- user_font9/10 (21 px) for the name and the input field (gfx sizes that render as large as the mixer's: about 0.63 of the pixel size at 2x).
    t.row_height,t.send_row_height = 18,18
    t.font,t.fonts = 'Arial',{main={10.1,true},list={10.1,true},sends={10.1,true},header={13.3,true},bold={10.1,true}}
    -- The edition's green (readouts, pan text, track number) and input-field ink: the uncommented `set` lines of its script.
    local function rgb(name,d) local r,g,b=cfg:match('\nset[ \t]+'..name..'[ \t]+%[(%d+)[ \t]+(%d+)[ \t]+(%d+)%]') return r and {tonumber(r),tonumber(g),tonumber(b)} or d end
    t.rt={green=rgb('PTGreen',{56,209,119}),input=rgb('PTrecinput',{203,203,203})}
    colors.col_tcp_textsel=named('col_tcp_textsel')
  end
  if t.layout=='default34' then
    -- Lists are 14 pt rows (the art's three states of 14); labels are the theme's mixer face (Microsoft Sans Serif 11 px, which REAPER shows in a Helvetica-like substitute).
    t.row_height,t.send_row_height = 14,14
    t.font,t.fonts = 'Arial',{main={13},list={13.4},sends={13.4},header={14.5},bold={13}}
  end
  if t.layout=='realogix' then
    -- Lists are 17 pt rows (fxlist.font [4 17]). Faces from its .ReaperTheme: lists Verdana bold 9 px (user_font3), labels and values Verdana 9 px (user_font7),
    -- the name Calibri bold 12 px (user_font2; the native screenshot shows a regular sans, so Arial regular here), the number Verdana bold 11 px (user_font4): gfx sizes 1.27 x the pixel em.
    t.row_height,t.send_row_height = 17,17
    t.font,t.fonts = 'Verdana',{main={11.4},list={11.4,true},sends={11.4,true},header={15.6,false,'Arial'},bold={13.9,true}}
  end
  if t.layout=='echolot' then
    -- Lists are 23 pt rows (fxlist.font [16 23]). Every mixer label is Arial (user_font0/13/14/15, lb_font): the name 11 px bold (measured), the others 9-11 px;
    -- gfx sizes about 1.27 x the pixel em. Its 100% art is shown at twice the size (1 art px = 1 pt).
    t.row_height,t.send_row_height = 23,23
    t.font,t.fonts = 'Arial',{main={11.4},list={14},sends={14},header={13.6,true},bold={14}}
  end
  if t.layout=='part' then
    -- Lists are 17 pt rows (insert slot 34 px); every mixer label is Tahoma regular, user_font7 (24 px, an em of 12 pt: a gfx size of about 15).
    t.row_height,t.send_row_height = 17,17
    t.font,t.fonts = 'Tahoma',{main={15.2},list={15.2},sends={15.2},header={15.2},bold={11.7}} -- (`bold` is the meter's scale: its numbers are a third smaller than the labels')
    -- The editions differ only in these constants of their script (`set THEME_color_x [r g b ...]`) and the zero-line colour of their sliders.
    local function nums(name) local body=cfg:match('\nset[ \t]+THEME_color_'..name..'[ \t]+%[([^%]]*)%]') if not body then return nil end local o={} for n in body:gmatch('%-?%d+') do o[#o+1]=tonumber(n) end return o end
    t.pt={}
    for _,k in ipairs({'track_neutral','track_frame','mcp_empty_space','track_bg','track_label_bg','track_label_text','select_bar','master_icon_bg','readout_font','button_text_off'}) do t.pt[k]=nums(k) end
    local a,rgb=cfg:match('\nmcp_pan_zeroline[ \t]+(%x%x)(%x%x%x%x%x%x)')
    t.pt.zero=a and {tonumber(rgb:sub(1,2),16),tonumber(rgb:sub(3,4),16),tonumber(rgb:sub(5,6),16),tonumber(a,16)} or {255,255,255,96}
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
  -- Horizon declares its Theme Adjuster values through a `defp name default min max 'text'` macro.
  if t.layout=='horizon' then source = (source:gsub('\n[ \t]*defp[ \t]+([%w_%.]+)[ \t]+(%-?%d+)','\ndefine_parameter %1 \'.\' %2')) end
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
  if t.layout=='horizon' then
    -- 'List elements' 1-5 (default 1) make 8-16 pt cells on a pitch two points taller; the size picks the theme's small, medium or large
    -- user font. Every mixer label is bold Arimo (user_font6-8: 17, 20 and 23 px at 200%; measured against the native text, which is about 0.97 of that as an em and matches the bold face's ink to 2%).
    local n=math.max(1,math.min(5,t.param('mcp_list_h_size',1)))
    t.row_height=8+2*n;t.send_row_height=t.row_height
    local list=n>=4 and 14.3 or n>=3 and 12.4 or 10.6
    t.font,t.fonts='Arimo',{main={list,true},list={list,true},sends={list,true},header={14.3,true},bold={12.4,true}}
    -- Washes and pan colours are named in the script by tone and palette numbers; both editions define the same ones.
    t.tone,t.palette={},{}
    for n,r,g,b in cfg:gmatch('\n[ \t]*def[ \t]+tone(%d+)[ \t]+(%d+)[ \t]+(%d+)[ \t]+(%d+)') do t.tone[tonumber(n)]={tonumber(r),tonumber(g),tonumber(b)} end
    for n,r,g,b in cfg:gmatch('\n[ \t]*def[ \t]+color(%d+)[ \t]+(%d+)[ \t]+(%d+)[ \t]+(%d+)') do t.palette[tonumber(n)]={tonumber(r),tonumber(g),tonumber(b)} end
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
        local path = join(t.dir,(v[1] ~= '' and v[1]..'_' or '')..(name:gsub('/','__'))..'.png') -- a name may carry a folder (`ci/...`)
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
