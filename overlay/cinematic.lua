-- Isolated wake-up adapter. Native delays, music, glyph effects and event code
-- run unchanged. Only exact original command boundaries can hold the text engine.
return function(ctx)
 local O,U,word,byte,log,pages=ctx.O,ctx.U,ctx.word,ctx.byte,ctx.log,ctx.pages
 local records=ctx.records or {};local byIndex={};local plans={}
 for _,r in ipairs(records) do byIndex[r.index]=r;plans[r.index]=r.stages end
 local C={active=nil,entryStack=nil,prevA=true,release=true}
 local function matches(r)
  if not r or word(0x7FDBDF)~=r.index then return false end
  local selector=word(0x7FDC5B)
  if r.source_base==0x7E0000 then if selector~=2 then return false end
  elseif selector~=5 and selector~=0 then return false end
  for i,v in ipairs(r.raw) do if byte((r.source_base or 0x7F0000)+r.offset+i-1)~=v then return false end end
  return true
 end
 local function identify()
  local r=byIndex[word(0x7FDBDF)]
  if matches(r) and word(0x7FDBE7)==0 and (word(0x30)|(byte(0x32)<<16))==(r.source_base or 0x7F0000)+r.offset then return r end
 end
 local function resolveText(text)
  local resolved=text:gsub('{name:(%x%x)}',function(arg)
   return assert(ctx.resolveName and ctx.resolveName(tonumber(arg,16)), 'Unbound cinematic name '..arg)
  end)
  return resolved
 end
 local function resolvedPlan(r,index)
  local original=plans[r.index][index];local plan={}
  for k,v in pairs(original) do plan[k]=v end
  plan.text=resolveText(original.text)
  if original.cues then
   plan.cues={};for i,cue in ipairs(original.cues) do plan.cues[i]={cue[1],resolveText(cue[2])} end
  end
  if index==1 and r.native_header then
   local header=assert(ctx.headerRecord and ctx.headerRecord(r.native_header),'Compiled cinematic header is absent')
   assert(header.id==r.native_header,'Cinematic source header differs')
   local prefix=resolveText(header.text)..'\n'
   plan.text=prefix..plan.text
   if plan.cues then for _,cue in ipairs(plan.cues) do cue[2]=prefix..cue[2] end end
  end
  return plan
 end
 local function stage(r,cursor)
  local index=1
  for i,p in ipairs(plans[r.index]) do if cursor>=p.first then index=i end end
  return index,resolvedPlan(r,index)
 end
 local function begin(r,cursor)
  if r.native_header then
   local actual=ctx.resolveHeader and ctx.resolveHeader(r)
   if not actual or actual.id~=r.native_header then return nil end
  end
  local layout=U.dialogueLayout(false);if not layout then return nil end
  local index,plan=stage(r,cursor)
  C.active={record=r,layout=layout,stage=index,plan=plan,phase='playing',approved={},page=1,text='',cursor=cursor}
  C.prevA=true;C.release=true;log('cinematic-open',{id=r.id,cursor=cursor})
  return C.active
 end
 local function bindStage(a,cursor)
  local index,plan=stage(a.record,cursor)
  if index~=a.stage then a.stage=index;a.plan=plan;a.page=1;log('cinematic-stage',{id=a.record.id,stage=index}) end
  local text=plan.text
  if plan.cues then
   text=''
   for _,cue in ipairs(plan.cues) do if cursor>=cue[1] then text=cue[2] end end
  end
  a.text=text;a.cursor=cursor
 end
 function C.dispatch()
  local r=identify();if not r then return false end
  local cursor=word(0x7FDBDD);if cursor<(r.native_start_cursor or 0) then return false end;local a=C.active
  if not a or a.record~=r then a=begin(r,cursor) end
  if not a then return false end
  bindStage(a,cursor)
  if cursor==a.plan.last and not a.approved[cursor] then
   a.text=a.plan.text;a.pages=pages(a.text,a.layout.width,a.layout.rows);a.page=1;a.phase='reading';C.release=true;C.prevA=true
   local s=emu.getCpuState(emu.cpuType.snes)
   assert(C.entryStack and s.sp==C.entryStack-1,'Cinematic boundary stack differs from original text routine')
   -- Matching PLB/RTL balances the original routine's one remaining DBR byte.
   s.pc=0x9B78;emu.setCpuState(s,emu.cpuType.snes)
   log('cinematic-gate',{id=r.id,cursor=cursor,stage=a.stage,pages=#a.pages,sp=s.sp})
  end
  return true
 end
 function C.hold()
  C.entryStack=emu.getCpuState(emu.cpuType.snes).sp
  local a=C.active
  if a and a.phase=='reading' and matches(a.record) then
   local s=emu.getCpuState(emu.cpuType.snes);s.pc=0x99D1;emu.setCpuState(s,emu.cpuType.snes);return true
  end
  return false
 end
 function C.input(raw)
  local a=C.active;if not a then return false end
  if not matches(a.record) then C.active=nil;return false end
  local press=raw.a==true;local edge=press and not C.prevA;C.prevA=press
  if C.release then
   local held=false;for _,name in ipairs(ctx.buttons) do held=held or raw[name]==true end
   if not held then C.release=false;C.prevA=false end
  elseif not O.hidden and a.phase=='reading' and edge then
   if a.page<#a.pages then a.page=a.page+1;log('cinematic-page',{id=a.record.id,page=a.page,stage=a.stage})
   else a.approved[a.cursor]=true;a.phase='playing';log('cinematic-read',{id=a.record.id,cursor=a.cursor,stage=a.stage}) end
  end
  local mask={};for _,name in ipairs(ctx.buttons) do mask[name]=false end;emu.setInput(mask,0);return true
 end
 function C.wait(value)
  local a=C.active
  if a and a.phase=='playing' and matches(a.record) then
   local cursor=word(0x7FDBDD)
   if a.approved[cursor-1] and a.record.raw[cursor]==0xFC then return 0x80 end
  end
  return value
 end
 function C.close(value)
  local a=C.active
  if a and a.phase=='playing' and matches(a.record) and a.approved[plans[a.record.index][#plans[a.record.index]].last] then return 0x80 end
  return value
 end

 local function hex(text) return (text:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
 local function content(r)
  local texts={};for index in ipairs(plans[r.index]) do texts[#texts+1]=resolvedPlan(r,index).text end
  return hex(table.concat(texts,'\f'))
 end
 function C.serialize()
  local a=C.active;if not a then return nil end
  local approved={};for cursor in pairs(a.approved) do approved[#approved+1]=cursor end;table.sort(approved)
  return table.concat({'CINEMA',a.record.index,word(0x7FDBDD),a.stage,a.page,a.phase,content(a.record),table.concat(approved,','),a.cursor},'\t')
 end
 local function parse(line)
  local values={};for value in (line..'\t'):gmatch('(.-)\t') do values[#values+1]=value end
  if #values~=9 or values[1]~='CINEMA' then return nil end
  local r=byIndex[tonumber(values[2])];if not r or content(r)~=values[7] then return nil end
  local cursor,stage,page=tonumber(values[3]),tonumber(values[4]),tonumber(values[5]);local phase=values[6];local boundCursor=tonumber(values[9])
  if not cursor or cursor<0 or cursor>#r.raw-1 or not stage or not plans[r.index][stage] or not page or page<1 or (phase~='reading' and phase~='playing') or not boundCursor then return nil end
  local approved={};for number in values[8]:gmatch('%d+') do
   local n=tonumber(number);local found=false
   for _,plan in ipairs(plans[r.index]) do if plan.last==n and n<=cursor then found=true end end
   if not found then return nil end;approved[n]=true
  end
  local plan=plans[r.index][stage]
  if phase=='reading' and (cursor~=plan.last or boundCursor~=cursor or approved[cursor]) then return nil end
  return {record=r,cursor=cursor,stage=stage,page=page,phase=phase,approved=approved,boundCursor=boundCursor}
 end
 function C.validate(line) return parse(line)~=nil end
 function C.restore(line)
  local saved=assert(parse(line),'Invalid cinematic checkpoint content/plan')
  assert(matches(saved.record) and word(0x7FDBDD)==saved.cursor,'Cinematic native source/cursor mismatch')
  local a=assert(begin(saved.record,saved.boundCursor));a.stage=saved.stage;a.plan=resolvedPlan(a.record,a.stage);a.page=saved.page;a.phase=saved.phase;a.approved=saved.approved;a.cursor=saved.boundCursor;a.text=a.plan.text
  a.pages=pages(a.text,a.layout.width,a.layout.rows);assert(a.page<=#a.pages,'Cinematic saved page outside reading plan')
  C.release=true;C.prevA=true;log('cinematic-checkpoint-restored',{id=a.record.id,page=a.page,stage=a.stage})
 end
 function C.discard(raw) C.prevA=raw.a==true end
 function C.present() return C.active~=nil end
 function C.draw()
  local a=C.active;if not a then return end
  if not matches(a.record) then C.active=nil;return end
  local text=a.phase=='reading' and a.pages[a.page] or (pages(a.text,a.layout.width,a.layout.rows)[1] or '')
  U.dialogue(a.layout,text,a.phase=='reading',O.frame)
 end
 function C.reset() C.active=nil;C.prevA=true;C.release=true end
 return C
end
