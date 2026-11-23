local M = {}; M.__index=M
function M.new(host) return setmetatable({r=host,epoch=0},M) end
function M:context()
  local r=self.r;local p=r.EnumProjects(-1,'')
  local t=r.GetSelectedTrack2(p,0,false)
  if t and not r.ValidatePtr2(p,t,'MediaTrack*') then t=nil end
  local guid=t and r.GetTrackGUID(t) or nil
  if p~=self.project or t~=self.track or guid~=self.guid then
    self.project,self.track,self.guid=p,t,guid;self.epoch=self.epoch+1
  end
  return p,t,guid
end
-- The mixer shows "Kontakt 8", not "VST3i: Kontakt 8 (Native Instruments)". A user-renamed
-- FX has no type prefix and is left exactly as typed.
function M.fx_label(name)
  local short,n=tostring(name):gsub('^%u%w*: ','')
  if n>0 then
    while true do
      local cut,c=short:gsub('%s*%b()%s*$','')
      if c==0 or cut=='' then break end
      short=cut
    end
  end
  return short
end
-- A send's destination track. REAPER hands scripts a track pointer here; if a build returns a bare
-- number instead, SWS's accessor is used when present.
function M:send_dest(t,i)
  local r=self.r
  local dest=r.GetTrackSendInfo_Value(t,0,i,'P_DESTTRACK')
  if type(dest)=='number' and r.BR_GetMediaTrackSendInfo_Track then dest=r.BR_GetMediaTrackSendInfo_Track(t,0,i,1) end
  return dest
end
function M:is_track(project,track)
  if track==nil or type(track)=='number' then return false end
  local ok,valid=pcall(self.r.ValidatePtr2,project,track,'MediaTrack*')
  return ok and valid==true
end
function M:snapshot()
  local p,t,guid=self:context();if not t then return nil end
  return self:read(p,t,guid)
end
-- Snapshot of the track an inspected track feeds (master, parent folder or a send destination).
-- It is only valid while its owner is still the inspected track and the destination still exists.
function M:output_snapshot(owner,track)
  local r=self.r
  if not owner or track==owner.track or not self:is_track(owner.project,track) then return nil end
  local s=self:read(owner.project,track,r.GetTrackGUID(track))
  s.owner=owner;return s
end
function M:read(p,t,guid)
  local r=self.r;local _,name=r.GetTrackName(t)
  local s={project=p,track=t,guid=guid,epoch=self.epoch,name=name,color=r.GetTrackColor(t),fx={},sends={},peaks={}}
  s.master=r.GetMasterTrack~=nil and r.GetMasterTrack(p)==t
  s.parent=not s.master and r.GetParentTrack and r.GetParentTrack(t) or nil
  for _,k in ipairs({'D_VOL','D_PAN','D_WIDTH','D_DUALPANL','D_DUALPANR','B_MUTE','I_SOLO','B_PHASE','I_RECARM','I_RECMON','IP_TRACKNUMBER','I_RECINPUT',
    'I_PANMODE','I_AUTOMODE','I_FXEN','I_RECMODE','B_MAINSEND','I_MIDIHWOUT'}) do
    s[k]=r.GetMediaTrackInfo_Value(t,k)
  end
  for i=0,r.TrackFX_GetCount(t)-1 do
    local _,n=r.TrackFX_GetFXName(t,i,'')
    s.fx[#s.fx+1]={index=i,guid=r.TrackFX_GetFXGUID(t,i),name=n,label=M.fx_label(n),
      enabled=r.TrackFX_GetEnabled(t,i),offline=r.TrackFX_GetOffline(t,i)}
  end
  -- Rack order follows the mixer: hardware outputs, the MIDI hardware output, then track sends.
  local hw=r.GetTrackNumSends(t,1)
  for i=0,hw-1 do
    local _,n=r.GetTrackSendName(t,i,'')
    s.sends[#s.sends+1]={kind='hw',index=i,name=n,volume=r.GetTrackSendInfo_Value(t,1,i,'D_VOL'),
      mute=r.GetTrackSendInfo_Value(t,1,i,'B_MUTE')~=0}
  end
  if not s.master and s.I_MIDIHWOUT>=0 and r.GetMIDIOutputName then
    local ok,n=r.GetMIDIOutputName((math.floor(s.I_MIDIHWOUT)>>5)&31,'')
    s.sends[#s.sends+1]={kind='midi',name=ok and n~='' and n or 'MIDI output'}
  end
  for i=0,r.GetTrackNumSends(t,0)-1 do
    local _,n=r.GetTrackSendName(t,hw+i,'')
    s.sends[#s.sends+1]={kind='send',index=i,name=n,dest=self:send_dest(t,i),
      volume=r.GetTrackSendInfo_Value(t,0,i,'D_VOL'),mute=r.GetTrackSendInfo_Value(t,0,i,'B_MUTE')~=0}
  end
  s.freeze=math.floor(r.GetMediaTrackInfo_Value(t,'I_FREEZECOUNT') or 0) -- how many freezes the track holds (0: not frozen)
  s.receives=r.GetTrackNumSends(t,-1)
  s.anysolo=r.AnyTrackSolo~=nil and r.AnyTrackSolo(p) and true or false -- some track is soloed: a track that is not is silenced by it (REAPER marks the meter)
  s.recfx=r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(t) or 0
  s.peaks={r.Track_GetPeakInfo(t,0),r.Track_GetPeakInfo(t,1)}
  if s.master then -- the master meter's loudness readout and the master mono switch
    s.loudness=r.Track_GetPeakInfo(t,1024);s.vumode=r.GetMediaTrackInfo_Value(t,'I_VUMODE')
    s.mono=r.GetToggleCommandStateEx~=nil and r.GetToggleCommandStateEx(0,40917)==1
  end
  return s
end
local MAX_GAIN=10^(12/20)
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.volume_mapping(r)
  if type(r.DB2SLIDER)=='function' and type(r.SLIDER2DB)=='function' then
    local lo,hi=r.DB2SLIDER(-150),r.DB2SLIDER(12)
    if hi>lo then
      return {
        native=true,
        to_gain=function(p) p=clamp(p,0,1);return p==0 and 0 or 10^(r.SLIDER2DB(lo+p*(hi-lo))/20) end,
        to_position=function(g) return g<=0 and 0 or clamp((r.DB2SLIDER(20*math.log(g,10))-lo)/(hi-lo),0,1) end
      }
    end
  end
  return {native=false,to_gain=function(p) return MAX_GAIN*clamp(p,0,1)^3 end,
    to_position=function(g) return clamp(g/MAX_GAIN,0,1)^(1/3) end}
end
function M:valid(token)
  if not token then return false end
  if token.owner then
    local r=self.r
    return self:valid(token.owner) and self:is_track(token.project,token.track) and r.GetTrackGUID(token.track)==token.guid
  end
  local p,t,g=self:context()
  return t~=nil and p==token.project and t==token.track and g==token.guid and self.epoch==token.epoch
end
-- Every write runs inside one complete project-scoped undo block, closed even if the setter throws.
function M:edit(token,label,fn)
  local r=self.r
  r.Undo_BeginBlock2(token.project)
  local ok,result=pcall(fn)
  r.Undo_EndBlock2(token.project,'Inspector: '..label,-1)
  if not ok then return false,result end
  if result~=false then r.TrackList_AdjustWindows(false);r.UpdateArrange() end
  return result~=false
end
local bounds={D_VOL={0,MAX_GAIN},D_PAN={-1,1},B_MUTE={0,1},I_SOLO={0,1},B_PHASE={0,1},I_RECARM={0,1},I_RECMON={0,2},
  I_FXEN={0,1},B_MAINSEND={0,1},I_AUTOMODE={0,5},I_RECMODE={0,16},I_RECINPUT={-1,8191}}
local pan={D_PAN=true,D_WIDTH=true,D_DUALPANL=true,D_DUALPANR=true}
for k in pairs(pan) do bounds[k]={-1,1} end
function M:set(token,key,value)
  if not bounds[key] or type(value)~='number' or value~=value or math.abs(value)==math.huge or not self:valid(token) then return false end
  if pan[key] then
    local mode=self.r.GetMediaTrackInfo_Value(token.track,'I_PANMODE')
    if mode~=token.I_PANMODE or (key=='D_PAN' and mode==6) or (key=='D_WIDTH' and mode~=5)
      or ((key=='D_DUALPANL' or key=='D_DUALPANR') and mode~=6) then return false end
  end
  value=clamp(value,bounds[key][1],bounds[key][2])
  if key~='D_VOL' and not pan[key] then value=math.floor(value) end
  local r=self.r
  if r.GetMediaTrackInfo_Value(token.track,key)==value then return true end
  return self:edit(token,key,function() return r.SetMediaTrackInfo_Value(token.track,key,value) end)
end
local toggles={B_MUTE=true,I_SOLO=true,B_PHASE=true,I_RECARM=true,I_RECMON=true,I_FXEN=true,B_MAINSEND=true}
function M:toggle(token,key)
  if not self:valid(token) or not toggles[key] then return false end
  local v=self.r.GetMediaTrackInfo_Value(token.track,key)
  return self:set(token,key,key=='I_RECMON' and (v+1)%3 or (v==0 and 1 or 0))
end
-- "Master track: Toggle stereo/mono (L+R)", the action behind the mixer's master mono button.
function M:master_mono(token)
  local r=self.r
  if not self:valid(token) or not token.master or not r.Main_OnCommandEx then return false end
  r.Main_OnCommandEx(40917,0,token.project);return true
end
-- Same guard as every other write, under the name the freeze code reads best with.
function M:verify(token) return self:valid(token) end
-- FeedTheCat's Smart-freeze scripts are found through REAPER's own action list (reaper-kb.ini is only read, never
-- written): a SCR line names the script's path, and "_" + its RS id resolves to the session's command id.
local FTC={tracks='smart-freeze selected tracks.lua',settings='smart-freeze settings.lua'}
function M:ftc_command(which)
  local r=self.r;local tail=FTC[which]
  if not tail or not r.GetResourcePath or not r.NamedCommandLookup then return nil end
  local f=io.open(r.GetResourcePath()..'/reaper-kb.ini','rb');if not f then return nil end
  local id
  for line in f:lines() do
    local rs,path=line:match('^SCR%s+%d+%s+%d+%s+(RS%x+)%s+"[^"]*"%s+"([^"]*)"')
    if not rs then rs,path=line:match('^SCR%s+%d+%s+%d+%s+(RS%x+)%s+"[^"]*"%s+(%S+)') end
    if rs and path then
      path=path:lower():gsub('\\','/')
      if path:sub(-#tail)==tail and (#path==#tail or path:sub(-#tail-1,-#tail-1)=='/') then id=rs;break end
    end
  end
  f:close()
  if not id then return nil end
  local cmd=r.NamedCommandLookup('_'..id)
  return cmd and cmd~=0 and cmd or nil
end
-- REAPER's freeze actions work on the selected tracks (the inspected track is the first one); selection is never changed.
local FREEZE={unfreeze=41644,stereo=41223,mono=40901,multi=40877}
function M:freeze_track(token,mode)
  local r=self.r
  if not token or token.master or token.owner or not r.Main_OnCommandEx or not self:verify(token) then return false end
  local cmd,note=FREEZE[mode],nil
  if mode=='smart' then
    cmd=self:ftc_command('tracks')
    if not cmd then cmd,note=FREEZE.stereo,'fallback' end
  end
  if not cmd then return false end
  r.Main_OnCommandEx(cmd,0,token.project)
  return true,note
end
function M:smart_freeze_settings()
  local r=self.r;local cmd=r.Main_OnCommandEx and self:ftc_command('settings')
  if not cmd then return false end
  r.Main_OnCommandEx(cmd,0,0);return true
end
-- FX slots are addressed by index, so the GUID is rechecked before every use.
function M:fx_ok(token,fx)
  return self:valid(token) and fx~=nil and self.r.TrackFX_GetFXGUID(token.track,fx.index)==fx.guid
end
-- The input (record) FX chain lives at index 0x1000000 of the same track.
function M:open_input_fx(token)
  if not self:valid(token) then return false end
  self.r.TrackFX_Show(token.track,0x1000000,1);return true
end
function M:open_fx(token,fx)
  if not self:fx_ok(token,fx) then return false end
  local r=self.r
  local floating=r.TrackFX_GetFloatingWindow and r.TrackFX_GetFloatingWindow(token.track,fx.index)
  r.TrackFX_Show(token.track,fx.index,floating and 2 or 3);return true
end
function M:fx_chain(token,fx)
  if not self:valid(token) or (fx and not self:fx_ok(token,fx)) then return false end
  self.r.TrackFX_Show(token.track,fx and fx.index or 0,1);return true
end
function M:fx_edit(token,fx,what)
  if not self:fx_ok(token,fx) then return false end
  local r,t,i=self.r,token.track,fx.index
  if what=='bypass' then return self:edit(token,'FX bypass',function() r.TrackFX_SetEnabled(t,i,not r.TrackFX_GetEnabled(t,i)) end) end
  if what=='offline' then return self:edit(token,'FX offline',function() r.TrackFX_SetOffline(t,i,not r.TrackFX_GetOffline(t,i)) end) end
  if what=='delete' then return self:edit(token,'remove FX',function() return r.TrackFX_Delete(t,i) end) end
  return false
end
function M:fx_parallel(token,fx,mode)
  if not self:fx_ok(token,fx) or not self.r.TrackFX_SetNamedConfigParm then return false end
  return self:edit(token,'FX parallel',function() return self.r.TrackFX_SetNamedConfigParm(token.track,fx.index,'parallel',tostring(mode)) end)
end
-- The name as stored (empty for an unnamed track, which REAPER displays as "Track N").
function M:track_name(token)
  local r=self.r
  if not self:valid(token) or token.master or not r.GetSetMediaTrackInfo_String then return nil end
  local ok,name=r.GetSetMediaTrackInfo_String(token.track,'P_NAME','',false)
  return ok and name or ''
end
function M:rename(token,name)
  if type(name)~='string' or self:track_name(token)==nil then return false end
  return self:edit(token,'rename track',function() return self.r.GetSetMediaTrackInfo_String(token.track,'P_NAME',name,true) end)
end
function M:fx_rename(token,fx,name)
  if not self:fx_ok(token,fx) or type(name)~='string' or not self.r.TrackFX_SetNamedConfigParm then return false end
  return self:edit(token,'rename FX',function() return self.r.TrackFX_SetNamedConfigParm(token.track,fx.index,'renamed_name',name) end)
end
function M:add_container(token)
  if not self:valid(token) then return false end
  return self:edit(token,'add container',function() return self.r.TrackFX_AddByName(token.track,'Container',false,-1)>=0 end)
end
-- The Inspector's own FX clipboard (REAPER's is not reachable from scripts). It remembers the
-- source by track pointer and FX GUID and looks the slot up again when pasting.
function M:fx_copy(token,fx,cut)
  if not self:fx_ok(token,fx) then return false end
  self.clip={project=token.project,track=token.track,guid=fx.guid,cut=cut==true};return true
end
function M:fx_paste(token,position)
  local c,r=self.clip,self.r
  if not c or not self:valid(token) or c.project~=token.project or not r.ValidatePtr2(c.project,c.track,'MediaTrack*') then return false end
  local src
  for i=0,r.TrackFX_GetCount(c.track)-1 do if r.TrackFX_GetFXGUID(c.track,i)==c.guid then src=i;break end end
  if not src then self.clip=nil;return false end
  local dest=math.max(0,math.min(r.TrackFX_GetCount(token.track),math.floor(position or 1e9)))
  local ok=self:edit(token,c.cut and 'move FX' or 'paste FX',function() r.TrackFX_CopyToTrack(c.track,src,token.track,dest,c.cut) end)
  if ok and c.cut then self.clip=nil end
  return ok
end
-- "Slot for selected/all tracks" entries: apply this slot's new state to the same slot elsewhere.
function M:scope(token,all)
  local r,out=self.r,{}
  if all then for i=0,r.CountTracks(token.project)-1 do out[#out+1]=r.GetTrack(token.project,i) end
  else for i=0,r.CountSelectedTracks(token.project)-1 do out[#out+1]=r.GetSelectedTrack(token.project,i) end end
  return out
end
function M:fx_slot_bypass(token,fx,all)
  if not self:fx_ok(token,fx) then return false end
  local r=self.r;local on=not r.TrackFX_GetEnabled(token.track,fx.index)
  return self:edit(token,'bypass FX slot',function()
    for _,t in ipairs(self:scope(token,all)) do if r.TrackFX_GetCount(t)>fx.index then r.TrackFX_SetEnabled(t,fx.index,on) end end
  end)
end
function M:send_slot_mute(token,send,all)
  if not self:send_ok(token,send) then return false end
  local r=self.r;local mute=send.mute and 0 or 1
  return self:edit(token,'mute send slot',function()
    for _,t in ipairs(self:scope(token,all)) do if r.GetTrackNumSends(t,0)>send.index then r.SetTrackSendInfo_Value(t,0,send.index,'B_MUTE',mute) end end
  end)
end
-- Selects the destination track and scrolls to it; the Inspector then follows the selection.
function M:goto_send_dest(token,send)
  local r=self.r
  if not self:send_ok(token,send) or not self:is_track(token.project,send.dest) then return false end
  r.SetOnlyTrackSelected(send.dest)
  if r.SetMixerScroll then r.SetMixerScroll(send.dest) end
  if r.Main_OnCommandEx then r.Main_OnCommandEx(40913,0,token.project) end -- scroll selected track into view
  return true
end
-- Opens REAPER's "Add FX to track" browser without the FX chain, as a mixer slot click does.
-- The browser (40271, a toggle) targets the last-touched track, so it is only used when that is
-- this track; it is closed first if already open so it re-targets. Otherwise the chain is the
-- fallback: an empty chain brings up its own Add FX window, a populated one returns 'chain'.
function M:add_fx(token)
  if not self:valid(token) then return false end
  local r=self.r
  if r.Main_OnCommandEx and r.GetLastTouchedTrack and r.GetLastTouchedTrack()==token.track then
    if r.GetToggleCommandStateEx and r.GetToggleCommandStateEx(0,40271)==1 then r.Main_OnCommandEx(40271,0,token.project) end
    r.Main_OnCommandEx(40271,0,token.project);return true
  end
  local n=r.TrackFX_GetCount(token.track)
  r.TrackFX_Show(token.track,math.max(0,n-1),1)
  return true,n>0 and 'chain' or nil
end
-- REAPER only exposes its routing window for the last-touched track; refuse rather than open another track's.
function M:routing(token)
  if not self:valid(token) then return false end
  local r=self.r
  if not r.Main_OnCommandEx or not r.GetLastTouchedTrack or r.GetLastTouchedTrack()~=token.track then return false,'touch' end
  r.Main_OnCommandEx(40293,0,token.project);return true
end
function M:send_ok(token,send)
  return self:valid(token) and send~=nil and send.kind=='send'
    and self:send_dest(token.track,send.index)==send.dest
end
function M:send_edit(token,send,what)
  if not self:send_ok(token,send) then return false end
  local r,t,i=self.r,token.track,send.index
  if what=='mute' then
    return self:edit(token,'send mute',function() return r.SetTrackSendInfo_Value(t,0,i,'B_MUTE',send.mute and 0 or 1) end)
  end
  if what=='remove' then return self:edit(token,'remove send',function() return r.RemoveTrackSend(t,0,i) end) end
  return false
end
function M:send_targets(token,limit)
  local out={};if not self:valid(token) then return out end
  local r=self.r
  for i=0,math.min(r.CountTracks(token.project),limit or 80)-1 do
    local t=r.GetTrack(token.project,i)
    if t and t~=token.track then local _,n=r.GetTrackName(t);out[#out+1]={track=t,name=n,number=i+1} end
  end
  return out
end
function M:add_send(token,dest)
  if not self:valid(token) or dest==nil or dest==token.track or not self.r.ValidatePtr2(token.project,dest,'MediaTrack*') then return false end
  return self:edit(token,'add send',function() return self.r.CreateTrackSend(token.track,dest)>=0 end)
end
return M
