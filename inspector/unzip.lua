-- Minimal read-only zip reader (stored and deflate entries) so theme archives work without extensions.
-- Never writes to, or modifies, the archive.
local M = {}

local crc_table
local function crc32(s)
  if not crc_table then
    crc_table = {}
    for i = 0, 255 do
      local c = i
      for _ = 1, 8 do c = (c & 1) ~= 0 and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
      crc_table[i] = c
    end
  end
  local c = 0xFFFFFFFF
  for i = 1, #s do c = crc_table[(c ~ s:byte(i)) & 255] ~ (c >> 8) end
  return c ~ 0xFFFFFFFF
end
M.crc32 = crc32

local LBASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LEXT = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DBASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577}
local DEXT = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local ORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

local function huffman(lengths, n)
  local count, offs, symbol = {}, {}, {}
  for i = 0, 15 do count[i] = 0 end
  for i = 0, n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
  offs[1] = 0
  for i = 1, 14 do offs[i + 1] = offs[i] + count[i] end
  for i = 0, n - 1 do
    local l = lengths[i]
    if l ~= 0 then symbol[offs[l]] = i; offs[l] = offs[l] + 1 end
  end
  return {count = count, symbol = symbol}
end

local fixed_lit, fixed_dist

-- RFC 1951 inflate. `limit` bounds the output so a hostile archive cannot exhaust memory.
function M.inflate(data, limit)
  local pos, bitbuf, bitcnt = 1, 0, 0
  local out, n = {}, 0
  local function bits(k)
    while bitcnt < k do
      local b = data:byte(pos)
      if not b then error('compressed data is truncated', 0) end
      pos = pos + 1; bitbuf = bitbuf | (b << bitcnt); bitcnt = bitcnt + 8
    end
    local v = bitbuf & ((1 << k) - 1)
    bitbuf = bitbuf >> k; bitcnt = bitcnt - k
    return v
  end
  local function decode(h)
    local code, first, index = 0, 0, 0
    for len = 1, 15 do
      code = code | bits(1)
      local c = h.count[len]
      if code - c < first then return h.symbol[index + (code - first)] end
      index = index + c; first = (first + c) << 1; code = code << 1
    end
    error('invalid compressed data', 0)
  end
  local function codes(lit, dist)
    while true do
      local sym = decode(lit)
      if sym == nil then error('invalid compressed data', 0) end
      if sym < 256 then
        n = n + 1; out[n] = sym
      elseif sym == 256 then
        return
      else
        sym = sym - 256
        if sym > 29 then error('invalid compressed data', 0) end
        local len = LBASE[sym] + bits(LEXT[sym])
        local ds = decode(dist)
        if ds == nil or ds > 29 then error('invalid compressed data', 0) end
        local d = DBASE[ds + 1] + bits(DEXT[ds + 1])
        if d > n then error('invalid compressed data', 0) end
        for _ = 1, len do n = n + 1; out[n] = out[n - d] end
      end
      if n > limit then error('archive entry is larger than declared', 0) end
    end
  end
  local last
  repeat
    last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      bitbuf, bitcnt = 0, 0
      local len, nlen = data:byte(pos) + data:byte(pos + 1) * 256, data:byte(pos + 2) + data:byte(pos + 3) * 256
      if len ~ nlen ~= 0xFFFF then error('invalid compressed data', 0) end
      pos = pos + 4
      if pos + len - 1 > #data or n + len > limit then error('compressed data is truncated', 0) end
      for i = pos, pos + len - 1 do n = n + 1; out[n] = data:byte(i) end
      pos = pos + len
    elseif kind == 1 then
      if not fixed_lit then
        local l = {}
        for i = 0, 143 do l[i] = 8 end
        for i = 144, 255 do l[i] = 9 end
        for i = 256, 279 do l[i] = 7 end
        for i = 280, 287 do l[i] = 8 end
        fixed_lit = huffman(l, 288)
        local d = {}
        for i = 0, 29 do d[i] = 5 end
        fixed_dist = huffman(d, 30)
      end
      codes(fixed_lit, fixed_dist)
    elseif kind == 2 then
      local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
      local lengths = {}
      for i = 0, 18 do lengths[i] = 0 end
      for i = 1, ncode do lengths[ORDER[i]] = bits(3) end
      local lencode = huffman(lengths, 19)
      lengths = {}
      local i = 0
      while i < nlen + ndist do
        local sym = decode(lencode)
        if sym == nil then error('invalid compressed data', 0) end
        if sym < 16 then
          lengths[i] = sym; i = i + 1
        else
          local prev, rep = 0, 0
          if sym == 16 then
            if i == 0 then error('invalid compressed data', 0) end
            prev = lengths[i - 1]; rep = 3 + bits(2)
          elseif sym == 17 then rep = 3 + bits(3)
          else rep = 11 + bits(7) end
          if i + rep > nlen + ndist then error('invalid compressed data', 0) end
          for _ = 1, rep do lengths[i] = prev; i = i + 1 end
        end
      end
      local dl = {}
      for j = 0, ndist - 1 do dl[j] = lengths[nlen + j] end
      codes(huffman(lengths, nlen), huffman(dl, ndist))
    else
      error('invalid compressed data', 0)
    end
  until last == 1
  local parts = {}
  for i = 1, n, 4096 do parts[#parts + 1] = string.char(table.unpack(out, i, math.min(n, i + 4095))) end
  return table.concat(parts)
end

local MAX_ENTRY = 64 * 1024 * 1024

-- Returns {path=, entries={[lowercase name]={name,method,crc,csize,usize,offset}}, fingerprint=}.
function M.open(path)
  local f = io.open(path, 'rb'); if not f then return nil, 'Cannot read theme archive' end
  local size = f:seek('end')
  local tail_len = math.min(size, 65557)
  f:seek('set', size - tail_len)
  local tail = f:read(tail_len) or ''
  local at
  for i = #tail - 21, 1, -1 do
    if tail:sub(i, i + 3) == 'PK\5\6' then at = i; break end
  end
  if not at then f:close(); return nil, 'Not a zip archive' end
  local total, cd_size, cd_offset = string.unpack('<I2I4I4', tail, at + 10)
  if cd_offset == 0xFFFFFFFF or cd_offset + cd_size > size then f:close(); return nil, 'Unsupported zip archive' end
  f:seek('set', cd_offset)
  local cd = f:read(cd_size) or ''
  f:close()
  local entries, p = {}, 1
  for _ = 1, total do
    if cd:sub(p, p + 3) ~= 'PK\1\2' then return nil, 'Damaged zip archive' end
    local method, _, _, crc, csize, usize, nlen, elen, clen = string.unpack('<I2I2I2I4I4I4I2I2I2', cd, p + 10)
    local offset = string.unpack('<I4', cd, p + 42)
    local name = cd:sub(p + 46, p + 45 + nlen):gsub('\\', '/')
    entries[name:lower()] = {name = name, method = method, crc = crc, csize = csize, usize = usize, offset = offset}
    p = p + 46 + nlen + elen + clen
  end
  -- The central directory lists every file's checksum, so its own checksum identifies this exact archive.
  return {path = path, entries = entries, fingerprint = ('%08x'):format(crc32(cd))}
end

function M.read(zip, name)
  local e = zip.entries[name:lower()]
  if not e then return nil, 'Not in archive: ' .. name end
  if e.usize > MAX_ENTRY or e.csize > MAX_ENTRY then return nil, 'Archive entry too large' end
  local f = io.open(zip.path, 'rb'); if not f then return nil, 'Cannot read theme archive' end
  f:seek('set', e.offset)
  local head = f:read(30) or ''
  if #head < 30 or head:sub(1, 4) ~= 'PK\3\4' then f:close(); return nil, 'Damaged zip archive' end
  local nlen, elen = string.unpack('<I2I2', head, 27)
  f:seek('set', e.offset + 30 + nlen + elen)
  local raw = f:read(e.csize) or ''
  f:close()
  if #raw ~= e.csize then return nil, 'Damaged zip archive' end
  local data
  if e.method == 0 then data = raw
  elseif e.method == 8 then
    local ok, result = pcall(M.inflate, raw, e.usize)
    if not ok then return nil, tostring(result) end
    data = result
  else return nil, 'Unsupported zip compression' end
  if #data ~= e.usize or crc32(data) ~= e.crc then return nil, 'Archive entry failed its checksum' end
  return data
end

return M
