from pathlib import Path
import shutil,subprocess,json,concurrent.futures,os
import argparse
p=argparse.ArgumentParser(description='Cross-compile modified Windows MesenCore.dll using llvm-mingw.')
p.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[1]/'emulator')
p.add_argument('--toolchain',type=Path,required=True)
p.add_argument('--output',type=Path,default=Path('build/windows/MesenCore.dll'))
p.add_argument('--jobs',type=int,default=3)
a=p.parse_args();src=a.source.resolve();out=a.output.resolve();out.parent.mkdir(parents=True,exist_ok=True)
tool=a.toolchain.resolve()/'bin/x86_64-w64-mingw32-clang++';cc=tool.with_name('x86_64-w64-mingw32-clang');obj=out.parent/'objects';obj.mkdir(exist_ok=True)
files=[]
for folder in ['Core','Utilities','InteropDLL','Windows']:
 files+=list((src/folder).rglob('*.cpp'))
import xml.etree.ElementTree as ET
lua_project=ET.parse(src/'Lua/Lua.vcxproj')
lua_files=[src/'Lua'/e.attrib['Include']for e in lua_project.iter()if e.tag.endswith('ClCompile')and'Include'in e.attrib]
files+=list((src/'Utilities').rglob('*.c'))+lua_files+list((src/'SevenZip').rglob('*.c'))
flags=['-O2','-DNDEBUG','-DWIN32','-D_WINDOWS','-D_USRDLL','-DINTEROPDLL_EXPORTS','-DUNICODE','-D_UNICODE','-fms-extensions','-Wno-ignored-attributes','-Wno-pragma-pack','-I'+str(src/'windows-sdk'),'-I'+str(src),'-I'+str(src/'Core'),'-I'+str(src/'Utilities'),'-I'+str(src/'Windows'),'-I'+str(src/'InteropDLL')]
def build(p):
 out=obj/(str(p.relative_to(src)).replace('/','_')+'.o')
 if out.exists()and out.stat().st_mtime>=p.stat().st_mtime:return out
 cmd=[str(cc if p.suffix=='.c'else tool)]+flags+([]if p.suffix=='.c'else['-std=c++17'])+['-c',str(p),'-o',str(out)]
 x=subprocess.run(cmd,capture_output=True,text=True)
 if x.returncode:raise RuntimeError(str(p.relative_to(src))+'\n'+x.stderr[-6500:])
 return out
print('Compiling',len(files),'native sources',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs)as pool:objects=list(pool.map(build,files))
cmd=[str(tool),'-shared','-O2','-o',str(out)]+list(map(str,objects))+['-ldinput8','-lxinput9_1_0','-ld3d11','-ld3dcompiler','-ldxguid','-lwinmm','-lcomctl32','-lkernel32','-luser32','-lgdi32','-lwinspool','-lcomdlg32','-ladvapi32','-lshell32','-lole32','-loleaut32','-luuid','-lws2_32','-ldsound']
x=subprocess.run(cmd,capture_output=True,text=True);(out.parent/'windows-link.log').write_text(x.stdout+x.stderr);assert x.returncode==0,x.stderr[-6500:];print('Built',out,flush=True)
