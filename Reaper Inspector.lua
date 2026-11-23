-- @description Reaper Inspector: dockable selected-track strip matching the Reapertips mixer
-- @author jamiethemorris
-- @version 0.8.0
-- @provides
--   inspector/app.lua
--   inspector/bitmaps.lua
--   inspector/model.lua
--   inspector/theme.lua
--   inspector/unzip.lua
--   inspector/view.lua
-- @link https://github.com/jamiethemorris/reaper-inspector
-- Keep the inspector/ directory beside this entrypoint. No extensions required.
local source=debug.getinfo(1,'S').source
assert(source:sub(1,1)=='@','Load the Inspector from its saved Lua file')
local directory=source:sub(2):match('^(.*[/\\])') or './'
local App=dofile(directory..'inspector/app.lua')
App.new(reaper,gfx):run()
