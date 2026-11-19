# Reaper Inspector

A dockable, single-selected-track Lua `gfx` inspector, independent of REAPER's mixer. Runtime dependencies: REAPER's built-in Lua/ReaScript and `gfx` only. No ReaImGui, SWS, JS extension, package installation, action registration by the script, or theme installation.

**Verification status (0.6.0):** the three hand-made layouts (Reapertips v1.90, Reapertips v1.95, REAPER Default 7) were each checked offline against a screenshot of the native mixer strip in that theme. That comparison uses a stand-in renderer (`tests/preview.py`), so it proves geometry and artwork handling, not REAPER's own text rendering, menus or control behaviour. 0.2.0 has been run in REAPER 7.86 on macOS; 0.4.0 has been seen running in REAPER with Default 7 and Flat Madness (two strips, archive artwork, plain strip); the Default 7 layout, live Theme Adjuster reading, rename and several click behaviours added since 0.2.0 have **not yet been confirmed in REAPER**. All 35 offline synthetic-host tests pass.

## Install

**ReaPack:** Extensions → ReaPack → Import repositories…, paste

```
https://github.com/jamiethemorris/reaper-inspector/raw/main/index.xml
```

then install **Reaper Inspector** from Browse packages. It appears in the Actions list as `Script: Reaper Inspector.lua`.

**Manually:** download the repository and follow the next section.

No theme artwork is included. The Inspector reads the artwork of the theme REAPER is using, from wherever it is installed.

## Load it yourself

Keep `Reaper Inspector.lua` beside the `inspector/` folder. In REAPER's Actions list choose **ReaScript → Load**, select `Reaper Inspector.lua`, then run it. To pick up a new version, close the Inspector (Escape or the window's close button) and run the action again; REAPER itself does not need a restart. The directory may live anywhere; modules are loaded relative to their own source files.

The first window is 170 logical points wide by 700 high. The native strip is 86 points wide; at that width or more the layout never overlaps. Extra width goes to the meter first, then to space between fader and buttons. Below 86 points the meter is removed so the fader and buttons still fit (down to roughly 64). Extra height goes to the FX and send racks; the lower strip stays between 300 and 380 points tall and, like the theme, drops the input row on short strips. Escape, window close, the menu's Close entry or running the action again stops the inspector.

Right-click on empty panel space for the Inspector's own menu: **Dock inspector**, **Show output strip**, **Load theme...**, **Follow REAPER's theme**, **Try full theme artwork (experimental)**, **Close inspector**. The artwork checkbox lets unrecognized themes try more of their own images without changing the Inspector's control positions. Missing artwork can still fall back to drawn controls, and available images may not fit perfectly. The checkbox starts off each time the Inspector opens.

## Renaming

Double-click a track name to rename that track (either strip; the master cannot be renamed). REAPER gives scripts no in-place text field, so this opens a small "Rename track" box rather than editing the name on the strip. Clearing the name returns the track to REAPER's default "Track N". One undo step per rename.

## Output strip

When the panel is at least 172 points wide (two native strips), a second strip appears to the right of the inspected track and shows where that track goes:

- By default the **master**, or the track's **parent folder** when it is inside one.
- Click a **track send** and the strip switches to that send's destination track. Click the pinned **Master send / Parent send** row (the last row of the send rack, under its own divider) to switch back. A small bar at the left of a row marks which one the strip is showing. The last choice is remembered per track until the Inspector is closed.
- The output strip is a full strip: fader, pan, mute, FX rack and menus, sends, automation all act on that other track. It lets go as soon as the inspected track changes or the output track disappears.
- The master's strip has no record arm, monitoring, input, record mode, solo or polarity button, and no output row of its own. Its rack shows inserts only (its hardware outputs are reached through the routing button). When its meter is wide enough it shows a peak readout per channel and the master's loudness readout at the bottom. It is drawn with the ordinary strip art, not the theme's separate master art (80gray is the exception; see below).
- Right-click the output row to turn the master/parent send itself on or off (a muted-looking row means it is off).
- MIDI and hardware output rows are not tracks, so clicking them opens the routing window instead.

Turn the strip off or on with **Show output strip** in the Inspector menu (right-click the fader area, the track name or other empty panel space) or in the output row's right-click menu. The setting is remembered. In a panel narrower than 172 points only the inspected track is shown and clicking a send opens the routing window.

## Theme and appearance

By default the Inspector **follows the theme REAPER is using** and notices within about a second when you switch theme. **Load theme...** pins a particular theme instead (a `.ReaperTheme` file, a `.ReaperThemeZip` archive, or an unpacked asset folder containing `rtconfig.txt`); **Follow REAPER's theme** goes back to following. A theme that cannot be read keeps the current one and displays an error. Quotes, spaces and apostrophes are treated as path data, never executable text.

How closely it matches depends on the theme:

| Theme | What you get |
|---|---|
| Reapertips v1.95 (the current stock theme and its colour variants: Green, Purple, Hybrid, Light, Dark with Light Menus) | A hand-made layout: the theme's own artwork, placed where the native mixer puts it, with each variant's own panel colours. Assumes the theme's default Theme Adjuster values (wide strip, labels on, no sidebar). |
| REAPER Default 6, compatible derivatives (e.g. Neptune VI), and Reapertips v1.90 | A shared 6-style layout with each theme’s own artwork. Compatible Default 6 scripts use the smaller pan knob, show In FX on tall strips, and can vary the record-arm offset and name-bar height. When the mixer background's fixed top region covers the pan/input panel, it supplies the normal and selected shading without changing the track-number footer. Reapertips v1.90 and personal copies keep their previous appearance. Themes that change the mixer structure still use the plain strip. |
| REAPER Default 7 and compatible derivatives | The Inspector detects the Default 7 normal-width mixer structure in the theme script, regardless of the filename, and uses that theme's own images. Derivatives may still place or style controls differently from the native mixer. Supported Theme Adjuster values include verbose labels, track-colour strength, selection strength, inverted selected labels, selection dot, text brightness, background colour, and show/hide switches for route, FX, envelope and phase. Layout A's values are used for every track. |
| 80gray v2.2 (all editions: Classic, D3, Everforest Light, MP Classic/Machine/Octagon/Pro/Ristretto/Spectrum) | A hand-made layout of the theme's standard strip: FX, FX bypass, envelope and polarity on top, a pan slider (two small knobs in stereo and dual pan), a thin fader beside the meter, mute/solo/routing at the upper right, input FX/monitor/record arm at the lower right, then the name, selection bar, number and routing-diagram row. Controls keep the theme's sizes and move with the panel width, as the theme's own *MCP: Width* setting does. Each edition's colours are read from its script. Like the native strip it has no input selector or record-mode button. The master strip follows the theme's master layout: name in the bottom row, a mono/stereo switch in place of polarity, a solo button, and the mixer's Menu artwork (not clickable here). Not reproduced: the narrow form (60 pt and below), the fader turning into a knob on very short strips, folder nesting in the routing-diagram row, and the *MCP: Tint* and record-arm indicator options. |
| theFRXST 3.three | A hand-made layout: name bar on top with the track's colour dot, the FX and send lists inside the strip, and the theme's rounded control panel anchored to the bottom (FX, bypass and routing; input, input FX and the IN/AUTO/OFF monitor row; volume readout, bar-shaped pan and width, envelope and polarity, the mute button carrying the track number, solo, record arm; fader and meter). The theme's strip is a fixed 124 pt: in a narrower or wider panel the left column and fader keep their place and the meter takes the difference, losing its text below 24 pt and disappearing below 10 pt. The master follows the theme's master rows, with a mono/stereo switch. Not reproduced: the theme's "thin" mixer layout, rows dropping out on very short strips, folder indents, the master's logo and its denser meter scale. |
| Mydaw | A hand-made Ableton-style layout following the theme's script at any strip width: FX button, holder and bypass; input, input FX / monitor / record mode and the routing button at the top of the panel; volume readout, pan knob (bars on narrow strips and in the stereo and dual pan modes), the mute button carrying the track number, polarity, solo and record arm down the left; a thin meter with the fader's triangle on its right; the name at the bottom. The master follows the theme's master rows, with a mono/stereo switch; its meter narrows with the strip. A coloured track shows its colour behind the send list and in the name band. Not reproduced: the Return layout, folder indents, rows dropping out on short strips, the master's side scales. |
| CSIX AE-Narrow and SX (dark, light, slate, loom) | A hand-made layout following the one mixer script the six editions share, at any strip width: FX button and bypass, pan knob (knob pair with width, bars in dual pan), input, input FX, record mode and polarity down the top of the panel; volume readout, meter, fader on its groove, and the arm tab, monitor, mute, solo, routing and envelope buttons on its right; name and track number on their own bars. A coloured track tints the panel and send lists; each edition's text colours come from its script. The meter takes whatever width the strip has beyond the theme's 76 pt, the fader and buttons keeping their distance to it. The master is a track-like strip with a mono/stereo switch instead of the input rows. Not reproduced: the theme's wide master, the narrow and label-less variants, folder indents, rows dropping out on short strips, exact meter artwork. |
| Flat Madness 5.1.0 (CI and SI, Bright and Dark) | A hand-made layout following the one mixer macro the four editions share: a top card with record arm, record mode and monitor, the automation button, the input field, the track name, FX, bypass and input FX, and the pan knob with its readout (two bars in the stereo and dual pan modes); the track's colour in a bar between the cards; a lower card with the meter scale, the fader (the theme's tall cap image, its coloured fill running down from the cap) and volume readout, mute over solo, polarity and routing; the track number on the footer. The theme's own widths are followed: 80, 94 and 114 pt strips move the right-hand columns, and the meter takes whatever the panel has beyond the nearest one. The card greys come from the Theme Adjuster's *MCP background brightness* (brighter when selected), and the gloss option is followed. The master is a track-style strip (no input or arm rows, its tall mono/stereo switch above routing), not the theme's separate wide master. Not reproduced: that master, folder indents and brackets, the Meter-bridge and pan-slider layouts, the Adjuster's other *MCP solid background* choices, the coloured fader layouts (the default fader art is used), the strip's short-height form, the small tick marks beside the fader cap, exact meter artwork. |
| Anything else | A fixed Inspector layout with the theme's FX/send slot artwork, text and meter colours, and mute/solo artwork when compatible. Missing or incompatible buttons remain plain; knobs and faders use Inspector artwork. It does not copy the theme's control placement. |

**Theme archives** are read in place by a small built-in unzipper and are never modified. REAPER's drawing functions can only load images from files, so the images actually drawn (a few dozen) are copied on first use into the Inspector's own cache, `<REAPER resource folder>/Data/ReaperInspector/cache/<theme>-<fingerprint>/`. Each is checked against the archive's checksum first. The folder can be deleted at any time. A `.ReaperTheme` that points at an archive (how REAPER stores your colour tweaks to a zipped theme) is understood, and its colours win.

The hand-made layouts are **theme-specific; there is no generic WALTER engine**. `inspector/view.lua` uses the supported themes' wide mixer geometry. Default 6 and Reapertips v1.90 share an arrangement and adapt the pan and fader artwork to the theme. Reapertips v1.95 redesigned the strip (smaller record, envelope and record-mode buttons, framed drop-downs, envelope above polarity, the input box moving beside the record button on short strips), which is why it has its own layout. What is read from the theme at run time:

- The PNG artwork, at the 100/150/200% density matching the display.
- Each PNG's guide border. Pink lines mark margins that must not stretch (so the input arrow, button caps and rounded slot ends keep their exact pixels and only the flat middle stretches). Yellow lines mark art that overhangs its control (knob shadow, the white selected-track line above the number footer). Sprites are drawn 1:1 with nearest sampling; nothing is resampled except the small send-level knob.
- FX/send text colours and meter colours from the `.ReaperTheme` file (with built-in values as fallback for an asset-folder source).
- The list row height from `rtconfig.txt`.
- For Default 6- and 7-compatible mixer scripts, the theme's normal or selected backing art behind the FX and send slots, with the existing gray as a fallback.
- 80gray is recognised by its mixer script (row sizes and control rectangles), not its file name; its send rows are taller than its insert rows, as in the mixer.
- PhaseLab 1.3 and 2.0 use the shared 6-style strip with their compact control sizes and theme artwork. Their strip colour is layered as in the mixer (track colour, mixer background, then the theme's full-strip number-tile art, all behind the controls); the pan marker and the record-arm surround come from the theme's own images.

Theme-adjuster settings are not read: the panel uses the theme's default dim amounts, which matched the native mixer in testing.

Colour follows the theme's rules for a selected track: a track with a custom colour gets that colour on the pan/input panel and number footer (dimmed by the theme amounts, with the theme's tinted track-name colour); a track without one gets the theme's neutral grey. The Inspector always shows its track in the selected style, including the handle bar above the FX button and the white line above the number.

On macOS `gfx.ext_retina` scales both the framebuffer and pointer coordinates. The inspector converts these to logical coordinates once and snaps every edge to a device pixel. On Windows/Linux Retina is only a bitmap density hint. Those non-macOS branches are synthetic-test coverage, not native-platform verification.

### Theme Adjuster values

While the Inspector is following REAPER's theme it reads the Theme Adjuster's current values about once a second, so changing a setting there changes the Inspector too. A theme pinned with **Load theme...** uses that theme's built-in defaults instead, because REAPER only reports values for the theme it is using. Only the Default 7 layout, the Reapertips v1.95 colour settings and 80gray's selection-bar width and routing-diagram height use these values; anything not listed in the table above is not followed.

On Default 7 and on tall Default 6 strips, **In FX** opens the track's input FX chain.

## Controls

Top to bottom:

- **FX rack:** click a plug-in to show or hide its floating window. Shift-click toggles bypass, Alt-click removes it (both undoable). Click an empty slot to open REAPER's "Add FX to track" browser. That browser targets the track last clicked in REAPER, so if that is a different track the Inspector opens the FX chain instead and says so. Mouse-wheel scrolls a rack once it is full; a thin scrollbar appears only then, and a full rack scrolls one row past its last entry so there is always an empty slot to add into. Names are shortened the way the mixer shows them ("Kontakt 8", not "VST3i: Kontakt 8 (Native Instruments)"); names you typed yourself are left alone.
- **FX modifiers, as in the mixer:** Shift-click bypass, Alt-click delete, Cmd-click FX chain, Shift+Cmd-click offline, Alt+Shift-click bypass that slot on selected tracks (add Cmd for all tracks).
- **Right-click a plug-in or empty slot:** a menu in the same order as REAPER's: Add FX, Add container, Run in parallel with previous FX (and the merge-MIDI variant), Paste/Copy/Cut FX, Float FX configuration, Show FX chain, Bypass chain, Bypass/Offline/Delete FX, Rename FX instance, Bypass FX slot for selected/all tracks. **It is the Inspector's own menu**: REAPER gives scripts no way to open its native one. Left out because scripts cannot reach them: Quick add FX, Add FX chain, Replace/Quick replace, Move to container, multi-mono/multi-stereo, the "include automation" copy variants, FX parameters in panel, embedded UI in TCP/MCP. Copy/Cut/Paste use the Inspector's own clipboard (it works between tracks inside the Inspector but is not REAPER's clipboard); Paste inserts after the clicked slot.
- **Send rack:** hardware outputs, the track's MIDI hardware output (cyan), then track sends, each with a small level knob that is display-only. Click a track send to show its destination in the output strip (or, with the strip off or no room for it, the routing window); MIDI and hardware output rows always open the routing window. Shift-click mutes it, Alt-click removes it, Alt+Shift-click mutes that slot on selected tracks (add Cmd for all). Click an empty slot for the routing window too; right-click it to add a send.
- **Right-click a send:** Mute send, Remove send, Mute send slot for selected/all tracks, Show track routing window, Go to send destination track (selects it, so the Inspector follows), Add send to. "Show send parameters" and "MIDI/OSC learn" are not available to scripts. Hardware and MIDI output rows show the entries greyed except routing.
- **FX button / bypass light:** the button opens the FX chain; the light beside it bypasses or enables the whole chain.
- **Pan:** the Inspector follows the track's existing pan mode on either strip. Balance has one knob, stereo pan has separate pan and width knobs, and dual pan has independent horizontal sliders for the left and right channels. Shift-drag is fine adjustment. Double-click resets pan to center, width to 100%, or a dual-pan slider to its own side. The Inspector does not change the track's pan mode.
- **Input:** click for a menu of None, mono and stereo audio inputs, and MIDI devices/channels. ReaRoute and multichannel inputs are not listed.
- **IN / record mode:** click for the common record modes (input, stereo output, monitoring only, MIDI overdub, MIDI replace).
- **Record arm, monitoring, mute, solo, polarity:** click to toggle; monitoring cycles off → on → auto. Arm and monitoring can affect live audio, but only these explicit clicks change them. The inspector never starts transport or recording.
- **Routing button:** opens REAPER's routing window for the track. REAPER only offers that for its "last touched" track, so if the inspected track is not the one you last clicked in REAPER the Inspector says so instead of opening another track's routing.
- **Automation button:** click for the automation-mode menu.
- **Volume:** drag the cap or click/drag the lane. Shift-drag is fine adjustment, double-click returns to 0 dB. The cap position uses REAPER's own fader curve (`DB2SLIDER`/`SLIDER2DB`), so it sits where the mixer's does.
- **Meter:** stereo peaks on the theme's +6 to −62 dB scale, with a held-peak readout above. Click the meter to clear the readout. It is a peak display, not RMS/LUFS, and its lit colours are a ramp between the theme's meter colours rather than the mixer's exact meter drawing.

With multiple selected tracks, the first selected ordinary track is inspected. The master can appear in the output strip but cannot itself be the inspected track. Name/index, colour, state, FX, sends and peaks are polled without changing REAPER's selection. Automation envelopes are not edited; native automation may override static volume/pan values.

## Mutation and lifecycle boundaries

Construction, launch, drawing, selection changes and shutdown make no track/project edits. Inspector settings/diagnostics use only the `ReaperInspector` ExtState section. No REAPER INI/theme/project files are written by this code.

Every control write validates the current project, selected pointer, pointer validity, track GUID and selection generation. FX actions additionally recheck the plug-in's GUID at its slot, and send actions recheck that the slot still points at the same destination track; a stale target is refused. Drag capture is pinned to that identity; a selection change, deleted track or project switch cancels it rather than transferring the drag to another track. There is no grouping or selected-track ganging through these direct setters.

Each changed value owns a complete project-scoped Undo block within one callback, including setter exceptions. No Undo block is held across `defer`; this initial safety-first implementation can create several small Undo entries during a drag. Native grouping/undo consolidation is not promised. `defer` also suppresses automatic action Undo on no-op/duplicate/startup paths.

Registered reruns use supported `set_action_options(1)` when available. Direct/CLI duplicate starts request the incumbent's scoped stop and do not create another gfx window or steal its registry. Cleanup removes only the matching owner. Nonpersistent owner/stop state disappears on a REAPER restart; an unverified live owner is never reclaimed by a timer.

## Runtime receipt for read-only host verification

The `ReaperInspector` ExtState section exposes nonpersistent keys:

| Key | Meaning |
| --- | --- |
| `owner` | Unique active instance token; removed on clean stop |
| `status` | `running`, `stopped` or `error`; retained for inspection |
| `frame_count` | Completed UI frame count |
| `current_track_guid`, `current_track_name` | Last displayed track, empty if none |
| `current_project` | Last displayed project pointer string, diagnostic only |
| `theme_source`, `theme_directory` | Resolved theme source and asset location |
| `assets_loaded`, `assets_missing` | Successfully loaded image count and missing names |
| `error` | Last load/runtime error, empty if none |

Read these with `reaper.GetExtState('ReaperInspector', key)`. Receipts are per-field, not atomic snapshots; compare `frame_count` around a multi-key read if needed. Before a track is selected, artwork is lazily unloaded and `assets_loaded` can legitimately be zero. Stop retains the last receipt while releasing its owner. Persistent settings are only `theme`, `dock`, `width`, `height`.

For a read-only host smoke harness, `dofile('/absolute/path/inspector/app.lua')` returns the constructor (`App.new(reaper, gfx)`); `start()`, `frame()` and idempotent `stop()` are exposed. Importing modules does not start the application. The ordinary entrypoint alone runs the deferred scheduler. Do not use the synthetic test host as evidence of native readbacks.

## Offline checks

Run from this directory:

```sh
lua tests/run.lua
luac -p 'Reaper Inspector.lua' inspector/*.lua tests/*.lua
python3 tests/asset_audit.py
```

The Lua suite exercises the production modules with explicitly synthetic host/gfx APIs: read-only startup/selection, click handlers and menus, guide-margin slicing, FX/send identity checks, volume and pan modes, stale drag cancellation, balanced Undo on exceptions, theme/path handling, docking/stop/rerun lifecycle, and layout at several widths, heights and densities.

The Lua suite and the audit read the artwork of installed copies of the Reapertips theme (`ColorThemes/Reapertips Theme_Custom2`, a v1.90 copy, plus the stock v1.95 `Reapertips Theme.ReaperThemeZip`, its Light variant and REAPER's own `Default_7.0.ReaperThemeZip`), which are not in this repository; without them most tests cannot run.

The Python stdlib audit decodes every installed PNG the Inspector can draw (48 sprites × 3 densities) and checks that no guide pixels sit inside the cropped art.

`tests/preview.py` is a developer aid that renders one frame to a PNG without REAPER, for comparing layout against a screenshot. It needs a private Python environment with `lupa`, `pillow` and `numpy`; the Inspector itself does not. Its fonts and blending are approximations, so it is not evidence of what REAPER draws. `diagnostics/preview_0.3.0.png` is its output for the output strip.

## Official API reference

The implementation was checked against the official ReaScript reference fetched during this build:

https://www.reaper.fm/sdk/reascript/reascripthelp.html

Relevant sections: `gfx.blit`, `gfx.dock`, `gfx.loadimg`, `gfx.getpixel`, `gfx.triangle`, `gfx.showmenu`, `gfx.ext_retina`, `set_action_options`, `GetSelectedTrack2`, `ValidatePtr2`, `DB2SLIDER`, `SLIDER2DB`, `SetMediaTrackInfo_Value` and project-scoped Undo. Available APIs are still determined by the installed host. Actual host verification and screenshot matching remain a separate acceptance gate.

## Releasing a new version

Bump `@version` in `Reaper Inspector.lua`, commit, tag the commit `vX.Y.Z`, add a matching `<version>` block to `index.xml` whose file links point at that tag, then push the branch and the tag. ReaPack users get it on their next synchronise.
