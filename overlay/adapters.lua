-- Native inventory/battle/choice and long-name editor adapters.
-- All hooks are for the fingerprinted original Japan ROM only.
return function(C)
 local O,word,byte,log=C.O,C.word,C.byte,C.log
 local M={editor=nil,nativeEditorFrame=-100,editorSeen=nil,previous={},itemDraws={},labelHits={}}
 local function field(arg)
  local b={};for i=0,3 do b[#b+1]=string.format('%02x',byte(0x7F4928+(arg-2)*4+i)) end
  return table.concat(b)
 end
 local function jsonString(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
   if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
   return string.format('\\u%04x',c:byte())
  end)..'"'
 end
 local function jsonValue(v)
  if type(v)=='string' then return jsonString(v) end
  if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
  assert(type(v)=='table','Unsupported profile value')
  local a={};for k,x in pairs(v) do a[#a+1]=jsonString(tostring(k))..':'..jsonValue(x) end
  table.sort(a);return '{'..table.concat(a,',')..'}'
 end
 local function persist()
  local p=assert(OVERLAY_PROFILE_PATH,'No profile path supplied')
  local profile=OVERLAY_PROFILE or {};profile.names=OVERLAY_NAMES
  local f=assert(io.open(p..'.tmp','wb'));f:write(jsonValue(profile)..'\n');f:close();assert(os.rename(p..'.tmp',p))
 end
 local unavailableKeys={}
 local function keyPressed(name)
  if unavailableKeys[name] then return false end
  local ok,held=pcall(emu.isKeyPressed,name)
  if not ok then unavailableKeys[name]=true;log('optional-key-unavailable',{key=name});return false end
  return held
 end
 local nativeDefaults={['8076bcbc']='MANA',['88e0bcbc']='YUZU'}
 local letters='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -\'!?.'
 -- Names are literal strings, so preview chunks preserve every space too.
 function M.namePreview(text,requested)
  local p={};for i=1,#text,18 do p[#p+1]=text:sub(i,i+17) end
  if #p==0 then p[1]='_' end
  return p,math.max(1,math.min(requested or #p,#p))
 end
 local function openEditor(arg)
  local alias=OVERLAY_NAMES[string.format('%02X',arg)]
  local raw=field(arg);local normalized=raw:gsub('..',function(b) return b=='00' and 'bc' or b end)
  local defaults=nativeDefaults
  -- Native editor pads with NUL before END; resolve the original name before aliases.
  local text=(alias and alias.source_raw==raw and alias.display) or defaults[normalized] or C.displayName(arg) or ''
  M.editor={arg=arg,text=text,cursor=1,phase='editing',raw=field(arg)}
  M.previous={};O.release=true;O.prevX=true;log('name-editor-open',{arg=arg,characters=#text})
 end
 function M.command(action,value)
  local e=assert(M.editor,'No active name editor');assert(e.phase=='editing')
  if action=='append' then
   assert(type(value)=='string' and value~='' and not value:find('[^ -~]'),'Name requires printable ASCII')
   e.text=e.text..value;e.preview=nil;e.error=nil
  elseif action=='backspace' then e.text=e.text:sub(1,-2);e.preview=nil;e.error=nil
  elseif action=='cancel' then M.editor=nil;O.release=true;log('name-editor-cancelled')
  elseif action=='save' then
   if e.text:match('^%s*$') then e.error='Please enter a name.';return end
   e.phase='committing';log('name-editor-confirm',{arg=e.arg,characters=#e.text})
  else error('Unknown name editor action') end
 end
 M.field=field
 -- C14866 is the native grid/control-row update, with the saved DBR still on stack.
 -- C14B1B is precisely the original END handler (PLB then validation/padding).
 emu.addMemoryCallback(function()
  M.nativeEditorFrame=O.frame
  local arg=word(0x7FDCC7)+2
  assert(arg>=2 and arg<=8,'Unexpected native name slot')
  if M.editorSeen~=arg then M.editorSeen=arg;openEditor(arg) end
  if M.editor and M.editor.phase=='committing' then
   assert(M.editor.arg==arg,'Name-editor slot changed before confirmation')
   local s=emu.getCpuState(emu.cpuType.snes);s['pc']=0x4B1B;emu.setCpuState(s,emu.cpuType.snes)
  end
 end,emu.callbackType.exec,0xC14866,0xC14866,emu.cpuType.snes)
 emu.addMemoryCallback(function()
  if M.editor and M.editor.phase=='committing' then
   local e=M.editor;local key=string.format('%02X',e.arg)
   OVERLAY_NAMES[key]={source_raw=field(e.arg),display=e.text};persist()
   log('name-editor-saved',{arg=e.arg,characters=#e.text,source_raw=field(e.arg)})
   M.editor=nil;O.release=true
  end
 end,emu.callbackType.exec,0xC14B4B,0xC14B4B,emu.cpuType.snes)
 function M.input(raw)
  local last=M.lastInput or {};M.lastInput=raw
  if M.viewer then
   if raw.a and not last.a then
    if M.viewer.page<#M.viewer.pages then M.viewer.page=M.viewer.page+1 else M.viewer=nil;O.release=true end
   end
   if raw.b and not last.b then M.viewer=nil;O.release=true end
   local mask={};for k in pairs(raw) do mask[k]=false end;emu.setInput(mask,0);return true
  end
  if M.context=='main-menu' and raw.y and not last.y then
   local name=C.displayName(2)
   if name then M.viewer={pages=C.pages(name,38,6),page=1};log('full-name-viewer-open') end
   emu.setInput({y=false},0);return true
  end
  local e=M.editor
  if not e then return false end
  local keys={};for k,v in pairs(raw) do keys[k]=v and not M.previous[k] end;M.previous=raw
  -- The keyboard is optional; controller editing always remains available.
  local keyboard={}
  for c in ('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'):gmatch('.') do keyboard[c]=not (OVERLAY_REPORT_KEYS and OVERLAY_REPORT_KEYS[c]) and keyPressed(c) end
  keyboard.Space=keyPressed('Space');keyboard.Backspace=keyPressed('Backspace');keyboard.Enter=keyPressed('Enter')
  local typing=false;for _,held in pairs(keyboard) do typing=typing or held end
  if M.editor and e.phase=='editing' then
   for c,held in pairs(keyboard) do
    if held and not (M.keyboard or {})[c] then
     if c=='Space' then M.command('append',' ')
     elseif c=='Backspace' then M.command('backspace')
     elseif c=='Enter' then M.command('save')
     else M.command('append',c) end
    end
   end
  end
  M.keyboard=keyboard
  if M.editor and e.phase=='editing' and not typing then
   if keys.l then e.preview=math.max(1,(e.preview or #M.namePreview(e.text))-1) end
   if keys.r then e.preview=math.min(#M.namePreview(e.text),(e.preview or #M.namePreview(e.text))+1) end
   if keys.left then e.cursor=((e.cursor-2)%#letters)+1 end
   if keys.right then e.cursor=(e.cursor%#letters)+1 end
   if keys.up then e.cursor=((e.cursor-1-12)%#letters)+1 end
   if keys.down then e.cursor=((e.cursor-1+12)%#letters)+1 end
   if keys.a then M.command('append',letters:sub(e.cursor,e.cursor)) end
   if keys.b then M.command('backspace') end
   if keys.select then M.command('cancel') end
   if keys.start then M.command('save') end
  end
  local mask={};for k in pairs(raw) do mask[k]=false end;emu.setInput(mask,0)
  return true
 end
 function M.drawEditor()
  local e=M.editor;if not e then return end
  local p,preview=M.namePreview(e.text,e.preview)
  C.nativeUI.nameEditor(p[preview],letters,e.cursor,string.format('%d/%d',preview,#p),e.error)
 end
 function M.drawViewer()
  if not M.viewer then return end
  emu.drawRectangle(8,24,240,160,0x00080828,true)
  emu.drawString(14,30,'FULL NAME',0x00B8C8FF,0x00080828)
  emu.drawString(14,48,M.viewer.pages[M.viewer.page],0x00FFFFFF,0x00080828)
  emu.drawString(14,164,'A: next  B: close  X: hide',0x00B8C8FF,0x00080828)
 end
 function M.discardInput(raw)
  M.previous=raw;M.lastInput=raw
  M.keyboard={}
  for c in ('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'):gmatch('.') do M.keyboard[c]=not (OVERLAY_REPORT_KEYS and OVERLAY_REPORT_KEYS[c]) and keyPressed(c) end
  for _,c in ipairs({'Space','Backspace','Enter'}) do M.keyboard[c]=not (OVERLAY_REPORT_KEYS and OVERLAY_REPORT_KEYS[c]) and keyPressed(c) end
 end
 function M.serialize()
  if not M.editor then return nil end
  local e=M.editor
  if e.phase~='editing' then return nil end
  return 'EDITOR\t'..e.arg..'\t'..e.raw..'\t'..e.cursor..'\t'..(e.preview or 0)..'\t'..e.text
 end
 function M.restore(line)
  local arg,raw,cursor,preview,text=line:match('^EDITOR\t(%d+)\t(%x+)\t(%d+)\t(%d+)\t(.*)$')
  arg=assert(tonumber(arg));cursor=assert(tonumber(cursor));preview=assert(tonumber(preview))
  assert(arg>=2 and arg<=8 and raw==field(arg),'Name-editor checkpoint source mismatch')
  assert(cursor>=1 and cursor<=#letters and not text:find('[^ -~]'),'Invalid name-editor checkpoint')
  M.editor={arg=arg,raw=raw,cursor=cursor,preview=preview>0 and preview or nil,text=text,phase='editing'}
  M.editorSeen=arg;M.nativeEditorFrame=O.frame;M.previous={};M.keyboard={}
 end
 function M.reset()
  M.editor=nil;M.viewer=nil;M.editorSeen=nil;M.lastInput={};M.previous={};M.keyboard={};M.itemDraws={};M.inventoryLayoutKey=nil;M.inventoryView=nil
 end
 -- Read original VRAM once per overlay frame; never change game tilemaps.
 local menuRows={}
 local function glyph(tile) return (tile&15)|((tile&0x1E0)>>1) end
 local function scan() return C.nativeUI.tilemap() end

 local function matches(w,row,col,tiles)
  if col+#tiles>32 then return false end
  local attr=w[row*32+col+1]&0xFC00
  for i,t in ipairs(tiles) do
   local v=w[row*32+col+i]
   if v&1023~=t or v&0xFC00~=attr or v&0xC000~=0 then return false end
  end
  return true
 end
 local wantedFirst={}
 for _,group in ipairs({C.data.menus,C.data.battle_labels or {}}) do
  for _,m in ipairs(group) do wantedFirst[m.tiles[1]]=true end
 end
 local indexedWords=nil;local positionsByTile={};local noPositions={}
 local function find(w,text,requiredRow,records)
  if indexedWords~=w then
   indexedWords=w;positionsByTile={}
   for i,v in ipairs(w) do
    local tile=v&1023
    if wantedFirst[tile] then
     positionsByTile[tile]=positionsByTile[tile] or {};table.insert(positionsByTile[tile],i-1)
    end
   end
  end
  for _,m in ipairs(records or C.data.menus) do
   if m.english==text then
    for _,position in ipairs(positionsByTile[m.tiles[1]] or noPositions) do
     local row=position//32;local col=position%32
     if (not requiredRow or row==requiredRow) and col<=31-#m.tiles and matches(w,row,col,m.tiles) then return {row=row,col=col,record=m} end
    end
   end
  end
 end
 local firstItems={};for _,item in ipairs(C.data.items) do
  if #item.tiles>=2 and item.text and item.text:match('%S') then
   local t=item.tiles[1];firstItems[t]=firstItems[t] or {};table.insert(firstItems[t],item)
  end
 end
 local byAddress={};for _,i in ipairs(C.data.items) do byAddress[tonumber(i.id,16)+0xC00000]=i end
 -- The generic original ROM-string renderer is used by inventory names.
 -- Alternate C19417 covers other item/ability list consumers.
 local function recordNativeItem()
  local s=emu.getState();if s['cpu.y']~=0 then return end
  local address=word(0x30)|(byte(0x32)<<16);local item=byAddress[address]
  if not item then return end
  for i,v in ipairs(item.raw) do if byte(address+i-1)~=v then return end end
  local key=item.id..':'..tostring(s['cpu.x'])
  if not M.itemDraws[key] then
   M.itemDraws[key]=true;log('native-item-source',{index=item.index,id=item.id,tile_offset=s['cpu.x']})
  end
 end
 emu.addMemoryCallback(recordNativeItem,emu.callbackType.exec,0xC0C185,0xC0C185,emu.cpuType.snes)
 emu.addMemoryCallback(recordNativeItem,emu.callbackType.exec,0xC19417,0xC19417,emu.cpuType.snes)
 function M.choicePair(w)
  w=w or scan();if not w then return nil end
  local yes,no=find(w,'YES'),find(w,'NO')
  if yes and no and no.row-yes.row==2 and yes.col==no.col and yes.col>=1 and yes.col+math.max(#yes.record.tiles,3)<=31 and (w[yes.row*32+yes.col+1]&0xFC00)==(w[no.row*32+no.col+1]&0xFC00) then return yes,no end
 end
 function M.drawChoice(yes,no)
  M.context='choice';C.nativeUI.choice(yes,no)
  local key=yes.row..':'..yes.col
  if not M.labelHits['choice:'..key] then
   M.labelHits['choice:'..key]=true;log('choice-overlay-open',{yes_row=yes.row,no_row=no.row,col=yes.col})
  end
 end
 -- Reflow the original two-column grid, preserving native row/column
 -- selection and every rendered quantity digit. No input is synthesized.
 local inventoryWrap={}
 function M.inventoryLayout(pairs,selected,capacity)
  capacity=capacity or 8
  local groups={}
  for _,pair in ipairs(pairs) do
   local group={source=pair,items={},height=1}
   for _,entry in ipairs(pair.items) do
    local text=entry.item.text;local lines=inventoryWrap[text]
    if not lines then
     local pages=C.pages(text,12,1000000)
     assert(#pages==1,'Inventory name wrapper lost a page')
     lines={};for line in (pages[1]..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
     inventoryWrap[text]=lines
    end
    local quantityLine=#lines-1
    if #lines[#lines]>8 then quantityLine=quantityLine+1 end
    group.height=math.max(group.height,quantityLine+1)
    group.items[#group.items+1]={entry=entry,lines=lines,quantityLine=quantityLine}
   end
   if group.height>capacity then return nil end
   groups[#groups+1]=group
  end
  local first=1
  if selected then
   local used=0;for i=1,selected do used=used+groups[i].height end
   while used>capacity do used=used-groups[first].height;first=first+1 end
  end
  local result={first=first,last=first-1,rows={},selected=selected};local used=0
  for i=first,#groups do
   local group=groups[i];if used+group.height>capacity then break end
   group.line=used;group.index=i;result.rows[#result.rows+1]=group
   used=used+group.height;result.last=i
  end
  return result
 end
 local function inventoryScrollMark(x,y,up,pal)
  local ink=C.nativeUI.color(pal,3);local shadow=C.nativeUI.color(pal,2);local points={}
  for row=0,2 do
   local half=up and row or 2-row
   for col=2-half,2+half do points[#points+1]={x+col,y+row} end
  end
  local batch={};local function add(x,y,color)batch[#batch+1]=x;batch[#batch+1]=y;batch[#batch+1]=color end
  for _,point in ipairs(points) do add(point[1]+1,point[2]+1,shadow) end
  for _,point in ipairs(points) do add(point[1],point[2],ink) end
  if emu.drawPixelBatch then emu.drawPixelBatch(batch)
  else for i=1,#batch,3 do emu.drawPixel(batch[i],batch[i+1],batch[i+2]) end end
 end
 local function drawFullInventory(pairs,w,top,pal)
  if #pairs==0 or pairs[1].row~=11 then return false end
  local allowed={};local selected=nil;local selectedColumn=nil
  for i,pair in ipairs(pairs) do
   if pair.row~=11+2*(i-1) then return false end
   for _,entry in ipairs(pair.items) do
    for r=entry.row,entry.row+1 do for col=entry.col-2,entry.col+10 do allowed[r*32+col]=true end end
    if glyph(w[entry.row*32+entry.col-1]&1023)==0xBD then selected=i;selectedColumn=entry.col end
   end
  end
  -- A child menu or unknown text keeps the native panel. Never paint over
  -- another window just because a few old inventory names remain visible.
  for row=11,26 do for col=2,29 do
   local g=glyph(w[row*32+col+1]&1023)
   if not allowed[row*32+col] and g~=0 and g~=0xBC then return false end
  end end
  local layout=M.inventoryLayout(pairs,selected,8)
  if not layout then return false end
  if not C.nativeUI.suppressSnapshot(11,2,28,16,w) then C.nativeUI.erase(16,88+top,224,128,pal) end
  local signature={}
  for _,group in ipairs(layout.rows) do
   local y=(11+group.line*2)*8+top
   for _,item in ipairs(group.items) do
    local entry=item.entry;local x=entry.col==4 and 32 or 144
    for n,line in ipairs(item.lines) do C.nativeUI.text(x,y+(n-1)*16,line,entry.pal) end
    local quantityY=y+item.quantityLine*16
    -- These six tiles are the actual colon and packed-decimal display,
    -- including padding, palette and shadow. Do not reparse as binary/hex.
    for dy=0,1 do for dx=0,2 do
     C.nativeUI.tile(w[(entry.row+dy)*32+entry.col+8+dx+1],(entry.col+8+dx)*8,quantityY+dy*8)
    end end
    if group.index==selected and entry.col==selectedColumn then
     C.nativeUI.tile(w[entry.row*32+entry.col-1],(entry.col-2)*8,y)
     C.nativeUI.tile(w[(entry.row+1)*32+entry.col-1],(entry.col-2)*8,y+8)
    end
    signature[#signature+1]=entry.item.id..':'..group.line..':'..entry.count
   end
  end
  if layout.first>1 then inventoryScrollMark(25,88+top,true,pal) end
  if layout.last<#pairs then inventoryScrollMark(25,208+top,false,pal) end
  local key=table.concat(signature,'|')..'@'..tostring(selected)..':'..tostring(selectedColumn)
  M.inventoryView={layout=layout,selectedColumn=selectedColumn}
  if M.inventoryLayoutKey~=key then
   M.inventoryLayoutKey=key
   log('inventory-full-name-layout',{first=layout.first,last=layout.last,selected=selected or 0,column=selectedColumn or 0,above=layout.first>1,below=layout.last<#pairs})
   for _,group in ipairs(layout.rows) do for _,item in ipairs(group.items) do
    local e=item.entry
    log('inventory-full-name-row',{id=e.item.id,index=e.item.index,text=e.item.text,count=e.count,source_row=e.row,source_col=e.col,draw_row=11+2*group.line,quantity_row=11+2*(group.line+item.quantityLine),wrapped_hex=(table.concat(item.lines,'\n'):gsub('.',function(c)return string.format('%02x',c:byte())end)),selected=group.index==selected and e.col==selectedColumn})
   end end
  end
  return true
 end
 function M.drawMenus()
  M.context=nil
  local w=scan();if not w then return end
  local top=emu.getDrawSurfaceSize(emu.drawSurface.consoleScreen).overscan.top
  -- Exact original stat glyphs together, only inside the native battle kernel.
  -- Gauges/numbers and controller handling remain native.
  local battleBank=word(0xD3);local phase=word(0xD1)
  if battleBank==0xC3 and phase>=0x0453 and phase<=0x0942 then
   for _,menu in ipairs(C.data.battle_menus or {}) do
    local valid=true
    for i,v in ipairs(menu.raw) do if byte(0x7F0000+menu.offset_in_block+i-1)~=v then valid=false end end
    for i,line in ipairs(menu.lines) do if not matches(w,menu.first_row+(i-1)*2,4,line.tiles) then valid=false end end
    if valid then
     M.context=menu.index==611 and 'battle-root' or 'battle-commands'
     C.nativeUI.menu(menu)
     if not M.labelHits[menu.id] then M.labelHits[menu.id]=true;log('battle-menu-overlay-open',{id=menu.id}) end
    end
   end
   local stats={};for _,text in ipairs({'ATTACK','DEFENSE','SPEED'}) do stats[#stats+1]=find(w,text,nil,C.data.battle_labels) or false end
   local valid=stats[1] and stats[2] and stats[3]
   if valid then
    local first=stats[1]
    for i,m in ipairs(stats) do if m.col~=first.col or m.row~=first.row+(i-1)*2 then valid=false end end
    valid=valid and first.col<=3 and first.row>=17 and first.row<=21
   end
   if valid then
    M.context='battle-stats'
    for _,m in ipairs(stats) do C.nativeUI.stat(m.row,m.col,m.record.english) end
    if not M.labelHits.battleStats then M.labelHits.battleStats=true;log('battle-stats-overlay-open',{col=stats[1].col,row=stats[1].row}) end
   end
  end
  local categories={'ITEMS','WEAPONS','CLOTHING','CHARMS','TREASURES'}
  local tabs={};for _,text in ipairs(categories) do tabs[#tabs+1]=find(w,text,7) or false end
  local inventory=true
  for _,m in ipairs(tabs) do if not m or m.row~=7 then inventory=false end end
  if inventory then
   M.context='inventory'
   if not M.labelHits.inventory then M.labelHits.inventory=true;log('inventory-overlay-open') end
   local selected=word(0x7FDCA1)
   local placements={{112,3},{184,3},{24,7},{104,7},{168,7}}
   local pal=(w[7*32+4]>>10)&7
   -- All five full labels fit in two existing native windows. No frame changes.
   if emu.setSnesTextMask then
    -- Remove only the original label ink and old selection arrow. Frame,
    -- window fill and unrelated Japanese remain in their native layers.
    local ready=true
    for _,m in ipairs(tabs) do if not C.nativeUI.suppress(m.row,m.col-1,#m.record.tiles+1,2) then ready=false end end
    if not ready then C.nativeUI.erase(12,56+top,232,16,pal) end
   else
    C.nativeUI.erase(56,24+top,184,16,pal)
    C.nativeUI.erase(12,56+top,232,16,pal)
   end
   for i,text in ipairs(categories) do
    local pos=placements[i];C.nativeUI.text(pos[1],pos[2]*8+top,text,pal)
   end
   if selected>=0 and selected<5 then
    local source=tabs[selected+1].col-1;local pos=placements[selected+1]
    C.nativeUI.tile(w[7*32+source+1],pos[1]-8,pos[2]*8+top)
    C.nativeUI.tile(w[8*32+source+1],pos[1]-8,(pos[2]+1)*8+top)
   end
   C.nativeUI.inventoryTitle(C.data.inventory_title.english)
   local pairs={};local invalid=false
   for row=11,25,2 do
    local pair={row=row,items={}}
    for _,col in ipairs({4,18}) do
     local tile=w[row*32+col+1]&1023;local g=glyph(tile)
     if g~=0 and g~=0xBC then
      local found=nil;local ambiguous=false
      for _,item in ipairs(firstItems[tile] or {}) do
       if matches(w,row,col,item.tiles) then
        if found and found.text~=item.text then ambiguous=true end
        found=item
       end
      end
      local count='';local validCount=true
      for n=col+9,col+10 do
       local digit=glyph(w[row*32+n+1]&1023)
       if digit>=1 and digit<=10 then count=count..tostring(digit-1)
       elseif digit~=0xBC and digit~=0 then validCount=false end
      end
      if found and not ambiguous and validCount and count~='' and glyph(w[row*32+col+9]&1023)==0xBE then
       pair.items[#pair.items+1]={item=found,count=count,row=row,col=col,pal=(w[row*32+col+1]>>10)&7}
      else invalid=true end
     end
    end
    if #pair.items>0 then pairs[#pairs+1]=pair end
   end
   M.inventoryView=nil
   if invalid or not drawFullInventory(pairs,w,top,pal) then M.inventoryLayoutKey=nil end
  end
  local labels={'ITEMS','EQUIPMENT','STATS','ADMIRATION'}
  local main={};for _,text in ipairs(labels) do main[#main+1]=find(w,text) or false end
  local valid=true
  for i,m in ipairs(main) do if not m or m.col~=25 or m.row~=1+2*i then valid=false end end
  if valid then
   M.context='main-menu'
   emu.drawRectangle(160,16+top,88,72,0x0008084A,true)
   local selected=word(0x7FDC83)
   for i,text in ipairs(labels) do
    emu.drawString(166,24+top+(i-1)*16,(i-1)==selected and '> '..text or '  '..text,0x00FFFFFF,0x0008084A)
   end
   local name=C.displayName(2)
   if name then
    local hp=''
    for col=13,19 do
     local g=glyph(w[5*32+col+1]&1023)
     if g>=1 and g<=10 then hp=hp..tostring(g-1) end
    end
    if hp~='' then
     emu.drawRectangle(74,24+top,83,48,0x0008084A,true)
     local display=#name<=42 and table.concat(C.pages(name,13,4),'\n') or 'Y: VIEW FULL\nNAME'
     emu.drawString(78,24+top,display,0x00FFFFFF,0x0008084A)
     emu.drawString(78,64+top,'HP: '..hp,0x00FFFFFF,0x0008084A)
    end
   end
   if not M.labelHits.main then M.labelHits.main=true;log('main-menu-overlay-open',{selected=selected}) end
  end
  local yes,no=M.choicePair(w);if yes then M.drawChoice(yes,no) end
 end

 return M
end
