-- Gokinjo English overlay, MesenCE 2.2.1. No ROM writes.
-- Bootstrap sets OVERLAY_ROOT; headless tests optionally set OVERLAY_TEST.
local root=assert(OVERLAY_ROOT,'Load via launch.sh or tools/run.py')
emu.selectDrawSurface(emu.drawSurface.consoleScreen)
local data=assert(loadfile(OVERLAY_CATALOG_PATH or root..'/catalog.lua'))()
assert(emu.getRomInfo().fileSha1Hash:lower()==data.sha1,'Overlay requires the fingerprinted original Japan ROM')
local O={hidden=false,prevX=false,active=nil,frame=0,release=false,prevA=false,events={},menuHits={},held=0,recover=true}
local adapters=nil
local nativeUI=assert(loadfile(OVERLAY_NATIVE_UI_PATH or root..'/native_ui.lua'))()()
OVERLAY=O -- test/diagnostic API; no synthetic dialogue in the normal launcher
local function log(event,fields)
 fields=fields or {};fields.event=event;fields.frame=O.frame;O.events[#O.events+1]=fields
 if OVERLAY_TEST and OVERLAY_TEST.event then OVERLAY_TEST.event(fields) end
end
local function byte(a) return emu.read(a,emu.memType.snesMemory,false) end
local function word(a) return byte(a)|(byte(a+1)<<8) end
local function pages(text,width,rows)
 local result={}
 for paragraph in (text..'\f'):gmatch('(.-)\f') do
  local lines={}
  for sourceLine in (paragraph..'\n'):gmatch('(.-)\n') do
   local line=''
   for token in sourceLine:gmatch('%S+') do
    if #line>0 and #line+1+#token>width then lines[#lines+1]=line;line='' end
    while #token>width do
     if #line>0 then lines[#lines+1]=line;line='' end
     lines[#lines+1]=token:sub(1,width);token=token:sub(width+1)
    end
    if #token>0 then line=line=='' and token or line..' '..token end
   end
   if #line>0 then lines[#lines+1]=line end
  end
  for i=1,#lines,rows do
   local group={};for j=i,math.min(i+rows-1,#lines) do group[#group+1]=lines[j] end
   result[#result+1]=table.concat(group,'\n')
  end
 end
 return result
end
O.paginate=pages
local byIndex={};for _,r in ipairs(data.dialogue) do
 local indices={r.index}
 if r.native_span then indices={};for _,part in ipairs(r.native_span.parts) do indices[#indices+1]=part.index end end
 for _,index in ipairs(indices) do byIndex[index]=byIndex[index] or {};table.insert(byIndex[index],r) end
end
local function address(r) return (r.source_base or 0x7F0000)+r.offset end
local function sourceBufferMatches(r)
 local selector=word(0x7FDC5B)
 if r.battle_binding and (selector~=0 or word(0x7F6207)~=1 or word(0x7F6987)~=14 or word(0xD3)~=0xC3 or word(0xD1)<0x0453 or word(0xD1)>0x0942)then return false end
 if r.source_base==0x7E6000 then if selector~=7 then return false end
 elseif r.source_base==0x7E0000 then if selector~=2 then return false end
 elseif selector~=0 and selector~=5 then return false end
 for i,v in ipairs(r.raw) do if byte(address(r)+i-1)~=v then return false end end
 if r.native_span then
  for _,part in ipairs(r.native_span.parts) do
   for i,v in ipairs(part.raw) do if byte(address(part)+i-1)~=v then return false end end
  end
  for i,index in ipairs(r.native_span.queue) do if word(0x7FE15C+2*(i-1))~=index then return false end end
  if word(0x7FE15C+2*#r.native_span.queue)~=0 then return false end
 end
 return true
end
local function sourceMatches(r)
 if word(0x7FDBE7)~=0 or not sourceBufferMatches(r) then return false end
 if not r.native_span then return word(0x7FDBDF)==r.index end
 local index=word(0x7FDBDF);local next=word(0x7FE1AC)
 for _,part in ipairs(r.native_span.parts) do
  if index==part.index and next==2*(part.queue_position+1) and (word(0x30)|(byte(0x32)<<16))==address(part) then
   local cursor=word(0x7FDBDD)
   if r.native_span.has_item then
    local used=part.items_before
    for _,offset in ipairs(part.item_offsets) do if cursor>offset then used=used+1 end end
    if word(0x7FDC2D)~=2*used then return false end
   end
   if r.native_span.has_number then
    local used=part.numbers_before+(part.number_offset and cursor>=part.number_offset+2 and 1 or 0)
    if word(0x7FDC3F)~=2*used then return false end
   end
   return true
  end
 end
 return false
end
-- During native name/item/number substitution, the live pointer is temporarily
-- outside the parent entry. A paired checkpoint still belongs to that exact
-- queue/part when its saved return cursor names the original substitution.
local function spanCheckpointMatches(r)
 if not r.native_span or not sourceBufferMatches(r) then return false end
 if sourceMatches(r) then return true end
 local mode=word(0x7FDBE7);local current=word(0x7FDBDF);local cursor=word(0x7FDBEF)
 for _,part in ipairs(r.native_span.parts) do
  if current==part.index and word(0x7FE1AC)==2*(part.queue_position+1) and cursor>=1 and cursor<#part.raw then
   if mode==3 and cursor>=2 and part.raw[cursor-1]==0xF9 and part.raw[cursor]>=2 and part.raw[cursor]<=8 then return true end
   if mode==1 and ((r.native_span.has_item and part.raw[cursor]==0xF8) or (r.native_span.has_number and part.number_offset and cursor==part.number_offset+2)) then return true end
  end
 end
 return false
end
local nativeEvents={};for _,r in ipairs(data.native_events or {}) do nativeEvents[r.index]=r end
local nativeHeaders={};for _,r in ipairs(data.native_headers or {}) do
 nativeHeaders[r.index]=nativeHeaders[r.index] or {};table.insert(nativeHeaders[r.index],r)
end
local function headerRecord(id)
 for _,header in ipairs(data.native_headers or {}) do if header.id==id then return header end end
end
local function headerFor(index)
 for _,header in ipairs(nativeHeaders[index] or {}) do if sourceBufferMatches(header) then return header end end
end
local function queueHeader(r)
 local cursor=word(0x7FE1AC);if cursor<2 or cursor>0x4E or cursor%2~=0 or not sourceBufferMatches(r) then return nil end
 local pos=cursor-2;local current=word(0x7FDBDF)
 if word(0x7FE15C+pos)~=current then return nil end
 if headerFor(current) and word(0x7FE15C+cursor)==r.index then pos=cursor
 else
  while pos>=0 and word(0x7FE15C+pos)~=r.index do
   local event=nativeEvents[word(0x7FE15C+pos)]
   if not event or not sourceBufferMatches(event) then return nil end
   pos=pos-2
  end
 end
 if pos<2 then return nil end
 local header=headerFor(word(0x7FE15C+pos-2))
 if header and sourceBufferMatches(header) then return header end
end
local function prefixRecord()
 local header=headerFor(word(0x7FDBDF));if not header or not sourceBufferMatches(header) then return nil end
 local cursor=word(0x7FE1AC);if cursor<2 or cursor>0x4E or cursor%2~=0 then return nil end
 for _,r in ipairs(byIndex[word(0x7FE15C+cursor)] or {}) do if queueHeader(r)==header then return r end end
end
local function identify()
 local pointer=word(0x30)|(byte(0x32)<<16)
 for _,r in ipairs(byIndex[word(0x7FDBDF)] or {}) do
  -- A fresh takeover must precede item/number consumption. After a native
  -- substitution, its argument slot may be reused; only an existing owner or
  -- a paired checkpoint with its saved content plan can continue that span.
  local fresh=not r.native_span or (not r.native_span.has_item or word(0x7FDC2D)==0) and (not r.native_span.has_number or word(0x7FDC3F)==0)
  if fresh and (r.native_span or pointer==address(r)) and sourceMatches(r) then return r end
 end
end
local function tailSourceMatches(r)
 if r.native_span then return word(0x7FDBDF)==r.native_span.parts[#r.native_span.parts].index and sourceMatches(r) end
 if sourceMatches(r) then return true end
 -- Original message queues can finish with a verified non-prose music event.
 -- Keep the last English speech only if the exact consumed queue still binds
 -- that speech, followed solely by source-checked original native events.
 local phase=word(0x7FE1AE)
 if (phase~=2 and phase~=3) or not sourceBufferMatches(r) then return false end
 local cursor=word(0x7FE1AC);if cursor<2 or cursor>0x50 or cursor%2~=0 then return false end
 if word(0x7FE15C+cursor-2)~=word(0x7FDBDF) then return false end
 for offset=cursor-2,0,-2 do
  local index=word(0x7FE15C+offset)
  if index==r.index then return true end
  local event=nativeEvents[index]
  if not event or not sourceBufferMatches(event) then return false end
 end
 return false
end
local function displayName(arg)
 local address=0x7F4928+(arg-2)*4
 local b={};for i=0,3 do b[#b+1]=byte(address+i) end
 local hex={};for _,v in ipairs(b) do hex[#hex+1]=string.format('%02x',v) end
 local raw=table.concat(hex)
 local defaults={['8076bcbc']='MANA',['170b180b']='MANA',['88e0bcbc']='YUZU',['231f241f']='YUZU',['35313531']='SNIFFLES',['86908bbc']='YAWARA',['ce3139bb']='DOCTOR',['58575b36']='LAWRENCE',['76766abc']='NANAKO'}
 local alias=OVERLAY_NAMES and OVERLAY_NAMES[string.format('%02X',arg)]
 if alias and alias.source_raw==raw then return alias.display end
 if defaults[raw] then return defaults[raw] end
 local chars={};for _,v in ipairs(b) do
  if v==0xBC then chars[#chars+1]=' '
  elseif v>=1 and v<=0x24 then chars[#chars+1]=('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'):sub(v,v)
  else return nil end
 end
 return table.concat(chars):gsub(' +$','')
end
O.displayName=displayName
local function battleTarget(index)
 local found=nil
 for _,entry in ipairs(data.battle_names or {})do if entry.index==index then found=entry;break end end
 if not found then return nil end
 local tableOffset=word(0x7F0006);local offset=word(0x7F0000+tableOffset+2*index)
 if offset~=found.offset then return nil end
 for i,value in ipairs(found.raw)do if byte(0x7F0000+offset+i-1)~=value then return nil end end
 return found
end
local function begin(r,overrideLayout,restoredHeader)
 if O.battleRejected and O.battleRejected.id==r.id then return end
 local unresolved=false
 local header=restoredHeader or queueHeader(r)
 if not header and r.stock_choice_header and word(0x7FDBC7)==0 and adapters and adapters.choicePair() then
  local known=headerFor(r.stock_choice_header);if known and sourceBufferMatches(known) then header=known end
 end
 local template=header and not r.flow_caption and header.text..'\n'..r.text or r.text
 local text=template:gsub('{name:(%x%x)}',function(arg)
  local name=displayName(tonumber(arg,16));if not name then unresolved=true;return '' end;return name
 end)
 local nativeBindings={}
 if r.battle_binding then
  if not sourceBufferMatches(r) then log('unsupported-battle-context',{id=r.id});return end
  if r.battle_binding.actor then
   local index=word(0x7FDC21)
   if index>5 then log('unsupported-battle-actor',{id=r.id,index=index});return end
   local name=displayName(index+2);if not name then log('unsupported-battle-actor',{id=r.id,index=index});return end
   nativeBindings.battle_actor=index;text=text:gsub('{actor}',function()return name end)
  end
  if r.battle_binding.target then
   local index=word(0x7FDC29);local found=battleTarget(index)
   if not found then log('unsupported-battle-target-source',{id=r.id,index=index});return end
   nativeBindings.battle_target=index;text=text:gsub('{target}',function()return found.text end)
  end
  if r.battle_binding.number then
   local mode,cursor=word(0x7FDC2F),word(0x7FDC3F)
   -- Exact actual Sunday damage call traced at cursor zero. Additional
   -- argument slots and calendar mode need their own original-caller proof.
   if (mode~=1 and mode~=3 and mode~=4)or mode==4 and word(0x7FDDB9)==1 or cursor~=0 then log('unsupported-battle-number',{id=r.id,mode=mode,cursor=cursor});return end
   local packed=word(0x7FDDBF+cursor);local amount=0;local place=1
   for shift=0,12,4 do local digit=(packed>>shift)&15;if digit>9 then log('unsupported-battle-number',{id=r.id,packed=packed});return end;amount=amount+digit*place;place=place*10 end
   nativeBindings.battle_number=packed;nativeBindings.battle_number_mode=mode;nativeBindings.battle_number_cursor=cursor
   text=text:gsub('{number}',tostring(amount));log('battle-number',{id=r.id,amount=amount,packed=packed,cursor=cursor,mode=mode})
  end
  if text:find('{actor}',1,true)or text:find('{target}',1,true)or text:find('{number}',1,true)then log('unsupported-battle-template',{id=r.id});return end
 end
 if r.native_span and r.native_span.has_item then
  local index=word(0x7FDC19);local item=data.items[index+1]
  if not item or item.index~=index or not item.text:match('%S') then log('unsupported-item',{id=r.id,index=index});return end
  for i,v in ipairs(item.raw) do if byte(tonumber(item.id,16)+0xC00000+i-1)~=v then log('unsupported-item-source',{id=r.id,index=index});return end end
  nativeBindings.item=index;text=text:gsub('{item}',function() return item.text end);log('native-item',{id=r.id,index=index,text=item.text})
 end
 if r.native_number or r.native_span and r.native_span.has_number then
  local kind=word(0x7FDC2F)
  if (kind~=1 and kind~=3 and kind~=4) or kind==4 and word(0x7FDDB9)==1 then log('unsupported-number',{id=r.id,kind=kind});return end
  local packed=word(0x7FDDBF);local amount=0;local place=1
  for shift=0,12,4 do
   local digit=(packed>>shift)&15
   if digit>9 then log('unsupported-number',{id=r.id,kind=kind});return end
   amount=amount+digit*place;place=place*10
  end
  if r.native_span then nativeBindings.amount=packed;nativeBindings.mode=kind end
  text=text:gsub('{amount}',tostring(amount));log('native-number',{id=r.id,kind=kind,packed=packed,amount=amount})
 end
 if r.native_calendar then
  local index=word(0x7F4AB2)
  if word(0x7FDC2F)~=2 or index>=365 then log('unsupported-calendar',{id=r.id,index=index});return end
  local monthRaw,dayRaw=byte(0xDB7C97+index),byte(0xDB7E04+index)
  -- C09D2F consumes packed decimal nibbles, not binary month/day values.
  if (monthRaw&15)>9 or (dayRaw&15)>9 then log('unsupported-calendar',{id=r.id,index=index});return end
  local month,day=(monthRaw>>4)*10+(monthRaw&15),(dayRaw>>4)*10+(dayRaw&15)
  local months={'JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'}
  if not months[month] or day<1 or day>31 then log('unsupported-calendar',{id=r.id,index=index});return end
  text=text:gsub('{month}',months[month]):gsub('{day}',tostring(day))
  log('native-calendar',{id=r.id,index=index,month=month,day=day})
 end
 if unresolved then log('unsupported-name',{id=r.id});return end
 local caption=false;for _,code in ipairs(r.raw) do if code==0xA2 and not r.flow_caption and not header then caption=true end end
 local layout
 if r.battle_binding then
  -- Native battle narration uses the purple BG2 frame; BG3 contains the HP
  -- frame and text only. The field working width also overlaps the portrait.
  local state=nativeUI.frameState();local base=state['ppu.layers[1].tilemapAddress']*2
  local function tile(row,col)return emu.read16((base+2*(row*32+col))%65536,emu.memType.snesVideoRam,false)&0xC3FF end
  if state['ppu.layers[1].hscroll']~=0 or state['ppu.layers[1].vscroll']~=0 or tile(18,2)~=0x000D or tile(18,19)~=0x000F or tile(25,2)~=0x002D or tile(25,19)~=0x002F then log('unsupported-battle-frame',{id=r.id});return end
  layout={left=2,upper=18,cols=16,height=6,width=15,rows=3,bodyRow=19,bodyHeight=6}
 else layout=overrideLayout or nativeUI.dialogueLayout(caption)end
 if layout and overrideLayout then
  local skip=caption and 2 or 0
  layout={left=layout.left,upper=layout.upper,cols=layout.cols,height=layout.height,width=layout.cols-1,rows=math.floor((layout.height-skip)/2),bodyRow=layout.upper+1+skip,bodyHeight=layout.height-skip}
 end
 if not layout then log('unsupported-window',{id=r.id});return end
 local p=pages(text,layout.width,layout.rows);if #p==0 then return end
 O.tail=nil;O.prefix=nil
 O.active={layout=layout,record=r,pages=p,page=1,phase='reading',cursor=word(0x7FDBDD),header=header,nativeBindings=nativeBindings,content=text:gsub('.',function(c) return string.format('%02x',c:byte()) end)}
 log('dialogue-open',{id=r.id,pages=#p,cursor=O.active.cursor,header=header and header.id or '-'})
end
local function retainActive(recovering)
 local a=assert(O.active)
 O.tail={record=a.record,layout=a.layout,text=a.pages[#a.pages],windowKey=a.windowKey,recovering=recovering,content=a.content,header=a.header}
 O.active=nil
end
local function recoverDialogue()
 O.recover=false;local r=identify();local choice=adapters and adapters.choicePair()
 if not r and choice then
  for _,candidate in ipairs(byIndex[word(0x7FDBDF)] or {}) do if tailSourceMatches(candidate,choice) then r=candidate;break end end
 end
 if r then
  local role=r.raw[1]==0xF9 and (r.raw[2]==0x11 or r.raw[2]==0x12 or r.raw[2]==0x13 or r.raw[2]==0x14)
  if word(0x7FDBDD)<(r.native_start_cursor or (role and 2 or 0)) and word(0x7FDBC7)~=0 then return end
  local complete=word(0x7FDBC7)==0;local recoveredLayout=nil
  if complete then
   local header=queueHeader(r)
   local caption=false;for _,code in ipairs(r.raw) do if code==0xA2 and not r.flow_caption and not header then caption=true end end
   local layout=choice and nativeUI.findDialogueLayout(caption) or nativeUI.dialogueLayout(caption)
   if not layout or not nativeUI.dialogueWindowKey(layout,choice) then return end
   recoveredLayout=layout
  end
  begin(r,recoveredLayout);O.release=true;O.prevA=true;O.prevX=true
  if O.active and complete then
   if OVERLAY_RECOVER_COMPLETED_TAIL then retainActive(true);log('dialogue-tail-recovered',{id=r.id})
   else O.active.nativeComplete=true;log('completed-dialogue-replay',{id=r.id}) end
  end
 end
end
local cinema=assert(loadfile(OVERLAY_CINEMATIC_PATH or root..'/cinematic.lua'))()({O=O,U=nativeUI,word=word,byte=byte,log=log,pages=pages,records=data.cinematics,resolveName=displayName,resolveHeader=queueHeader,headerRecord=headerRecord,buttons={'a','b','x','y','l','r','start','select','up','down','left','right'}})
O.cinema=cinema
emu.addMemoryCallback(function()
 if cinema.dispatch() then return end
 if not O.active then
  local event=nativeEvents[word(0x7FDBDF)]
  if not (O.tail and event and sourceBufferMatches(event) and tailSourceMatches(O.tail.record)) then O.tail=nil end
  local r=identify()
  -- The original F9 role prefix prepares portrait/layout before any glyph.
  -- Let that nonprinting prefix run, then hold before the native bullet/name.
  local role=r and r.raw[1]==0xF9 and (r.raw[2]==0x11 or r.raw[2]==0x12 or r.raw[2]==0x13 or r.raw[2]==0x14)
  if r and word(0x7FDBDD)>=(r.native_start_cursor or (role and 2 or 0)) then begin(r) end
 end
end,emu.callbackType.exec,0xC09B1A,0xC09B1A,emu.cpuType.snes)
-- C09992 is the entry before PHB; C099D1 is an existing bare RTL.
-- Holding this routine leaves DBC7 busy and preserves CPU registers/stack.
-- The rest of the game, including its audio and original waiting animations,
-- remains in its normal loop. No savestate rewind is used as a freeze trick.
emu.addMemoryCallback(function()
 if cinema.hold() then return end
 if O.recover and word(0x7FDBC7)~=0 then
  recoverDialogue()
 end
 if O.battleRejected and (word(0x7FDBDF)~=O.battleRejected.index or not sourceBufferMatches(O.battleRejected) or word(0x7FDBC7)==0)then O.battleRejected=nil end
 local active=O.active;local bindings=active and active.nativeBindings or {}
 if active and active.phase=='reading' and bindings.battle_number and (word(0x7FDC2F)~=bindings.battle_number_mode or word(0x7FDC3F)~=bindings.battle_number_cursor or word(0x7FDDBF+bindings.battle_number_cursor)~=bindings.battle_number)then log('battle-number-invalidated',{id=active.record.id});O.battleRejected=active.record;O.active=nil;O.tail=nil;O.release=true end
 if active and active.record.battle_binding and (not sourceBufferMatches(active.record)or bindings.battle_actor and word(0x7FDC21)~=bindings.battle_actor or bindings.battle_target and (word(0x7FDC29)~=bindings.battle_target or not battleTarget(bindings.battle_target)))then log('battle-binding-invalidated',{id=active.record.id});O.battleRejected=active.record;O.active=nil;O.tail=nil;O.release=true end
 if active and active.record.native_span and (not sourceBufferMatches(active.record) or (bindings.item and word(0x7FDC19)~=bindings.item) or (bindings.amount and (word(0x7FDDBF)~=bindings.amount or word(0x7FDC2F)~=bindings.mode or bindings.mode==4 and word(0x7FDDB9)==1))) then
  log('native-span-invalidated',{id=O.active.record.id});O.active=nil;O.tail=nil;O.release=true
 end
 if O.active and O.active.phase=='reading' then
  local s=emu.getCpuState(emu.cpuType.snes);s['pc']=0x99D1;emu.setCpuState(s,emu.cpuType.snes);O.held=O.held+1
 end
end,emu.callbackType.exec,0xC09992,0xC09992,emu.cpuType.snes)
-- Supply an advance ONLY to the original FC wait handler's exact input read.
-- No A is injected into controller state or menu/choice input processing.

-- Increase only the original reader's temporary character quota after English
-- has been acknowledged. Do not alter its stored speed, controller or events.
local drainQuotaRead=false
emu.addMemoryCallback(function()drainQuotaRead=true end,emu.callbackType.exec,0xC09B08,0xC09B08,emu.cpuType.snes)
emu.addMemoryCallback(function(_,value)
 local armed=drainQuotaRead;drainQuotaRead=false
 local active=O.active
 if armed and active and active.phase=='draining'and sourceMatches(active.record)then
  if not active.drainBudgetLogged then active.drainBudgetLogged=true;log('native-drain-quota',{id=active.record.id,budget=32})end
  return math.max(value,32)
 end
 return value
end,emu.callbackType.read,0x7FDC3D,0x7FDC3D,emu.cpuType.snes)
local waitRead=false;local closeRead=nil
emu.addMemoryCallback(function() waitRead=true end,emu.callbackType.exec,0xC0AA0A,0xC0AA0A,emu.cpuType.snes)
emu.addMemoryCallback(function(_,value)
 local armed=waitRead;waitRead=false;local closing=closeRead;closeRead=nil
 if armed and cinema.present() then return cinema.wait(value) end
 if closing and word(0x7FE1AE)==3 and cinema.present() then return cinema.close(value) end
 if armed and O.active and O.active.phase=='draining' and sourceMatches(O.active.record) then
  log('native-page-advance',{id=O.active.record.id,cursor=word(0x7FDBDD)})
  return 0x80
 end
 if closing and OVERLAY_AUTO_CLOSE~=false and O.tail and not O.active and word(0x7FE1AE)==3 and tailSourceMatches(O.tail.record) then
  log('native-message-close',{id=O.tail.record.id,pc=closing});return 0x80
 end
 return value
end,emu.callbackType.read,0x7E2990,0x7E2990,emu.cpuType.snes)
-- These two reads belong to the original completed-message closing handler
-- (C0B718 dispatch), not the native choice-selection handler.
for _,pc in ipairs({0xC0B754,0xC0B75F}) do
 emu.addMemoryCallback(function() closeRead=pc end,emu.callbackType.exec,pc,pc,emu.cpuType.snes)
end
emu.addMemoryCallback(function()
 if O.active and O.active.phase=='draining' and sourceMatches(O.active.record) then
  local span=O.active.record.native_span
  if span and word(0x7FDBDF)~=span.parts[#span.parts].index then log('native-span-part-complete',{id=O.active.record.id,index=word(0x7FDBDF)});return end
  log('dialogue-complete',{id=O.active.record.id,cursor=word(0x7FDBDD)})
  retainActive(false);O.release=true
 end
end,emu.callbackType.exec,0xC09B3D,0xC09B3D,emu.cpuType.snes)
local buttons={'a','b','x','y','l','r','start','select','up','down','left','right'}
local function input()
 local raw=emu.getInput(0)
 if OVERLAY_TEST and OVERLAY_TEST.input then raw=OVERLAY_TEST.input(O.frame,raw,O) end
 -- Establish completed-source recovery before a held load-time button can
 -- close the native window. Closed/unknown windows are checked on this frame.
 if O.recover and word(0x7FDBC7)==0 and (identify() or byIndex[word(0x7FDBDF)] and adapters and adapters.choicePair()) then
  local mask={};for _,b in ipairs(buttons) do mask[b]=false end;emu.setInput(mask,0)
  O.prevA=raw.a==true;O.prevX=raw.x==true
  if adapters then adapters.discardInput(raw) end
  return
 end
 local overlayPresent=cinema.present() or O.active~=nil or O.tail~=nil or O.prefix~=nil or O.menuPresent or (adapters and (adapters.editor or adapters.viewer or adapters.context))
 local x=raw.x==true;local xEdge=x and not O.prevX;O.prevX=x
 if overlayPresent and xEdge then O.hidden=not O.hidden;log('overlay-visibility',{hidden=O.hidden}) end
 if overlayPresent and x then emu.setInput({x=false},0);raw.x=false end
 if O.hidden and overlayPresent then
  cinema.discard(raw)
  if adapters then adapters.discardInput(raw) end
  O.prevA=raw.a==true
  if cinema.present() or O.active or O.release or (adapters and (adapters.editor or adapters.viewer)) then
   local mask={};for _,b in ipairs(buttons) do mask[b]=false end;emu.setInput(mask,0)
  elseif OVERLAY_TEST then emu.setInput(raw,0) end
  return
 end
 -- Release barriers apply before editor/menu input as well as dialogue input.
 -- A held across the previous message cannot type into a newly opened editor.
 if O.release then
  if adapters then adapters.discardInput(raw) end
  local any=false;local mask={};for _,b in ipairs(buttons) do any=any or raw[b]==true;mask[b]=false end
  emu.setInput(mask,0);O.prevA=raw.a==true
  if not any then O.release=false;O.prevA=false;log('input-released') end
  return
 end
 if cinema.input(raw) then return end
 if adapters and adapters.input(raw) then O.prevA=raw.a==true;return end
 local any=false;for _,b in ipairs(buttons) do any=any or raw[b]==true end
 local a=raw.a==true;local edge=a and not O.prevA;O.prevA=a
 local blocking=O.active~=nil or O.release
 if O.active and O.active.phase=='reading' and edge then
  if O.active.page<#O.active.pages then
   O.active.page=O.active.page+1;log('english-page',{id=O.active.record.id,page=O.active.page})
  else
   O.active.phase='draining';log('english-finished',{id=O.active.record.id})
   if O.active.nativeComplete then
    local id=O.active.record.id;retainActive(false);O.release=true;log('completed-dialogue-replay-finished',{id=id})
   end
  end
 end
 if blocking then
  local mask={};for _,b in ipairs(buttons) do mask[b]=false end
  emu.setInput(mask,0)
 elseif OVERLAY_TEST then emu.setInput(raw,0) end
 -- A held on entry cannot skip a page; held controls cannot leak on exit.
 if O.release and not any then O.release=false;O.prevA=false;log('input-released') end
end
emu.addEventCallback(function()
 if OVERLAY_TEST and OVERLAY_TEST.guard then OVERLAY_TEST.guard(input) else input() end
end,emu.eventType.inputPolled)
local function vword(a)
 return emu.read(a,emu.memType.snesVideoRam,false)|(emu.read((a+1)%65536,emu.memType.snesVideoRam,false)<<8)
end
local menusByTile={};local emptyMenus={}
for _,m in ipairs(data.menus) do
 local first=m.tiles[1];menusByTile[first]=menusByTile[first] or {};table.insert(menusByTile[first],m)
end
local function menuOverlay(scanOnly)
 local top=emu.getDrawSurfaceSize(emu.drawSurface.consoleScreen).overscan.top
 local words=nativeUI.tilemap()
 if not words then return end
 for row=0,27 do
  for col=0,31 do
   local first=words[row*32+col+1]
   for _,m in ipairs(menusByTile[first&1023] or emptyMenus) do
    if col+#m.tiles<=32 and first&1023==m.tiles[1] and first&0xC000==0 then
     local match=true
     for k,tile in ipairs(m.tiles) do
      local v=words[row*32+col+k]
      if v&1023~=tile or v&0xFC00~=first&0xFC00 then match=false;break end
     end
     local owned=(m.english=='YES' or m.english=='NO') or (row==2 and col==2 and m.english=='ITEMS') or (row==7 and (m.english=='ITEMS' or m.english=='WEAPONS' or m.english=='CLOTHING' or m.english=='CHARMS' or m.english=='TREASURES')) or (col==25 and (row==3 or row==5 or row==7 or row==9) and m.id:match('^operation:'))
     local english=m.english
     if match and m.native_save_slot then
      local slot=words[row*32+col+#m.tiles+1]&1023
      if slot==2 or slot==3 then english=english..tostring(slot-1) else match=false end
     end
     if match and not owned then
      O.menuPresent=true
      if not scanOnly then
      local pal=(first>>10)&7
      local width=m.field_cols or math.max(#m.tiles,#english)
      if not nativeUI.suppress(row,col,width,2) then nativeUI.erase(col*8,row*8+top,width*8,16,pal) end
      if #english<=width and not m.small_font then nativeUI.text(col*8,row*8+top,english,pal)
      else
       local y=row*8+top+(english:find('\n',1,true) and 0 or 3)
       if m.character_advance then
        local x=col*8
        for c in english:gmatch('.') do
         if c=='\n' then x=col*8;y=y+8 else emu.drawString(x,y,c,nativeUI.color(pal,3),0xFF000000);x=x+m.character_advance end
        end
       else emu.drawString(col*8,y,english,nativeUI.color(pal,3),0xFF000000) end
      end
      if not O.menuHits[m.id] then O.menuHits[m.id]=true;log('menu-label',{id=m.id,row=row,col=col}) end
      end
     end
    end
   end
  end
 end
end
local function draw()
 O.menuPresent=false;O.prefix=nil
 if not O.active and not O.tail then
  local record=prefixRecord();local header=record and queueHeader(record)
  local layout=header and nativeUI.dialogueLayout(false)
  if layout and nativeUI.dialogueWindowKey(layout) then
   local resolved=true;local text=header.text:gsub('{name:(%x%x)}',function(arg) local name=displayName(tonumber(arg,16));if not name then resolved=false;return '' end;return name end)
   if resolved then O.prefix={layout=layout,text=pages(text,layout.width,layout.rows)[1] or '',fullText=text} end
  end
 end
 if O.recover and word(0x7FDBC7)==0 then recoverDialogue() end
 if O.tail and O.tail.recovering then O.tail.windowKey=nativeUI.dialogueWindowKey(O.tail.layout);O.tail.recovering=nil end
 local yes,no=nil,nil;if (O.tail or O.active and O.active.nativeComplete) and adapters then yes,no=adapters.choicePair() end
 if O.tail and (not tailSourceMatches(O.tail.record,yes) or not O.tail.windowKey or nativeUI.dialogueWindowKey(O.tail.layout,true)~=O.tail.windowKey) then
  log('dialogue-tail-cleared',{id=O.tail.record.id,source_match=tailSourceMatches(O.tail.record),key_present=O.tail.windowKey~=nil,key_match=nativeUI.dialogueWindowKey(O.tail.layout,true)==O.tail.windowKey,queue=word(0x7FE1AC),phase=word(0x7FE1AE),native_index=word(0x7FDBDF),native_mode=word(0x7FDBE7),native_state=word(0x7FDBC7)});O.tail=nil
 end
 if O.hidden then
  menuOverlay(true)
  emu.drawString(8,222,'X: show English',0x00FFFFFF,0x00080828)
 elseif adapters and adapters.viewer then adapters.drawViewer()
 elseif adapters and adapters.editor then adapters.drawEditor()
 elseif cinema.present() then cinema.draw()
 elseif O.active then
  O.active.windowKey=nativeUI.dialogueWindowKey(O.active.layout,yes)
  nativeUI.dialogue(O.active.layout,O.active.pages[O.active.page],O.active.phase=='reading',O.frame)
  if yes then adapters.drawChoice(yes,no) end
 elseif O.tail then
  nativeUI.dialogue(O.tail.layout,O.tail.text,false,O.frame)
  if yes then adapters.drawChoice(yes,no) end
 elseif O.prefix then nativeUI.dialogue(O.prefix.layout,O.prefix.text,false,O.frame)
 else menuOverlay();if adapters then adapters.drawMenus() end end
end
emu.addEventCallback(function()
 O.frame=O.frame+1;waitRead=false;nativeUI.begin();draw();nativeUI.finish()
 if OVERLAY_TEST and OVERLAY_TEST.frame then OVERLAY_TEST.frame(O) end
end,emu.eventType.endFrame)
local function reset()
 cinema.reset()
 O.active=nil;O.tail=nil;O.prefix=nil;O.menuPresent=false;O.release=true;O.prevA=true;O.recover=true;waitRead=false;closeRead=nil;O.hidden=false;O.prevX=true
 if adapters then adapters.reset() end
 log('state-reset')
end
emu.addEventCallback(reset,emu.eventType.stateLoaded)
emu.addEventCallback(reset,emu.eventType.reset)
adapters=assert(loadfile(OVERLAY_ADAPTER_PATH or root..'/adapters.lua'))()({O=O,word=word,byte=byte,log=log,displayName=displayName,pages=pages,data=data,root=root,nativeUI=nativeUI})
O.adapters=adapters
log('extension-ready',{sha1=data.sha1})

-- Managed paired checkpoints. F6 saves and F7 loads emulator + host overlay state.
-- Normal Mesen savestate loads restart supported English from its beginning.
local function hostText()
 local a=O.active
 local lines={'GOKINJO-OVERLAY-1',data.sha1,assert(OVERLAY_CATALOG_HASH),a and a.record.id or '-',a and tostring(a.page) or '0',a and a.phase or '-',O.release and '1' or '0'}
 if O.tail and O.tail.windowKey then
  lines[#lines+1]='TAIL\t'..O.tail.record.id..'\t'..assert(O.tail.windowKey)
  local values={};for _,k in ipairs({'left','upper','cols','height','width','rows','bodyRow','bodyHeight'}) do values[#values+1]=O.tail.layout[k] end
  lines[#lines+1]='TAIL_LAYOUT\t'..table.concat(values,',')
 end
 if a and a.nativeComplete then
  lines[#lines+1]='NATIVE_COMPLETE\t1'
  local values={};for _,k in ipairs({'left','upper','cols','height','width','rows','bodyRow','bodyHeight'}) do values[#values+1]=a.layout[k] end
  lines[#lines+1]='SOURCE_LAYOUT\t'..table.concat(values,',')
 end
 if (a or O.tail) and (a or O.tail).header then lines[#lines+1]='HEADER\t'..(a or O.tail).header.id end
 if a or O.tail then lines[#lines+1]='CONTENT\t'..assert((a or O.tail).content) end
 if a then lines[#lines+1]='LAYOUT\t'..a.layout.width..'\t'..a.layout.rows end
 lines[#lines+1]='VISIBILITY\t'..(O.hidden and '1' or '0')
 local cinematicLine=cinema.serialize();if cinematicLine then lines[#lines+1]=cinematicLine end
 local editor=adapters and adapters.serialize();if editor then lines[#lines+1]=editor end
 for arg,n in pairs(OVERLAY_NAMES or {}) do lines[#lines+1]='NAME\t'..arg..'\t'..n.source_raw..'\t'..n.display end
 return table.concat(lines,'\n')
end
local function requestCheckpoint(op)
 if O.checkpointPending then return end
 O.checkpointPending=true
 local id
 id=emu.addMemoryCallback(function()
  emu.removeMemoryCallback(id,emu.callbackType.exec,0,0xffffff,emu.cpuType.snes)
  O.checkpointPending=false
  local stem=OVERLAY_CHECKPOINT_STEM or root..'/runtime/checkpoint'
  if op=='save' then
   local bundle=hostText()..'\0'..emu.createSavestate()
   local f=assert(io.open(stem..'.tmp','wb'));f:write(bundle);f:close()
   assert(os.rename(stem..'.tmp',stem..'.bin'))
   log('paired-checkpoint-saved')
  else
   local f=io.open(stem..'.bin','rb');if not f then log('checkpoint-missing');return end
   local bundle=f:read('*a');f:close()
   local separator=assert(bundle:find('\0',1,true),'Invalid checkpoint bundle')
   local text=bundle:sub(1,separator-1);local state=bundle:sub(separator+1);local lines={}
   for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
   local compatible=lines[3]==OVERLAY_CATALOG_HASH
   for _,hash in ipairs(data.compatible_checkpoint_catalogs or {}) do compatible=compatible or lines[3]==hash end
   local specificMigration=false
   if not compatible and lines[6]=='reading' then
    for _,migration in ipairs(data.checkpoint_source_migrations or {}) do
     if lines[3]==migration.catalog_sha256 and lines[4]==migration.record then
      local f=io.open(root..'/'..migration.reference,'rb')
      if f then local reference=f:read('*a');f:close();if bundle==reference then compatible=true;specificMigration=true end end
     end
    end
   end
   if not (lines[1]=='GOKINJO-OVERLAY-1' and lines[2]==data.sha1 and compatible) then log('checkpoint-rejected',{reason='ROM/catalog mismatch'});return end
   local record=nil
   if lines[4]~='-' then
    for _,r in ipairs(data.dialogue) do if r.id==lines[4] then record=r end end
    assert(record and (lines[6]=='reading' or lines[6]=='draining'),'Invalid overlay checkpoint')
   end
   local cinematicLine=nil
   for i=8,#lines do if lines[i]:match('^CINEMA\t') then cinematicLine=lines[i] end end
   if cinematicLine and not cinema.validate(cinematicLine) then log('checkpoint-rejected',{reason='Cinematic content/plan changed'});return end
   assert(#state>1000,'Truncated checkpoint')
   emu.loadSavestate(state);nativeUI.resetMasks()
   if specificMigration then assert(record and identify()==record and word(0x7FDBC7)~=0,'Historical opening native source mismatch') end
   local names={};local editorLine=nil;local tailId,tailKey=nil,nil;local tailLayout=nil;local sourceLayout=nil;local nativeComplete=false;local hidden=false;local layoutWidth,layoutRows=nil,nil;local savedContent=nil;local savedHeader=nil
   for i=8,#lines do
    if lines[i]:match('^CINEMA\t') then -- Validated above before loading native state.
    elseif lines[i]:match('^VISIBILITY\t') then hidden=lines[i]=='VISIBILITY\t1'
    elseif lines[i]:match('^HEADER\t') then
     local id=lines[i]:sub(8)
     for _,h in ipairs(data.native_headers or {}) do if h.id==id then savedHeader=h;break end end
     assert(savedHeader and sourceBufferMatches(savedHeader),'Saved speaker-header source mismatch')
    elseif lines[i]:match('^CONTENT\t') then savedContent=lines[i]:sub(9);assert(savedContent:match('^%x+$'),'Invalid English content plan')
    elseif lines[i]:match('^LAYOUT\t') then local width,rows=lines[i]:match('^LAYOUT\t(%d+)\t(%d+)$');layoutWidth=assert(tonumber(width));layoutRows=assert(tonumber(rows))
    elseif lines[i]=='NATIVE_COMPLETE\t1' then nativeComplete=true
    elseif lines[i]:match('^SOURCE_LAYOUT\t') then
     local values={};for v in lines[i]:sub(15):gmatch('%d+') do values[#values+1]=tonumber(v) end
     assert(#values==8,'Invalid source dialogue geometry');sourceLayout={}
     for n,k in ipairs({'left','upper','cols','height','width','rows','bodyRow','bodyHeight'}) do sourceLayout[k]=values[n] end
     assert(sourceLayout.left+sourceLayout.cols+1<=31 and sourceLayout.upper+sourceLayout.height+1<=27 and sourceLayout.width==sourceLayout.cols-1 and sourceLayout.rows>0,'Source geometry outside native frame')
    elseif lines[i]:match('^TAIL_LAYOUT\t') then
     local values={};for v in lines[i]:sub(13):gmatch('%d+') do values[#values+1]=tonumber(v) end
     assert(#values==8,'Invalid retained dialogue geometry');tailLayout={}
     for n,k in ipairs({'left','upper','cols','height','width','rows','bodyRow','bodyHeight'}) do tailLayout[k]=values[n] end
     assert(tailLayout.left+tailLayout.cols+1<=31 and tailLayout.upper+tailLayout.height+1<=27 and tailLayout.width==tailLayout.cols-1 and tailLayout.rows>0,'Retained geometry outside native frame')
    elseif lines[i]:match('^TAIL\t') then tailId,tailKey=lines[i]:match('^TAIL\t([^\t]+)\t([%d,]+)$');assert(tailId and tailKey,'Invalid retained dialogue checkpoint')
    elseif lines[i]:match('^EDITOR\t') then editorLine=lines[i]
    else
    local arg,raw,display=lines[i]:match('^NAME\t(%x%x)\t(%x+)\t(.*)$')
    assert(arg and #raw==8,'Invalid name checkpoint');names[arg]={source_raw=raw,display=display}
    end
   end
   cinema.reset()
   if cinematicLine then cinema.restore(cinematicLine) end
   OVERLAY_NAMES=names;O.active=nil;O.tail=nil;O.recover=false;O.hidden=hidden;adapters.reset()
   if editorLine then adapters.restore(editorLine) end
   if record then
    assert(identify()==record or prefixRecord()==record or record.native_span and spanCheckpointMatches(record) or word(0x7FDBDF)==record.index and sourceBufferMatches(record) or nativeComplete and tailSourceMatches(record,adapters.choicePair()),'Checkpoint source binding failed')
    begin(record,sourceLayout,savedHeader);assert(O.active,'Checkpoint has unresolved name')
    local page=assert(tonumber(lines[5]));assert(page>=1,'Invalid checkpoint page')
    local sameContent=savedContent==O.active.content
    local sameLayout=layoutWidth==O.active.layout.width and layoutRows==O.active.layout.rows and sameContent
    if not sameLayout then
     if lines[6]=='reading' then page=1 else page=math.min(page,#O.active.pages) end
     log('checkpoint-layout-restarted',{page=page})
    end
    assert(page<=#O.active.pages,'Checkpoint page outside message')
    assert(not nativeComplete or word(0x7FDBC7)==0,'Completed-source checkpoint is not natively complete')
    O.active.page=page;O.active.phase=lines[6];O.active.nativeComplete=nativeComplete
    if not sameContent then
     if record.native_span and (record.native_span.has_item or record.native_span.has_number) then O.active=nil;log('checkpoint-content-unresolved',{id=record.id})
     else O.active.page=1;O.active.phase='reading';O.active.nativeComplete=word(0x7FDBC7)==0;log('checkpoint-content-restarted',{id=record.id}) end
    end
   end
   if tailId then
    assert(not record and not editorLine,'Retained dialogue conflicts with active state')
    local found=nil;for _,r in ipairs(data.dialogue) do if r.id==tailId then found=r end end
    assert(found and tailSourceMatches(found,adapters.choicePair()),'Retained dialogue source binding failed')
    begin(found,tailLayout,savedHeader);assert(O.active,'Retained dialogue has unresolved name')
    if savedContent==O.active.content then
     O.tail={record=found,layout=O.active.layout,text=O.active.pages[#O.active.pages],windowKey=tailKey,content=O.active.content,header=O.active.header};O.active=nil
    else
     if found.native_span and (found.native_span.has_item or found.native_span.has_number) then O.active=nil;log('checkpoint-content-unresolved',{id=found.id})
     else O.active.nativeComplete=word(0x7FDBC7)==0;log('checkpoint-content-restarted',{id=found.id}) end
    end
   end
   O.release=true;O.prevA=true;O.prevX=true -- Require a fresh release after API state loads too.
   nativeUI.begin();draw();nativeUI.finish() -- Queue host drawing for the next decoded frame.
   log('paired-checkpoint-loaded',{page=O.active and O.active.page or 0})
  end
 end,emu.callbackType.exec,0,0xffffff,emu.cpuType.snes)
end
O.checkpoint=requestCheckpoint
local previousSave,previousLoad=false,false
emu.addEventCallback(function()
 local save,load=emu.isKeyPressed('F6'),emu.isKeyPressed('F7')
 if save and not previousSave then requestCheckpoint('save') end
 if load and not previousLoad then requestCheckpoint('load') end
 previousSave,previousLoad=save,load
end,emu.eventType.inputPolled)
