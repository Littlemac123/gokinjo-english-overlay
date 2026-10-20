-- Manual untranslated-text reports. No game writes, native loads, or checkpoint writes.
local directory=assert(OVERLAY_REPORT_DIR)
local build=assert(OVERLAY_REPORT_BUILD)
local previousJapanese,previousBug,pending,serial=false,false,false,0
local function encode(value)
 local t=type(value)
 if t=='nil' then return 'null' end
 if t=='boolean' or t=='number' then return tostring(value) end
 if t=='string' then
  return '"'..value:gsub('[%z\1-\31\\"]',function(c)
   if c=='\\' then return '\\\\' elseif c=='"' then return '\\"' end
   return string.format('\\u%04x',string.byte(c))
  end)..'"'
 end
 assert(t=='table','Unsupported report value')
 local fields={};for k,v in pairs(value) do fields[#fields+1]=encode(tostring(k))..':'..encode(v) end
 table.sort(fields);return '{'..table.concat(fields,',')..'}'
end
local function write(path,data)
 local f=assert(io.open(path..'.tmp','wb'));assert(f:write(data));assert(f:close());assert(os.rename(path..'.tmp',path))
end
local function word(address) return emu.read16(address,emu.memType.snesMemory,false) end
local function notify(message) emu.displayMessage('Translation report',message) end
emu.addEventCallback(function()
 local japanese,bug=emu.isKeyPressed('S'),emu.isKeyPressed('D')
 if not pending then
  if bug and not previousBug then pending={kind='bug',phase='requested'}
  elseif japanese and not previousJapanese then pending={kind='untranslated',phase='requested'} end
 end
 previousJapanese,previousBug=japanese,bug
end,emu.eventType.inputPolled)
emu.addEventCallback(function()
 if not pending or pending.phase~='requested' then return end
 local kind=pending.kind;pending.phase='capturing'
 local ok,err=pcall(function()
  serial=serial+1
  local stamp=os.date('!%Y%m%d-%H%M%S');local stem
  repeat
   stem=directory..'/'..kind..'-'..stamp..'-'..tostring(OVERLAY.frame)..'-'..tostring(serial)
   local f=io.open(stem..'.json','rb');if not f then break end;f:close();serial=serial+1
  until false
  local png=emu.takeScreenshot()
  local record={format='gokinjo-untranslated-report-1',status='open',kind=kind,level=kind=='untranslated' and 1 or 2,classification=kind=='bug' and 'User-reported game/overlay bug; requires investigation' or 'User-marked untranslated text; requires source/context investigation',created_utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),build=build,
   screenshot_frame=OVERLAY.frame,map=word(0x7F6987),player_x=word(0x7E378E),player_y=word(0x7E380E),event_low=word(0x7E00D1),event_bank=word(0x7E00D3),native_text_index=word(0x7FE15C),
   overlay_hidden=OVERLAY.hidden,active_id=OVERLAY.active and OVERLAY.active.record.id,active_page=OVERLAY.active and OVERLAY.active.page,tail_id=OVERLAY.tail and OVERLAY.tail.record.id,
   names=OVERLAY_NAMES or {},screenshot=stem:match('[^/]+$')..'.png',savestate=stem:match('[^/]+$')..'.mss',capture_scope='Visible screenshot at end of frame; native savestate at next CPU execution. Native state alone does not preserve English page position. Does not replace F6/F7.'}
  local hook
  hook=emu.addMemoryCallback(function()
   emu.removeMemoryCallback(hook,emu.callbackType.exec,0,0xffffff,emu.cpuType.snes)
   local success,failure=pcall(function()
    local state=emu.createSavestate();record.state_overlay_frame=OVERLAY.frame
    write(stem..'.png',png);write(stem..'.mss',state)
    -- JSON is the commit marker. A report is complete only when it exists.
    if kind=='bug' then record.note_file=stem:match('[^/]+$')..'.txt';record.note_status='pending' end
    write(stem..'.json',encode(record)..'\n')
    if kind=='bug' then write(stem..'.bug-request','Describe game bug\n') end
   end)
   pending=false
   if success then notify('Saved '..stem:match('[^/]+$')) else notify('Could not save report: '..tostring(failure)) end
  end,emu.callbackType.exec,0,0xffffff,emu.cpuType.snes)
 end)
 if not ok then pending=false;notify('Could not capture: '..tostring(err)) end
end,emu.eventType.endFrame)
