"""Windows x64 tester launcher. SPDX-License-Identifier: GPL-3.0-or-later"""
import argparse,hashlib,json,os,shutil,subprocess,sys,tempfile,threading,time,uuid,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
ROM_SHA='4e790991a1dc4a9df209f68895412597b4069b42971683c3a3092a160556f305'
def digest(p):
    with p.open('rb')as f:return hashlib.file_digest(f,'sha256').hexdigest()
def lua(v):
    if isinstance(v,bool):return str(v).lower()
    if isinstance(v,(float,int)):return str(v)
    if isinstance(v,str):return '"'+''.join({'\\':'\\\\','"':'\\"','\n':'\\n','\r':'\\r','\t':'\\t'}.get(c,'\\x%02x'%ord(c)if ord(c)<32 else c)for c in v)+'"'
    return '{'+','.join('['+lua(k)+']='+lua(x)for k,x in v.items())+'}'
def atomic(p,body):
    p.parent.mkdir(parents=True,exist_ok=True)
    fd,n=tempfile.mkstemp(dir=p.parent,prefix='.new-')
    try:
        with os.fdopen(fd,'wb')as f:f.write(body)
        os.replace(n,p)
    finally:Path(n).unlink(missing_ok=True)
def rom_bytes(p):
    if p.suffix.lower()=='.zip':
        with zipfile.ZipFile(p)as z:
            candidates=[i for i in z.infolist()if Path(i.filename).suffix.lower()in('.sfc','.smc')and i.file_size<=10000000]
            for info in candidates:
                d=z.read(info)
                for raw in(d,d[512:]):
                    if hashlib.sha256(raw).hexdigest()==ROM_SHA:return raw
    elif p.stat().st_size<=10000000:
        d=p.read_bytes()
        for raw in(d,d[512:]):
            if hashlib.sha256(raw).hexdigest()==ROM_SHA:return raw
    raise ValueError('Choose the matching original Japanese ROM, not a patched ROM.')
def pick_rom():
    command="[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();Add-Type -AssemblyName System.Windows.Forms;$d=New-Object System.Windows.Forms.OpenFileDialog;$d.Title='Choose original Gokinjo Boukentai Japan ROM or ZIP';$d.Filter='SNES ROM or ZIP|*.sfc;*.smc;*.zip|All files|*.*';if($d.ShowDialog() -eq 'OK'){[Console]::Write($d.FileName)}"
    p=subprocess.run(['powershell.exe','-NoProfile','-STA','-Command',command],capture_output=True,text=True,encoding='utf-8')
    if p.returncode:raise RuntimeError('ROM picker failed. You can also drag your ROM onto Start-English.bat.')
    if not p.stdout.strip():raise SystemExit(0)
    return Path(p.stdout.strip())
def note_worker(logs,stopped):
    while not stopped.wait(.5):
        for request in logs.glob('*.bug-request'):
            stem=Path(str(request).rsplit('.',1)[0]);note=stem.with_suffix('.txt')
            try:
                p=subprocess.run(['powershell.exe','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',str(ROOT/'describe_bug.ps1'),str(note)])
                record=stem.with_suffix('.json');d=json.loads(record.read_text());d['note_status']='saved'if p.returncode==0 and note.exists()else'skipped';atomic(record,(json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode());request.unlink(missing_ok=True)
            except Exception as e:print('Bug note unavailable:',e,flush=True);stopped.wait(2)
def main():
    p=argparse.ArgumentParser();p.add_argument('game',nargs='?',type=Path);p.add_argument('--rom',type=Path);p.add_argument('--data-dir',type=Path);p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
    manifest=json.loads((ROOT/'manifest.json').read_text())
    for n,h in manifest['files'].items():
        if digest(ROOT/n)!=h:raise RuntimeError('Package integrity check failed: '+n)
    data=(a.data_dir or Path(os.environ['LOCALAPPDATA'])/'GokinjoEnglishTest').resolve();data.mkdir(parents=True,exist_ok=True)
    import msvcrt
    lock=(data/'.running').open('a+b');lock.seek(0)
    if lock.read(1)==b'':lock.write(b'0');lock.flush()
    lock.seek(0)
    try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    except OSError:raise RuntimeError('This testing save profile is already open.')
    rom=data/'rom/original.sfc'
    if a.rom or a.game or not rom.exists():atomic(rom,rom_bytes((a.rom or a.game or pick_rom()).resolve()))
    if digest(rom)!=ROM_SHA:raise RuntimeError('Imported ROM changed;import the original again.')
    profile=data/'profile.json'
    if not profile.exists():atomic(profile,b'{"names":{}}\n')
    names=json.loads(profile.read_text())
    if not isinstance(names.get('names'),dict):raise ValueError('Name profile is invalid;file preserved.')
    emudir=data/'emulator';emudir.mkdir(exist_ok=True);settings=emudir/'settings.json'
    if not settings.exists():
        seed={'Version':'2.2.1','ConfigUpgrade':5,'DefaultKeyMappings':'Xbox, ArrowKeys','Debug':{'ScriptWindow':{'AllowIoOsAccess':True,'AllowNetworkAccess':False,'ScriptTimeout':10}},'Snes':{'Port1':json.loads((ROOT/'report-controls.json').read_text())['controller'],'Overscan':{'Top':0,'Bottom':0,'Left':0,'Right':0}},'Preferences':{'ShortcutKeys':[{'Shortcut':'LoadStateSlot'+str(i),'KeyCombination':{'Key1':0},'KeyCombination2':{'Key1':0}}for i in[6,7]]}}
        atomic(settings,(json.dumps(seed,indent=2)+'\n').encode())
    for source in(ROOT/'emulator').iterdir():
        if not source.is_file():continue
        target=emudir/source.name
        if not target.exists()or digest(target)!=digest(source):
            if target.exists():os.chmod(target,0o666)
            atomic(target,source.read_bytes())
        if source.name=='MesenCore.dll':os.chmod(target,0o444)
    logs=data/'logs';logs.mkdir(exist_ok=True);session=data/'sessions'/uuid.uuid4().hex;session.mkdir(parents=True)
    for n in['catalog.lua','native_ui.lua','adapters.lua','cinematic.lua']:shutil.copy2(ROOT/'overlay'/n,session/n)
    globals_={'OVERLAY_ROOT':str(ROOT/'overlay'),'OVERLAY_CINEMATIC_PATH':str(session/'cinematic.lua'),'OVERLAY_NATIVE_UI_PATH':str(session/'native_ui.lua'),'OVERLAY_ADAPTER_PATH':str(session/'adapters.lua'),'OVERLAY_CATALOG_PATH':str(session/'catalog.lua'),'OVERLAY_CATALOG_HASH':manifest['files']['overlay/catalog.lua'],'OVERLAY_PROFILE_PATH':str(profile),'OVERLAY_PROFILE':names,'OVERLAY_NAMES':names['names'],'OVERLAY_CHECKPOINT_STEM':str(data/'checkpoint'),'OVERLAY_REPORT_DIR':str(logs),'OVERLAY_REPORT_KEYS':{'S':True,'D':True},'OVERLAY_REPORT_BUILD':{'release_id':manifest['release_id'],'catalog_sha256':manifest['files']['overlay/catalog.lua'],'core_sha256':manifest['files']['emulator/MesenCore.dll'],'reporter_sha256':manifest['files']['overlay/report_capture.lua']}}
    script=session/'session.lua';script.write_text(''.join(k+'='+lua(v)+'\n'for k,v in globals_.items())+(ROOT/'overlay/overlay.lua').read_text()+'\n'+(ROOT/'overlay/report_capture.lua').read_text(),encoding='utf-8')
    cmd=[str(emudir/'Mesen.exe'),str(rom),str(script)];plan={'argv':cmd,'data_dir':str(data),'core_sha256':digest(emudir/'MesenCore.dll'),'release_id':manifest['release_id']};atomic(data/'launch.json',(json.dumps(plan,indent=2)+'\n').encode())
    if a.prepare_only:print(json.dumps(plan,indent=2));return
    stopped=threading.Event();thread=threading.Thread(target=note_worker,args=(logs,stopped),daemon=True);thread.start()
    try:
        with(data/'emulator.log').open('w')as log:status=subprocess.call(cmd,cwd=emudir,stdout=log,stderr=subprocess.STDOUT)
    finally:stopped.set()
    if digest(emudir/'MesenCore.dll')!=manifest['files']['emulator/MesenCore.dll']:raise RuntimeError('Required core changed;see emulator.log. Saves preserved.')
    if status:raise RuntimeError('Mesen exited with an error;see '+str(data/'emulator.log'))
if __name__=='__main__':
    try:main()
    except Exception as e:print('Gokinjo English tester:',e,file=sys.stderr);sys.exit(1)
