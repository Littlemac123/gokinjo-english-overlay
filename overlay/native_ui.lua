-- Draw with the original game's live BG3 font, palettes and border tiles.
-- This changes only the host draw surface, never the native tilemap or palette.
return function()
 local U={};local state,chr,base,top,colors,masks;local previousMask={};local windowMaskSupported=false;local planeRows={};local frameScope=false;local frameWords=nil
 -- Core masks are discarded on native state load/reset. Invalidate the host
 -- readiness cache too, so the first rendered frame receives a transition cover.
 local function invalidateMask() previousMask={};windowMaskSupported=false end
 U.resetMasks=invalidateMask
 emu.addEventCallback(invalidateMask,emu.eventType.stateLoaded)
 emu.addEventCallback(invalidateMask,emu.eventType.reset)
 local function read(a) return emu.read(a%65536,emu.memType.snesVideoRam,false) end
 local function word(a) return read(a)|(read(a+1)<<8) end
 function U.begin()
  state=emu.getState();chr=state['ppu.layers[2].chrAddress']*2;base=state['ppu.layers[2].tilemapAddress']*2
  top=emu.getDrawSurfaceSize(emu.drawSurface.consoleScreen).overscan.top;colors={};masks={};planeRows={};frameScope=true;frameWords=nil
 end
 function U.frameState() return frameScope and state or emu.getState() end
 function U.tilemap()
  if frameScope and frameWords then return frameWords end
  local s=U.frameState();local b=s['ppu.layers[2].tilemapAddress']
  if not b or s['ppu.layers[2].hscroll']~=0 or s['ppu.layers[2].vscroll']~=0 then return nil end
  local words={};for i=0,895 do words[i+1]=emu.read16((b*2+2*i)%65536,emu.memType.snesVideoRam,false) end
  if frameScope then frameWords=words end
  return words
 end
 function U.finish()
  frameScope=false;frameWords=nil
  if emu.setSnesTextMask then
   windowMaskSupported=emu.setSnesTextMask(masks,true)==2;previousMask={}
   for _,cell in ipairs(masks) do previousMask[cell[1]]=cell[2] end
  end
 end
 function U.suppress(row,col,width,height)
  if not emu.setSnesTextMask then return false end
  local ready=true
  for r=row,row+height-1 do for c=col,col+width-1 do
   local a=(base+2*(r*32+c))%65536;local w=word(a);masks[#masks+1]={a,w}
   if previousMask[a]~=w then ready=false end
  end end
  -- The PPU consumes masks on the following frame. Cover the transition
  -- frame only, preventing a flash of Japanese beneath newly drawn English.
  return ready and windowMaskSupported
 end
 -- Inventory already obtained this exact BG3 snapshot in the same frame.
 -- Reuse its words instead of crossing the Lua/native boundary twice for each
 -- masked cell. Other renderers retain the original direct-read path above.
 function U.suppressSnapshot(row,col,width,height,words)
  if not emu.setSnesTextMask then return false end
  assert(frameScope and words==frameWords,'Text mask requires the current frame tilemap')
  local ready=true
  for r=row,row+height-1 do for c=col,col+width-1 do
   local a=(base+2*(r*32+c))%65536;local w=assert(words[r*32+c+1])
   masks[#masks+1]={a,w}
   if previousMask[a]~=w then ready=false end
  end end
  return ready and windowMaskSupported
 end
 function U.color(pal,index)
  local key=pal*4+index
  if not colors[key] then
   local a=key*2;local v=emu.read(a,emu.memType.snesCgRam,false)|(emu.read(a+1,emu.memType.snesCgRam,false)<<8)
   local function channel(shift) local q=(v>>shift)&31;return (q<<3)|(q>>2) end
   colors[key]=(channel(0)<<16)|(channel(5)<<8)|channel(10)
  end
  return colors[key]
 end
 function U.at(row,col) return word(base+2*(row*32+col)) end
 local function pixel(tile,x,y)
  local a=chr+tile*16+y*2
  local row=planeRows[a]
  if not row then row=read(a)|(read(a+1)<<8);planeRows[a]=row end
  return ((row>>(7-x))&1)|((row>>(14-x))&2)
 end
 function U.tile(w,x,y)
  if emu.drawSnesTiles then emu.drawSnesTiles({w,x,y-1},chr,0);return end
  y=y-1 -- Mesen drawPixel console-surface origin: verified by exact native tile echo.
  local tile=w&1023;local pal=(w>>10)&7
  for py=0,7 do for px=0,7 do
   local value=pixel(tile,w&0x4000~=0 and 7-px or px,w&0x8000~=0 and 7-py or py)
   if value~=0 then emu.drawPixel(x+px,y+py,U.color(pal,value)) end
  end end
 end
 local glyphs={['\x0E']=0xB9,['\x08']=0xB5,['\x03']=0xAE,['\x04']=0xAF,['\x05']=0xB0,['\x06']=0xA1,['\x07']=0xAC,['\x01']=0xB7,['\x02']=0xA2,[' ']=0xBC,['.']=0x93,[',']=0x98,['!']=0x96,['?']=0x95,[':']=0xBE,['-']=0xBB,['(']=0x99,[')']=0x9A,['"']=0x9B,['/']=0xAC,['&']=0x9F,['%']=0x9E}
 for i=0,9 do glyphs[tostring(i)]=i+1 end
 for i=0,25 do glyphs[string.char(65+i)]=11+i end
 function U.text(x,y,text,pal)
  y=y-1
  local origin=x;local glyphRun={}
  local function flush() if #glyphRun>0 then emu.drawSnesGlyphs(glyphRun,chr,pal);glyphRun={} end end
  for c in text:upper():gmatch('.') do
   if c=='\n' then x=origin;y=y+16
   elseif c=="'" then
    flush()
    local color=U.color(pal,3);emu.drawPixel(x+3,y+3,color);emu.drawPixel(x+3,y+4,color);emu.drawPixel(x+2,y+5,color);x=x+8
   elseif c=='/' then
    flush()
    for py=3,11 do
     local px=6-math.floor((py-3)*6/8)
     emu.drawPixel(x+px+1,y+py+1,U.color(pal,2))
     emu.drawPixel(x+px,y+py,U.color(pal,3))
     if px<6 then emu.drawPixel(x+px+1,y+py,U.color(pal,3)) end
    end
    x=x+8
   elseif c=='_' then
    flush()
    for px=0,6 do emu.drawPixel(x+px,y+11,U.color(pal,3)) end;x=x+8
   else
    local g=glyphs[c]
    if not g then
     -- Full printable-ASCII aliases remain valid. Preserve rare symbols until
     -- their final native-style glyphs are supplied, rather than dropping them.
     flush();emu.drawString(x+1,y+5,c,U.color(pal,3),0xFF000000)
    else
    if emu.drawSnesGlyphs then glyphRun[#glyphRun+1]=g;glyphRun[#glyphRun+1]=x;glyphRun[#glyphRun+1]=y
    else
    local tile=((g<<1)&0x1e0)|(g&15)
    for py=0,15 do for px=0,7 do
     local value=pixel(tile+(py>=8 and 16 or 0),px,py%8)
     if value>=2 then emu.drawPixel(x+px,y+py,U.color(pal,value)) end
    end end
    end
    end
    x=x+8
   end
  end
  flush()
 end
 -- Added lowercase glyphs use the native 8x16 cell and live ink/shadow colors.
 -- These are host font extensions only; original ROM/VRAM glyphs are untouched.
 local lower={
  a='00003C063E66663E00',b='60607C666666667C00',c='00003C666060663C00',
  d='06063E666666663E00',e='00003C667E60663C00',f='1C30307C3030303000',
  g='00003E66663E06663C',h='60607C666666666600',i='181800381818183C00',
  j='06060006060606663C',k='6060666C786C666600',l='381818181818183C00',
  m='00006C7E7E6A6A6A00',n='00007C666666666600',o='00003C666666663C00',
  p='00007C66667C606060',q='00003E66663E060606',r='00006C766060606000',
  s='00003E603C06067C00',t='30307C303030361C00',u='000066666666663E00',
  v='0000666666663C1800',w='000066666A6A7E3400',x='0000663C183C666600',
  y='00006666663E06663C',z='00007E060C18307E00'
 }
 local lowerPoints={}
 for c,bitmap in pairs(lower) do
  local points={};local py=0
  for pair in bitmap:gmatch('..') do
   py=py+1;local row=tonumber(pair,16)
   for px=0,7 do if row&(1<<(7-px))~=0 then points[#points+1]={px,py+1} end end
  end
  lowerPoints[c]=points
 end
 function U.nameText(x,y,text,pal)
  for c in text:gmatch('.') do
   local points=lowerPoints[c]
   if points then
    if emu.drawPixelBatch then
     local batch={};local function add(px,py,color) batch[#batch+1]=px;batch[#batch+1]=py;batch[#batch+1]=color end
     for _,p in ipairs(points) do add(x+p[1]+1,y+p[2]+1,U.color(pal,2)) end
     for _,p in ipairs(points) do add(x+p[1],y+p[2],U.color(pal,3)) end
     emu.drawPixelBatch(batch)
    else
     for _,p in ipairs(points) do emu.drawPixel(x+p[1]+1,y+p[2]+1,U.color(pal,2)) end
     for _,p in ipairs(points) do emu.drawPixel(x+p[1],y+p[2],U.color(pal,3)) end
    end
   else U.text(x,y,c,pal) end
   x=x+8
  end
 end
 -- Preserve the original choice box and arrow. Only exact source labels are
 -- suppressed; selection and A/B handling remain entirely in the game.
 function U.choice(yes,no)
  for _,label in ipairs({yes,no}) do
   local pal=(U.at(label.row,label.col)>>10)&7
   local text=label.record.english
   if text=='YES' and label.record.source_raw:sub(-2)=='96' then text=text..'!' end
   local width=math.max(#label.record.tiles,#text)
   if not U.suppress(label.row,label.col,width,2) then
    U.erase(label.col*8,label.row*8+top,width*8,16,pal)
   end
   U.text(label.col*8,label.row*8+top,text,pal)
  end
 end
 function U.nameEditor(preview,letters,cursor,status,message)
  local pal=(U.at(12,3)>>10)&7
  -- Expand the actual golden name field: original left cap stays fixed,
  -- original right cap moves to x240. The portrait is never overpainted.
  local size=emu.getScreenSize();assert(size.width==256 and size.height==239,'Unsupported name-editor screen')
  if emu.drawScreenRegions then
   -- Copy the live native frame regions in C++, avoiding a full-screen Lua
   -- table transfer and thousands of individual geometry draw commands.
   local crop=7
   emu.drawRectangle(16,176+top,224,32,U.color(pal,1),true)
   emu.drawScreenRegions({
    {80,15+crop,8,32,80,15+top,8,32},
    {88,15+crop,1,32,88,15+top,152,32},
    {136,15+crop,8,32,240,15+top,8,32},
    {8,120+crop,8,1,8,176+top,8,32},
    {240,120+crop,8,1,240,176+top,8,32},
    {8,176+crop,240,7,8,208+top,240,7}
   })
  else
  local buffer=emu.getScreenBuffer();local crop=7
  for y=15,46 do for x=80,247 do
   local sx=x<88 and x or x>=240 and 136+x-240 or 88
   emu.drawPixel(x,y+top,buffer[(y+crop)*256+sx+1]&0xFFFFFF)
  end end
  -- The original grid ends at y182. Add two native rows for the complete
  -- Latin grid and controls; relocate its exact bottom corners/edge by32px.
  for y=176,214 do for x=8,247 do
   local color
   if y>=208 then color=buffer[((y-32)+crop)*256+x+1]&0xFFFFFF
   elseif x<16 or x>=240 then color=buffer[(120+crop)*256+x+1]&0xFFFFFF
   else color=U.color(pal,1) end
   emu.drawPixel(x,y+top,color)
  end end
  end
  U.nameText(96,24+top,preview,pal)
  -- Keep the stepped native window, its background and all border pixels.
  -- Cover only the transition frame when the PPU mask is not yet installed.
  if not U.suppress(8,11,19,2) then emu.drawRectangle(88,63+top,151,15,U.color(pal,1),true) end
  if not U.suppress(12,2,28,10) then emu.drawRectangle(16,95+top,223,79,U.color(pal,1),true) end
  U.text(88,64+top,'A:ADD B:DELETE',pal)
  for i=1,#letters do
   local col=(i-1)%12;local row=math.floor((i-1)/12)
   local x=24+col*16;local y=96+row*16+top
   local c=letters:sub(i,i);if c==' ' then c='_' end
   U.nameText(x,y,c,pal)
   if i==cursor then
    U.tile((pal<<10)|0x16D,x-8,y);U.tile((pal<<10)|0x17D,x-8,y+8)
   end
  end
  local paging='L/R '..status
  U.text(152,176+top,#paging<=11 and paging or 'L/R:PAGE',pal)
  U.text(16,192+top,message or 'START:SAVE SELECT:CANCEL',pal)
 end
 function U.erase(x,y,width,height,pal)
  emu.drawRectangle(x,y+1,width-1,height-1,U.color(pal,1),true)
 end
 function U.menu(menu)
  local first=menu.first_row;local last=first+(#menu.lines-1)*2
  local upper,lower=first-1,last+2;local maxlen=0
  for _,line in ipairs(menu.lines) do maxlen=math.max(maxlen,#line.english) end
  local right=math.max(9,math.ceil((32+maxlen*8+8)/8));local pal=(U.at(first,4)>>10)&7
  U.erase(16,(upper+1)*8+top,(right-1)*8,(lower-upper-1)*8,pal)
  -- Remove the inside halves of the old right corners when widening.
  -- Their ink would otherwise survive transparent horizontal-edge pixels.
  if right>9 then U.erase(72,upper*8+top+4,8,4,pal);U.erase(72,lower*8+top,8,4,pal) end
  -- Reuse exact original corners, horizontal/vertical edges and cursor column.
  for row=upper,lower do
   for col=1,right do
    if row==upper or row==lower then
     local source=col==1 and 1 or col==right and 9 or 3
     U.tile(U.at(row,source),col*8,row*8+top)
    elseif col==1 or col==right then U.tile(U.at(row,col==1 and 1 or 9),col*8,row*8+top)
    elseif col==2 then U.tile(U.at(row,2),col*8,row*8+top) end
   end
  end
  for i,line in ipairs(menu.lines) do U.text(32,(first+(i-1)*2)*8+top,line.english,pal) end
 end
 function U.dialogueLayout(caption)
  local function memoryWord(a) return emu.read(a,emu.memType.snesMemory,false)|(emu.read(a+1,emu.memType.snesMemory,false)<<8) end
  local left,upper,cols,height=memoryWord(0x7FDBCB),memoryWord(0x7FDBCD),memoryWord(0x7FDBCF),memoryWord(0x7FDBD1)
  if left<0 or upper<0 or cols<8 or height<4 or left+cols+1>31 or upper+height+1>27 then return nil end
  local skip=caption and 2 or 0
  return {left=left,upper=upper,cols=cols,height=height,width=cols-1,rows=math.floor((height-skip)/2),bodyRow=upper+1+skip,bodyHeight=height-skip}
 end
 -- During an original choice, DBCB..DBD1 describe the smaller child box.
 -- A stock checkpoint has no host geometry, so locate the surviving native
 -- parent frame by all four corners. Only a unique largest dialogue fits.
 function U.findDialogueLayout(caption)
  local best=nil;local area=0;local tied=false
  for upper=0,21 do for left=0,22 do
   if U.at(upper,left)&0xC3FF==0x0144 then
    for right=left+9,31 do
     if U.at(upper,right)&0xC3FF==0x4144 then
      for bottom=upper+5,27 do
       if U.at(bottom,left)&0xC3FF==0x8144 and U.at(bottom,right)&0xC3FF==0xC144 then
        local cols,height=right-left-1,bottom-upper-1;local size=cols*height
        if size>area then
         local skip=caption and 2 or 0
         best={left=left,upper=upper,cols=cols,height=height,width=cols-1,rows=math.floor((height-skip)/2),bodyRow=upper+1+skip,bodyHeight=height-skip};area=size;tied=false
        elseif size==area then tied=true end
       end
      end
     end
    end
   end
  end end
  return not tied and best or nil
 end
 -- A completed message can remain in the native window after DBC7 goes idle.
 -- Retain English only while that exact source and frame still exist.
 function U.dialogueWindowKey(layout,choice)
  local current=U.dialogueLayout()
  if state['ppu.layers[2].hscroll']~=0 or state['ppu.layers[2].vscroll']~=0 then return nil end
  if not choice then
   if not current then return nil end
   for _,k in ipairs({'left','upper','cols','height'}) do if current[k]~=layout[k] then return nil end end
  end
  local right=layout.left+layout.cols+1;local bottom=layout.upper+layout.height+1
  if U.at(layout.upper,layout.left)&0xC3FF~=0x0144 or U.at(layout.upper,right)&0xC3FF~=0x4144 or U.at(bottom,layout.left)&0xC3FF~=0x8144 or U.at(bottom,right)&0xC3FF~=0xC144 then return nil end
  local cells={base,chr}
  for col=layout.left,right do cells[#cells+1]=U.at(layout.upper,col);cells[#cells+1]=U.at(bottom,col) end
  for row=layout.upper+1,bottom-1 do cells[#cells+1]=U.at(row,layout.left);cells[#cells+1]=U.at(row,right) end
  return table.concat(cells,',')
 end
 function U.dialogue(layout,text,reading,frame)
  local x=(layout.left+1)*8;local y=layout.bodyRow*8+top
  local pal=(U.at(layout.upper+1,layout.left+1)>>10)&7
  -- Leave the actual native frame, portrait and speaker caption untouched.
  if not U.suppress(layout.bodyRow,layout.left+1,layout.cols,layout.bodyHeight) then U.erase(x,y,layout.cols*8,layout.bodyHeight*8,pal) end
  U.text(x,y,text,pal)
  if reading and frame%40<20 then
   -- Exact continuation tile from the original FC animation table C0AB02.
   U.tile((pal<<10)|0x1FF,(layout.left+layout.cols)*8,(layout.upper+layout.height)*8+top)
  end
 end
 function U.inventoryTitle(title)
  -- This frame lives outside BG3. Copy the original composited game pixels,
  -- including its palette/shadow/corners, and extend only its horizontal edge.
  local size=emu.getScreenSize();if size.width~=256 or size.height~=239 then return false end
  local crop=7
  local pal=(U.at(2,2)>>10)&7
  U.erase(16,16+top,72,16,pal)
  if emu.drawScreenRegions then
   emu.drawScreenRegions({
    {8,8+crop,8,31,8,8+top,8,31},
    {40,8+crop,8,31,88,8+top,8,31},
    {24,8+crop,1,8,16,8+top,72,8},
    {24,32+crop,1,7,16,32+top,72,7}
   })
   U.text(16,16+top,title,pal)
   return true
  end
  local buffer=emu.getScreenBuffer()
  for y=8,38 do for x=8,95 do
   if x<16 or x>=88 or y<16 or y>=32 then
    local sx=x<16 and x or x>=88 and 40+x-88 or 24
    local color=buffer[(y+crop)*256+sx+1]&0xFFFFFF
    emu.drawPixel(x,y+top,color)
   end
  end end
  U.text(16,16+top,title,pal)
  return true
 end
 function U.stat(row,col,text)
  local pal=(U.at(row,col)>>10)&7;if not U.suppress(row,col,7,2) then U.erase(col*8,row*8+top,56,16,pal) end;U.text(col*8,row*8+top,text,pal)
 end
 return U
end
