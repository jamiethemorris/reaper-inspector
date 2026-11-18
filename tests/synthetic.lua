-- Explicit synthetic REAPER boundary. No live API is loaded by these tests.
local M = {}
function M.host()
  local p, a, b = {}, {guid='{A}',name='Synth',valid=true}, {guid='{B}',name='Other',valid=true}
  for _,t in ipairs({a,b}) do t.values={D_VOL=1,D_PAN=0,B_MUTE=0,I_SOLO=0,B_PHASE=0,I_RECARM=0,I_RECMON=0,IP_TRACKNUMBER=1,I_RECINPUT=-1,I_MIDIHWOUT=-1,B_MAINSEND=1,I_FXEN=1} end
  local h={project=p,selected=a,a=a,b=b,writes={},undos={},ext={},clock=100,frames={},fx={{guid='{FX1}',name='VSTi: Synth',enabled=true}}}
  h.EnumProjects=function(i) if i == -1 or i == 0 then return h.project,'' end end
  h.GetSelectedTrack2=function(proj) assert(proj == h.project);return h.selected end
  h.ValidatePtr2=function(proj,t) return proj == h.project and t and t.valid end
  h.GetTrackGUID=function(t) assert(t.valid);return t.guid end
  h.GetTrackName=function(t) return true,t.name end
  h.GetResourcePath=function() return os.getenv('HOME')..'/Library/Application Support/REAPER' end
  h.GetLastColorThemeFile=function() return h.theme_file end
  h.theme_file=h.GetResourcePath()..'/ColorThemes/Reapertips Theme_Custom2.ReaperTheme'
  h.cache=(os.getenv('TMPDIR') or '/tmp'):gsub('/+$','')..'/reaper-inspector-tests'
  h.RecursiveCreateDirectory=function(p) h.made=p;os.execute('mkdir -p "'..p..'"');return 1 end
  h.GetSetMediaTrackInfo_String=function(t,k,v,set)
    if k~='P_NAME' then return false,'' end
    if set then h.writes[#h.writes+1]={'name',t,v};t.name=v end
    return true,t.name
  end
  h.GetTrackColor=function() return 0 end
  h.ColorFromNative=function() return 204,179,49 end
  h.GetMediaTrackInfo_Value=function(t,k) assert(t.valid);return t.values[k] or 0 end
  h.send={dest=b,mute=0,present=true}
  h.GetTrackNumSends=function(_,cat) return cat == 0 and h.send.present and 1 or 0 end
  h.GetTrackSendName=function() return true,'Reverb' end
  h.GetTrackSendInfo_Value=function(_,_,_,k)
    if k=='P_DESTTRACK' then return h.send.dest elseif k=='B_MUTE' then return h.send.mute end
    return 0.5
  end
  h.SetTrackSendInfo_Value=function(t,_,_,k,v) h.writes[#h.writes+1]={'send',t,k,v};if k=='B_MUTE' then h.send.mute=v end;return true end
  h.RemoveTrackSend=function(t) h.writes[#h.writes+1]={'send',t,'remove'};h.send.present=false;return true end
  h.CreateTrackSend=function(t,d) h.writes[#h.writes+1]={'send',t,'create',d};return 0 end
  h.CountTracks=function() return 2 end
  h.master={guid='{MASTER}',name='MASTER',valid=true,values={D_VOL=1,D_PAN=0,B_MUTE=0,I_FXEN=1,I_MIDIHWOUT=-1,B_MAINSEND=1,IP_TRACKNUMBER=-1}}
  h.GetMasterTrack=function() return h.master end
  h.GetParentTrack=function(t) return t.parent end
  h.CountSelectedTracks=function() return h.selected and 1 or 0 end
  h.GetSelectedTrack=function() return h.selected end
  h.TrackFX_GetNamedConfigParm=function(_,i,k) return true,tostring(h.fx[i+1][k] or 0) end
  h.TrackFX_SetNamedConfigParm=function(t,i,k,v) h.writes[#h.writes+1]={'fxset',t,i,k,v};h.fx[i+1][k]=v;return true end
  h.TrackFX_AddByName=function(t,name) h.writes[#h.writes+1]={'fxset',t,name,'add'};h.fx[#h.fx+1]={guid='{NEW'..#h.fx..'}',name=name,enabled=true};return #h.fx-1 end
  h.TrackFX_CopyToTrack=function(st,si,dt,di,move) h.writes[#h.writes+1]={'fxcopy',st,si,dt,di,move} end
  h.SetOnlyTrackSelected=function(t) h.selected=t end
  h.GetTrack=function(_,i) return i==0 and a or b end
  h.GetLastTouchedTrack=function() return h.touched end
  h.GetToggleCommandStateEx=function() return 0 end
  h.Main_OnCommandEx=function(id) h.commands=h.commands or {};h.commands[#h.commands+1]=id end
  h.Track_GetPeakInfo=function(_,c) return c == 0 and 0.5 or 0.25 end
  h.TrackFX_GetCount=function() return #h.fx end
  h.TrackFX_GetFXName=function(_,i) return true,h.fx[i+1].name end
  h.TrackFX_GetFXGUID=function(_,i) return h.fx[i+1] and h.fx[i+1].guid end
  h.TrackFX_GetEnabled=function(_,i) return h.fx[i+1].enabled end
  h.TrackFX_GetOffline=function(_,i) return h.fx[i+1].offline==true end
  h.TrackFX_Show=function(t,i,mode) h.writes[#h.writes+1]={'fx',t,i,mode} end
  h.TrackFX_GetFloatingWindow=function() return h.floating end
  h.TrackFX_SetEnabled=function(t,i,on) h.writes[#h.writes+1]={'fxset',t,i,'enabled',on};h.fx[i+1].enabled=on end
  h.TrackFX_SetOffline=function(t,i,on) h.writes[#h.writes+1]={'fxset',t,i,'offline',on};h.fx[i+1].offline=on end
  h.TrackFX_Delete=function(t,i) h.writes[#h.writes+1]={'fxset',t,i,'delete'};table.remove(h.fx,i+1);return true end
  h.SetMediaTrackInfo_Value=function(t,k,v) h.writes[#h.writes+1]={t,k,v}; t.values[k]=v;return true end
  h.Undo_BeginBlock2=function() h.open=(h.open or 0)+1 end
  h.Undo_EndBlock2=function(_,s) h.open=h.open-1;h.undos[#h.undos+1]=s end
  h.TrackList_AdjustWindows=function() h.refresh=(h.refresh or 0)+1 end
  h.UpdateArrange=function() h.arrange=(h.arrange or 0)+1 end
  h.GetExtState=function(s,k) return h.ext[s..'/'..k] or '' end
  h.SetExtState=function(s,k,v) h.ext[s..'/'..k]=v end
  h.DeleteExtState=function(s,k) h.ext[s..'/'..k]=nil end
  h.time_precise=function() return h.clock end
  h.defer=function(f) h.frames[#h.frames+1]=f end
  h.atexit=function(f) h.exit=f end
  h.GetOS=function() return 'OSX64' end
  return h
end
function M.gfx()
  local g={w=340,h=1400,ext_retina=2,dest=-1,mouse_x=0,mouse_y=0,mouse_cap=0,mouse_wheel=0,images={},blits={},calls={},key=0,dockstate=0}
  for _,n in ipairs({'set','rect','line','circle','roundrect','drawstr','setfont','update','quit','setimgdim','muladdrect'}) do
    g[n]=function(...) g.calls[#g.calls+1]={n,...} end
  end
  g.loadimg=function(i,p) g.images[i]=p;return i end
  g.getpixel=function() return .2,.2,.2 end
  g.blit=function(...) g.blits[#g.blits+1]={...} end
  g.getchar=function() return g.key end
  g.measurestr=function(s) return #s*10,20 end
  g.init=function(_,w,h,d) g.w=w*2;g.h=h*2;g.dockstate=d or 0;g.initialized=true end
  g.dock=function(d) if d>=0 then g.dockstate=d end;return g.dockstate,100,100,g.w/2,g.h/2 end
  g.showmenu=function(str) g.menus=g.menus or {};g.menus[#g.menus+1]=str;return g.menu or 0 end
  return g
end
return M
