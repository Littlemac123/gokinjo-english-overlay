#!/usr/bin/env python3
"""Self-contained release launcher. No project tools or translation sources required."""
import argparse, fcntl, hashlib, json, os, shutil, subprocess, sys, tempfile, uuid, zipfile
from pathlib import Path

APP = Path(__file__).resolve().parents[2]
GAME = APP / 'usr/share/gokinjo'
ROM_SHA = '4e790991a1dc4a9df209f68895412597b4069b42971683c3a3092a160556f305'

def lua(value):
    if value is None: return 'nil'
    if isinstance(value, bool): return str(value).lower()
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, str):
        escapes = {'"': '\\"', '\\': '\\\\', '\n': '\\n', '\r': '\\r', '\t': '\\t', '\b': '\\b', '\f': '\\f'}
        return '"' + ''.join(escapes.get(c, '\\x%02x' % ord(c) if ord(c) < 32 else c) for c in value) + '"'
    if isinstance(value, list): return '{' + ','.join(lua(v) for v in value) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'

def atomic(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.new-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f: f.write(data)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)

def rom_bytes(path):
    if path.suffix.lower() == '.zip':
        with zipfile.ZipFile(path) as z:
            candidates = [i for i in z.infolist() if Path(i.filename).suffix.lower() in ('.sfc', '.smc') and i.file_size <= 10_000_000]
            for info in candidates:
                data = z.read(info)
                for raw in (data, data[512:]):
                    if hashlib.sha256(raw).hexdigest() == ROM_SHA: return raw
    elif path.stat().st_size <= 10_000_000:
        data = path.read_bytes()
        for raw in (data, data[512:]):
            if hashlib.sha256(raw).hexdigest() == ROM_SHA: return raw
    raise ValueError('This is not the matching original Gokinjo Boukentai (Japan) ROM.\nChoose the original .sfc, .smc, or .zip, without any translation patch.')

def pick_rom():
    title = 'Choose your original Gokinjo Boukentai (Japan) ROM or ZIP'
    if shutil.which('zenity'):
        cmd = ['zenity', '--file-selection', '--title=' + title, '--file-filter=SNES ROM | *.sfc *.smc *.zip *.SFC *.SMC *.ZIP', '--file-filter=All files | *']
    elif shutil.which('kdialog'):
        cmd = ['kdialog', '--title', title, '--getopenfilename', str(Path.home()), '*.sfc *.smc *.zip|SNES ROM or ZIP']
    else:
        raise RuntimeError('A file picker (zenity or kdialog) is required for first launch.\nAlternatively, run this AppImage with --rom /path/to/game.zip once.')
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0: raise SystemExit(0)
    return Path(result.stdout.rstrip('\n'))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom', type=Path, help='Import your matching original ROM once (.sfc, .smc or .zip)')
    p.add_argument('--data-dir', type=Path, help='Optional separate save/profile folder')
    p.add_argument('--prepare-only', action='store_true', help='Validate and prepare without opening Mesen')
    p.add_argument('--readme', action='store_true')
    a = p.parse_args()
    if a.readme:
        text = (GAME / 'README.txt').read_text()
        if shutil.which('zenity'): return subprocess.call(['zenity', '--text-info', '--title=Gokinjo English opening', '--filename=' + str(GAME / 'README.txt'), '--width=750', '--height=600'])
        print(text); return 0
    if os.uname().machine != 'x86_64': raise RuntimeError('This build requires Linux x86-64.')
    manifest = json.loads((GAME / 'manifest.json').read_text())
    for rel, digest in manifest['files'].items():
        if hashlib.sha256((APP / rel).read_bytes()).hexdigest() != digest:
            raise RuntimeError('A release file failed its integrity check: ' + rel)
    data = (a.data_dir or Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'gokinjo-english-opening').expanduser().resolve()
    data.mkdir(parents=True, exist_ok=True)
    os.chmod(data, 0o700)
    lock = (data / '.running').open('a')
    try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: raise RuntimeError('This save profile is already open. Close its game window before launching again.')
    rom = data / 'rom/original.sfc'
    if a.rom or not rom.exists():
        raw = rom_bytes((a.rom or pick_rom()).expanduser().resolve())
        atomic(rom, raw)
    if hashlib.sha256(rom.read_bytes()).hexdigest() != ROM_SHA: raise RuntimeError('The imported ROM changed. Import the original again with --rom.')
    profile = data / 'profile.json'
    if not profile.exists(): atomic(profile, b'{"names":{}}\n')
    names = json.loads(profile.read_text())
    if not isinstance(names.get('names'), dict): raise RuntimeError('Invalid name profile. Your existing file has been preserved.')
    config = data / 'config/MesenCE'
    config.mkdir(parents=True, exist_ok=True)
    settings = config / 'settings.json'
    reporter_enabled = (GAME / 'report_capture.lua').exists()
    if not settings.exists():
        # FirstRun initializes upstream keyboard/gamepad defaults on GUI launch.
        blank = [{'Shortcut': 'LoadStateSlot' + str(i), 'KeyCombination': {'Key1': 0}, 'KeyCombination2': {'Key1': 0}} for i in (6, 7)]
        seed = {'Version': '2.2.1', 'ConfigUpgrade': 5, 'DefaultKeyMappings': 'Xbox, ArrowKeys',
                'Debug': {'ScriptWindow': {'AllowIoOsAccess': True, 'AllowNetworkAccess': False, 'ScriptTimeout': 10}},
                'Snes': {'Port1': json.loads((APP / 'usr/bin/report-controls.json').read_text())['controller'] if reporter_enabled else {'Type': 'SnesController'}, 'Overscan': {'Top': 0, 'Bottom': 0, 'Left': 0, 'Right': 0}},
                'Preferences': {'ShortcutKeys': blank}}
        if not reporter_enabled: seed['ConfigUpgrade'] = 1
        atomic(settings, (json.dumps(seed, indent=2) + '\n').encode())
    if reporter_enabled:
        from report_notes import migrate_controls
        migrate_controls(settings, data)
    core = APP / 'usr/lib/gokinjo/MesenCore.so'
    installed = config / 'MesenCore.so'
    if not installed.exists() or hashlib.sha256(installed.read_bytes()).hexdigest() != manifest['files']['usr/lib/gokinjo/MesenCore.so']:
        atomic(installed, core.read_bytes(), 0o444)
    session = data / 'sessions' / uuid.uuid4().hex
    session.mkdir(parents=True)
    for name in ('catalog.lua', 'native_ui.lua', 'adapters.lua', 'cinematic.lua'):
        shutil.copyfile(GAME / name, session / name)
    globals_ = {'OVERLAY_CINEMATIC_PATH': str(session / 'cinematic.lua'), 'OVERLAY_NATIVE_UI_PATH': str(session / 'native_ui.lua'),
                'OVERLAY_ADAPTER_PATH': str(session / 'adapters.lua'), 'OVERLAY_CATALOG_PATH': str(session / 'catalog.lua'),
                'OVERLAY_ROOT': str(GAME), 'OVERLAY_CATALOG_HASH': manifest['files']['usr/share/gokinjo/catalog.lua'],
                'OVERLAY_NAMES': names['names'], 'OVERLAY_PROFILE': names, 'OVERLAY_PROFILE_PATH': str(profile),
                'OVERLAY_CHECKPOINT_STEM': str(data / 'checkpoint')}
    reporter = GAME / 'report_capture.lua'
    extra = ''
    if reporter.exists():
        reports = data / 'logs'
        reports.mkdir(exist_ok=True); os.chmod(reports, 0o700)
        globals_['OVERLAY_REPORT_DIR'] = str(reports)
        globals_['OVERLAY_REPORT_KEYS'] = {'S': True, 'D': True}
        globals_['OVERLAY_REPORT_BUILD'] = {'release_id': manifest['release_id'], 'catalog_sha256': manifest['files']['usr/share/gokinjo/catalog.lua'],
                                          'core_sha256': manifest['files']['usr/lib/gokinjo/MesenCore.so'],
                                          'reporter_sha256': manifest['files']['usr/share/gokinjo/report_capture.lua']}
        extra = reporter.read_text() + '\n'
    script = session / 'session.lua'
    script.write_text(''.join(k + '=' + lua(v) + '\n' for k, v in globals_.items()) + (GAME / 'overlay.lua').read_text() + '\n' + extra)
    cmd = [str(APP / 'usr/bin/Mesen'), str(rom), str(script)]
    plan = {'argv': cmd, 'data_dir': str(data), 'config': str(config.parent), 'profile_path': str(profile), 'rom_sha256': ROM_SHA,
            'core_sha256': manifest['files']['usr/lib/gokinjo/MesenCore.so'], 'release_id': manifest['release_id']}
    atomic(data / 'launch.json', (json.dumps(plan, indent=2) + '\n').encode())
    if a.prepare_only: print(json.dumps(plan, indent=2)); return 0
    env = dict(os.environ, XDG_CONFIG_HOME=str(config.parent))
    # No developer/test arguments are exposed in the normal launcher.
    notes = None
    if reporter.exists():
        from report_notes import ReportNotes
        notes = ReportNotes(data / 'logs'); notes.start()
    try:
        with (data / 'emulator.log').open('w') as log:
            status = subprocess.call(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
    finally:
        if notes: notes.close()
    if hashlib.sha256(installed.read_bytes()).hexdigest() != plan['core_sha256']:
        raise RuntimeError('Mesen replaced the required renderer. Your saves are preserved; see emulator.log.')
    if status: raise RuntimeError('Mesen could not start or exited with an error. See ' + str(data / 'emulator.log'))
    # Keep the most recent bootstrap for diagnosis; active instances use the lock.
    for old in (data / 'sessions').iterdir():
        if old != session and old.is_dir(): shutil.rmtree(old)
    return 0

if __name__ == '__main__':
    try: sys.exit(main())
    except Exception as exc:
        message = str(exc)
        print('Gokinjo English: ' + message, file=sys.stderr)
        if shutil.which('zenity') and (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
            subprocess.run(['zenity', '--error', '--title=Gokinjo English opening', '--text=' + message])
        elif shutil.which('kdialog') and (os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY')):
            subprocess.run(['kdialog', '--error', message])
        sys.exit(1)
