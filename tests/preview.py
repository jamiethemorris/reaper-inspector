#!/usr/bin/env python3
"""Offline developer preview: renders one Inspector frame to a PNG without REAPER.

Runs the production Lua view against a synthetic track and a Pillow-backed gfx
stand-in. It is an approximation for layout work (fonts, blending and rounding
are not REAPER's), never evidence of native rendering. Needs `pip install lupa
pillow numpy` in a private venv; the runtime itself has no such dependency.

  python tests/preview.py OUT.png [--w 122] [--h 922] [--scale 2] [--scenario plain|busy]
                                  [--mouse X,Y] [--theme PATH] [--full-artwork]
"""
import argparse
import ast
import os
import sys

import numpy as np
from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIRS = [os.path.expanduser('~/Library/Fonts'), '/Library/Fonts', '/System/Library/Fonts/Supplemental']


def font_path(name, bold):
    stem = name.replace(' ', '') + ('-Bold' if bold else '-Regular')
    for d in FONT_DIRS:
        for ext in ('.ttf', '.otf'):
            p = os.path.join(d, stem + ext)
            if os.path.exists(p):
                return p
    return '/System/Library/Fonts/Supplemental/Arial.ttf'


class Gfx:
    def __init__(self, lua, w, h, scale):
        self.lua, self.scale = lua, scale
        self.fb = Image.new('RGBA', (w, h), (0, 0, 0, 255))
        self.images, self.fonts, self.font, self.byidx = {}, {}, None, {}
        self.color = (255, 255, 255)
        t = self.t = lua.table()
        for k, v in dict(w=w, h=h, x=0, y=0, dest=-1, mode=0, a=1, mouse_x=0, mouse_y=0, mouse_cap=0,
                         mouse_wheel=0, ext_retina=scale).items():
            t[k] = v
        for name in ('init dock set rect line setfont drawstr measurestr loadimg getimgdim getpixel setimgdim '
                     'blit muladdrect update quit getchar showmenu triangle circle').split():
            t[name] = getattr(self, name)
        self.setfont(1, 'Fira Sans', 12 * scale, 0)

    # -- plumbing
    def target(self):
        d = int(self.t['dest'])
        return self.fb if d < 0 else self.images[d]

    def init(self, *a): self.t['ext_retina'] = self.scale
    def dock(self, d, *a): return 0, 0, 0, self.fb.size[0] / self.scale, self.fb.size[1] / self.scale
    def update(self): pass
    def quit(self): pass
    def getchar(self, *a): return 0
    def showmenu(self, *a): return 0

    def set(self, r, g=None, b=None, a=None, *rest):
        g = r if g is None else g
        b = r if b is None else b
        self.color = tuple(int(round(max(0, min(1, c)) * 255)) for c in (r, g, b))
        if a is not None:
            self.t['a'] = a

    def rgba(self):
        return self.color + (int(round(max(0, min(1, float(self.t['a']))) * 255)),)

    def rect(self, x, y, w, h, filled=1):
        x, y, w, h = (int(round(v)) for v in (x, y, w, h))
        if w <= 0 or h <= 0:
            return
        layer = Image.new('RGBA', (w, h), self.rgba())
        if not filled:
            ImageDraw.Draw(layer).rectangle((1, 1, w - 2, h - 2), fill=(0, 0, 0, 0))
        self.target().alpha_composite(layer, (x, y)) if x >= 0 and y >= 0 else None

    def line(self, x, y, x2, y2, aa=1):
        layer = Image.new('RGBA', self.target().size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).line((round(x), round(y), round(x2), round(y2)), fill=self.rgba(), width=1)
        self.target().alpha_composite(layer)

    def circle(self, x, y, r, fill=0, aa=1):
        layer = Image.new('RGBA', self.target().size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse((x - r, y - r, x + r, y + r), fill=self.rgba() if fill else None, outline=self.rgba())
        self.target().alpha_composite(layer)

    def triangle(self, *pts):
        layer = Image.new('RGBA', self.target().size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon([(pts[i], pts[i + 1]) for i in range(0, len(pts), 2)], fill=self.rgba())
        self.target().alpha_composite(layer)

    def setfont(self, idx, name=None, size=None, flags=0):
        idx = int(idx)
        if name is None:
            self.font = self.byidx.get(idx, self.font)
            return
        bold = isinstance(flags, (int, float)) and int(flags) == ord('b')
        # REAPER's gfx text on macOS comes out near 0.79 of the requested size (measured from a screenshot).
        key = (name, max(1, int(round(size * 0.79))), bold)
        if key not in self.fonts:
            self.fonts[key] = ImageFont.truetype(font_path(name, bold), key[1])
        self.font = self.byidx[idx] = self.fonts[key]

    def measurestr(self, s):
        asc, desc = self.font.getmetrics()
        return self.font.getlength(str(s)), asc + desc

    def drawstr(self, s, flags=0, right=None, bottom=None):
        s = str(s)
        x, y = float(self.t['x']), float(self.t['y'])
        w, h = self.measurestr(s)
        flags = int(flags or 0)
        right = x + w if right is None else float(right)
        bottom = y + h if bottom is None else float(bottom)
        tx, ty = x, y
        if flags & 1: tx = x + (right - x - w) / 2
        elif flags & 2: tx = right - w
        if flags & 4: ty = y + (bottom - y - h) / 2
        elif flags & 8: ty = bottom - h
        layer = Image.new('RGBA', self.target().size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((tx, ty), s, font=self.font, fill=self.rgba())
        if not flags & 256:
            box = tuple(int(round(v)) for v in (x, y, right, bottom))
            clipped = Image.new('RGBA', layer.size, (0, 0, 0, 0))
            if box[2] > box[0] and box[3] > box[1]:
                clipped.paste(layer.crop(box), box[:2])
            layer = clipped
        self.target().alpha_composite(layer)

    def loadimg(self, slot, path):
        try:
            self.images[int(slot)] = Image.open(path).convert('RGBA')
        except Exception:
            return -1
        return int(slot)

    def getimgdim(self, slot):
        im = self.images.get(int(slot))
        return im.size if im else (0, 0)

    def setimgdim(self, slot, w, h):
        if w <= 0 or h <= 0:
            self.images.pop(int(slot), None)
        else:
            self.images[int(slot)] = Image.new('RGBA', (int(w), int(h)), (0, 0, 0, 0))

    def getpixel(self):
        im = self.target()
        x, y = int(self.t['x']), int(self.t['y'])
        if not (0 <= x < im.size[0] and 0 <= y < im.size[1]):
            return 0, 0, 0
        r, g, b, _ = im.getpixel((x, y))
        return r / 255, g / 255, b / 255

    def blit(self, src, scale, rot, sx=0, sy=0, sw=None, sh=None, dx=None, dy=None, dw=None, dh=None, *rest):
        im = self.images[int(src)]
        sw = im.size[0] if sw is None else sw
        sh = im.size[1] if sh is None else sh
        dx = self.t['x'] if dx is None else dx
        dy = self.t['y'] if dy is None else dy
        dw = sw * scale if dw is None else dw
        dh = sh * scale if dh is None else dh
        box = tuple(int(round(v)) for v in (sx, sy, sx + sw, sy + sh))
        dw, dh, dx, dy = (int(round(v)) for v in (dw, dh, dx, dy))
        if dw <= 0 or dh <= 0 or box[2] <= box[0] or box[3] <= box[1]:
            return
        piece = im.crop(box)
        mode = int(self.t['mode'])
        if piece.size != (dw, dh):
            piece = piece.resize((dw, dh), Image.NEAREST if mode & 4 else Image.BILINEAR)
        a = max(0, min(1, float(self.t['a'])))
        if mode & 2:
            piece.putalpha(255)
        if a < 1:
            piece.putalpha(piece.getchannel('A').point(lambda v: int(v * a)))
        tgt = self.target()
        # manual clip for negative origins
        cx, cy = max(0, -dx), max(0, -dy)
        if cx or cy:
            piece = piece.crop((cx, cy, dw, dh)); dx += cx; dy += cy
        if piece.size[0] > 0 and piece.size[1] > 0 and dx < tgt.size[0] and dy < tgt.size[1]:
            tgt.alpha_composite(piece, (dx, dy))

    def muladdrect(self, x, y, w, h, mr, mg, mb, ma=1, ar=0, ag=0, ab=0, aa=0):
        x, y, w, h = (int(round(v)) for v in (x, y, w, h))
        arr = np.asarray(self.target()).astype(np.float32)
        reg = arr[y:y + h, x:x + w, :3]
        reg[:] = np.clip(reg * np.array([mr, mg, mb]) + np.array([ar, ag, ab]) * 255, 0, 255)
        self.target().paste(Image.fromarray(arr.astype(np.uint8), 'RGBA'))


SCENARIOS = {
    'plain': dict(name='Keys', number=1, color=None, vol=1.0, pan=0.0, recinput=4096 | (63 << 5), arm=0,
                  fx=[('VST3i: Kontakt 8 (Native Instruments)', True, False)], sends=[], peaks=(0, 0), auto=0),
    'busy': dict(name='Lead Vox', number=12, color=(60, 140, 200), vol=10 ** (-4.5 / 20), pan=-0.3, recinput=1024, arm=1,
                 fx=[('VST3: Pro-Q 3 (FabFilter)', True, False), ('VST: ReaComp (Cockos)', False, False),
                     ('JS: Volume Adjustment', True, True), ('My renamed chain', True, False)],
                 sends=[('Reverb Bus', 0.5, False), ('Delay', 1.0, True)], midiout='MIDI Interface',
                 peaks=(0.5, 0.25), auto=1),
}


OTHERS = {
    'MASTER': dict(name='MASTER', number=-1, color=None, vol=1.0, pan=0.0, recinput=-1, arm=0, auto=0, peaks=(0.4, 0.35),
                   fx=[('VST3: Pro-L 2 (FabFilter)', True, False)], sends=[]),
    'BUS': dict(name='Reverb Bus', number=20, color=(150, 90, 170), vol=10 ** (-6 / 20), pan=0.0, recinput=-1, arm=0, auto=0,
                peaks=(0.2, 0.2), fx=[('VST3: ValhallaRoom (Valhalla DSP)', True, False)], sends=[]),
}


def host(lua, sc):
    import math
    proj = 'PROJECT'
    tracks = dict(OTHERS, TRACK=sc)

    def vals(t):
        d = tracks[t]
        v = dict(D_VOL=d['vol'], D_PAN=d['pan'], B_MUTE=0, I_SOLO=0, B_PHASE=0, I_RECARM=d['arm'], I_RECMON=0,
                 IP_TRACKNUMBER=d['number'], I_RECINPUT=d['recinput'], I_PANMODE=3, I_AUTOMODE=d['auto'], I_FXEN=1,
                 I_RECMODE=0, I_NCHAN=2, B_MAINSEND=1, I_MIDIHWOUT=0 if d.get('midiout') else -1)
        v.update(d.get('vals') or {})
        return v

    def color(t):
        c = tracks[t]['color']
        return 0 if not c else 0x1000000 | (c[0] << 16) | (c[1] << 8) | c[2]

    def send(t, i, k):
        row = tracks[t]['sends'][int(i)]
        return {'D_VOL': row[1], 'B_MUTE': 1 if row[2] else 0, 'P_DESTTRACK': 'BUS' if int(i) == 0 else 'OTHERBUS'}.get(k, 0)

    r = dict(
        EnumProjects=lambda i, *a: (proj, ''), GetSelectedTrack2=lambda *a: 'TRACK',
        ValidatePtr2=lambda p, t, *a: t in tracks,
        GetMasterTrack=lambda p: 'MASTER', GetParentTrack=lambda t: None,
        GetTrackGUID=lambda t: '{%s}' % t, GetTrackName=lambda t, *a: (True, tracks[t]['name']),
        GetTrackColor=color,
        ColorFromNative=lambda c: ((int(c) >> 16) & 255, (int(c) >> 8) & 255, int(c) & 255),
        GetMediaTrackInfo_Value=lambda t, k: vals(t).get(k, 0),
        GetTrackNumSends=lambda t, cat: len(tracks[t]['sends']) if cat == 0 else 0,
        GetTrackSendName=lambda t, i, *a: (True, tracks[t]['sends'][int(i)][0]),
        GetTrackSendInfo_Value=lambda t, cat, i, k: send(t, i, k),
        GetMIDIOutputName=lambda i, *a: (True, sc.get('midiout') or ''),
        Track_GetPeakInfo=lambda t, c: tracks[t]['peaks'][int(c)] if int(c) < 2 else max(tracks[t]['peaks']) * 0.5,
        TrackFX_GetCount=lambda t: len(tracks[t]['fx']),
        TrackFX_GetFXName=lambda t, i, *a: (True, tracks[t]['fx'][int(i)][0]),
        TrackFX_GetFXGUID=lambda t, i: '{FX%d}' % i,
        TrackFX_GetEnabled=lambda t, i: tracks[t]['fx'][int(i)][1], TrackFX_GetOffline=lambda t, i: tracks[t]['fx'][int(i)][2],
        GetNumMIDIInputs=lambda: 0, GetNumAudioInputs=lambda: 2,
        GetInputChannelName=lambda i: 'Input %d' % (int(i) + 1),
        GetMIDIInputName=lambda i, s: (False, ''),
        DB2SLIDER=lambda db: 0.0 if db <= -150 else 716.0 * 10 ** (db / 80),
        SLIDER2DB=lambda v: -150.0 if v <= 0 else 80 * math.log10(v / 716.0),
        time_precise=lambda: 100.0, GetOS=lambda: 'macOS-arm64',
        GetExtState=lambda *a: '', SetExtState=lambda *a: None,
    )
    t = lua.table_from(r)
    # Lua-side wrappers: the model only trusts real Lua functions for the native fader mapping.
    lua.eval('function(t) local a,b=t.DB2SLIDER,t.SLIDER2DB;t.DB2SLIDER=function(x) return a(x) end;t.SLIDER2DB=function(x) return b(x) end end')(t)
    return t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--w', type=float, default=122); ap.add_argument('--h', type=float, default=922)
    ap.add_argument('--scale', type=int, default=2); ap.add_argument('--scenario', default='plain')
    ap.add_argument('--mouse', default=None); ap.add_argument('--theme', default=None)
    ap.add_argument('--live', default=None, help='Theme Adjuster values, e.g. LayoutA-verboseMcp=1,selDot=0')
    ap.add_argument('--target', default='main', help="output strip target: main, send (first send) or off")
    ap.add_argument('--set', action='append', default=[], help='scenario override key=python-literal')
    ap.add_argument('--full-artwork', action='store_true', help='the experimental full theme artwork toggle')
    a = ap.parse_args()
    sc = dict(SCENARIOS[a.scenario])
    for item in a.set:
        k, v = item.split('=', 1); sc[k] = ast.literal_eval(v)
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = Gfx(lua, int(a.w * a.scale), int(a.h * a.scale), a.scale)
    if a.mouse:
        mx, my = (float(v) for v in a.mouse.split(','))
        g.t['mouse_x'], g.t['mouse_y'] = mx * a.scale, my * a.scale
    r = host(lua, sc)
    run = lua.eval('''function(root, r, g, theme_path, out, live, full)
      local Theme, Model, View = dofile(root..'/inspector/theme.lua'), dofile(root..'/inspector/model.lua'), dofile(root..'/inspector/view.lua')
      local home = os.getenv('HOME')
      theme_path = theme_path or home..'/Library/Application Support/REAPER/ColorThemes/Reapertips Theme_Custom2.ReaperTheme'
      local cache = (os.getenv('TMPDIR') or '/tmp'):gsub('/+$', '')..'/reaper-inspector-preview'
      local theme, err = Theme.resolve(theme_path, {cache = cache, mkdir = function(p) os.execute('mkdir -p "' .. p .. '"') end})
      assert(theme, err)
      if live then theme.live = {}; for k, v in live:gmatch('([^=,]+)=(%-?%d+)') do theme.live[k] = tonumber(v) end end
      local view = View.new(r, g, Model.new(r), theme, {output_strip = out ~= 'off', full_theme_artwork = full})
      view:frame()
      if out == 'send' then view.choice[view.snapshot.guid] = 'BUS'; view:frame() end
      return view.bitmaps and table.concat(view.bitmaps.missing, ',') or ''
    end''')
    missing = run(ROOT, r, g.t, a.theme, a.target, a.live, a.full_artwork)
    g.fb.convert('RGB').save(a.out)
    print('wrote', a.out, g.fb.size, 'missing:', missing or '-')


if __name__ == '__main__':
    main()
