#!/usr/bin/env python3
"""Read-only installed PNG audit; stdlib only, no REAPER/GUI interaction."""
import struct
import zlib
from pathlib import Path

THEME = Path.home() / 'Library/Application Support/REAPER/ColorThemes/Reapertips Theme_Custom2'
# Every sprite the Inspector can draw.
NAMES = (
    'mcp_env mcp_env_latch mcp_env_preview mcp_env_read mcp_env_touch mcp_env_write mcp_fx_dis '
    'mcp_fx_empty mcp_fx_norm mcp_fxlist_byp mcp_fxlist_empty mcp_fxlist_norm mcp_fxlist_off '
    'mcp_idxbg_sel mcp_io mcp_io_dis mcp_io_r mcp_io_r_dis mcp_io_s mcp_io_s_dis mcp_io_s_r '
    'mcp_io_s_r_dis mcp_monitor_auto mcp_monitor_off mcp_monitor_on mcp_mute_off mcp_mute_on '
    'mcp_pan_knob_large mcp_phase_inv mcp_phase_norm mcp_recarm_off mcp_recarm_on mcp_recinput '
    'mcp_recmode_in mcp_recmode_off mcp_recmode_out mcp_send_knob_stack mcp_sendlist_empty '
    'mcp_sendlist_midihw mcp_sendlist_mute mcp_sendlist_norm mcp_solo_off mcp_solo_on mcp_volbg '
    'mcp_volthumb track_fxempty_v track_fxoff_v track_fxon_v ').split()

def png(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos, compressed = 8, bytearray()
    while pos < len(data):
        size = struct.unpack_from('>I', data, pos)[0]
        kind, body = data[pos+4:pos+8], data[pos+8:pos+8+size]
        assert zlib.crc32(kind+body) & 0xffffffff == struct.unpack_from('>I', data, pos+8+size)[0]
        if kind == b'IHDR':
            w, h, depth, color, comp, filt, interlace = struct.unpack('>IIBBBBB', body)
            assert color in (0, 2, 3, 4, 6) and interlace == 0 and (depth in (1, 2, 4, 8) if color in (0, 3) else depth == 8), (path, depth, color, interlace)
            channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
        elif kind == b'PLTE':
            palette = [tuple(body[i:i+3]) for i in range(0, len(body), 3)]
        elif kind == b'tRNS':
            alpha = body
        elif kind == b'IDAT':
            compressed.extend(body)
        pos += size+12
    raw = zlib.decompress(compressed)
    stride, rows, at = (w*depth+7)//8 if color in (0, 3) else w*channels, [], 0
    for _ in range(h):
        method = raw[at]
        at += 1
        row = bytearray(raw[at:at+stride])
        at += stride
        prior = rows[-1] if rows else bytearray(stride)
        for i in range(stride):
            a = row[i-channels] if i >= channels else 0
            b = prior[i]
            c = prior[i-channels] if i >= channels else 0
            if method == 1: value = a
            elif method == 2: value = b
            elif method == 3: value = (a+b)//2
            elif method == 4:
                p = a+b-c
                distances = [abs(p-a), abs(p-b), abs(p-c)]
                value = [a, b, c][distances.index(min(distances))]
            else:
                assert method == 0
                value = 0
            row[i] = (row[i]+value) & 255
        rows.append(row)
    assert at == len(raw)
    def pixel(x, y):
        i = x*channels
        if color in (0, 3):
            index = (rows[y][x*depth//8] >> (8-depth-(x*depth % 8))) & ((1 << depth)-1)
            return palette[index] if color == 3 else (index*255//((1 << depth)-1),)*3
        if color == 4:
            return (rows[y][i],)*3
        return tuple(rows[y][i:i+3])
    return w, h, pixel

if __name__ == '__main__':
    checked = 0
    for variant in ('', '150', '200'):
        for name in NAMES:
            path = THEME / variant / (name+'.png')
            w, h, p = png(path)
            marker = lambda rgb: rgb in ((255, 0, 255), (255, 255, 0))
            border = any(marker(p(x,y)) for x in range(w) for y in (0,h-1)) or any(marker(p(x,y)) for y in range(h) for x in (0,w-1))
            cut = int(border)
            interior = [(x,y) for y in range(cut,h-cut) for x in range(cut,w-cut) if marker(p(x,y))]
            assert not interior, (path, 'guide pixels inside crop', interior[:5])
            print(f'{variant or "100":>3} {name:24} {w:3}x{h:<3} crop={cut} core={w-2*cut}x{h-2*cut} sample={p(w//2,3*h//4)}')
            checked += 1
    print(f'PASS: {checked} installed PNGs decoded; zero pink/yellow guide pixels inside cropped art')
