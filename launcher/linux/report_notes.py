"""Collect optional user bug descriptions beside explicit D report captures."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile,threading

def atomic(path,data):
    fd,name=tempfile.mkstemp(prefix='.note-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f:f.write(data)
        os.replace(name,path)
    finally:Path(name).unlink(missing_ok=True)

def describe(request, runner=subprocess.run):
    stem=Path(str(request).rsplit('.',1)[0]);record_path=stem.with_suffix('.json')
    # Names contain no dots; every attachment has the same complete stem.
    record=json.loads(record_path.read_text())
    note=stem.with_suffix('.txt');seed=Path(str(stem)+'.note-input')
    atomic(seed,b'')
    try:
        if shutil.which('zenity'):
            command=['zenity','--text-info','--editable','--title=Describe game bug','--filename='+str(seed),'--width=640','--height=400','--ok-label=Save report','--cancel-label=Skip description']
        elif shutil.which('kdialog'):
            command=['kdialog','--title','Describe game bug','--textinputbox','Describe what happened and what you expected. Your screenshot and savestate are already captured.','','640','400']
        else:
            atomic(note,b'[Description unavailable: zenity or kdialog is required.]\n');status='unavailable';command=None
        if command:
            result=runner(command,capture_output=True,text=True,encoding='utf-8',errors='replace')
            if result.returncode==0:
                atomic(note,result.stdout.encode('utf-8'));status='saved' if result.stdout.strip() else 'empty'
            else:
                atomic(note,b'[Description skipped. Screenshot and savestate retained.]\n');status='skipped'
        # Preserve any resolution/evidence written while the prompt was open.
        record=json.loads(record_path.read_text());record['note_status']=status
        atomic(record_path,(json.dumps(record,ensure_ascii=False,indent=2)+'\n').encode())
        request.unlink(missing_ok=True)
    finally:seed.unlink(missing_ok=True)

class ReportNotes:
    def __init__(self,directory):
        self.directory=Path(directory);self.stopped=threading.Event()
        self.thread=threading.Thread(target=self.run,name='local-bug-notes',daemon=True)
    def start(self):self.thread.start()
    def close(self):
        self.stopped.set()
        # A prompt already opened by D remains available after game close.
        self.thread.join()
    def run(self):
        while not self.stopped.is_set():
            for request in sorted(self.directory.glob('*.bug-request')):
                if self.stopped.is_set():break
                try:describe(request)
                except Exception as error:
                    # Keep request and capture for a later retry, without stopping emulation.
                    print('Bug note could not be saved: '+str(error),flush=True)
                    self.stopped.wait(2)
                    break
            self.stopped.wait(.5)


def migrate_controls(settings,data):
    """Reserve S/D once, preserving all gamepad mappings and a settings backup."""
    marker=data/'report-controls-v1.json'
    if marker.exists():return
    original=settings.read_bytes();config=json.loads(original.decode('utf-8-sig'))
    controller=config.setdefault('Snes',{}).setdefault('Port1',{'Type':'SnesController'})
    mappings=[controller.setdefault('Mapping'+str(n),{}) for n in range(1,5)]
    keyboard=next((m for m in mappings if any(isinstance(v,int) and 0<v<4096 for v in m.values())),mappings[-1])
    for mapping in mappings:
        for button,value in list(mapping.items()):
            if isinstance(value,int) and value in (6,18,47,62):mapping[button]=0
    keyboard.update(A=18,Start=6)
    backup=data/'settings-before-report-controls.json'
    if not backup.exists():atomic(backup,original)
    atomic(settings,(json.dumps(config,indent=2)+'\n').encode())
    atomic(marker,(json.dumps({'revision':1,'simple_report':'S','bug_report':'D','next_page':'Space','start':'Enter','settings_backup':backup.name})+'\n').encode())
