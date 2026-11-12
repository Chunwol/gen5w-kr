"""Build host and freestanding Android API19 ARM structural patchers."""
import argparse,os,pathlib,subprocess,shutil
ROOT=pathlib.Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--ndk',default=os.environ.get('ANDROID_NDK_HOME') or str(pathlib.Path.home()/'AppData/Local/Android/Sdk/ndk/27.2.12479018'));p.add_argument('--host-only',action='store_true');a=p.parse_args()
 out=ROOT/'.build/portable';out.mkdir(parents=True,exist_ok=True)
 common=['-std=c99','-O2','-Wall','-Wextra','-Werror','tools/portable/main.c','tools/portable/dex_patch.c','tools/portable/supervision.c']
 subprocess.run([shutil.which('gcc') or 'cc',*common,'-o',str((out/('dex-patch-host.exe' if os.name=='nt' else 'dex-patch-host')).relative_to(ROOT))],cwd=ROOT,check=True)
 if not a.host_only:
  host='windows-x86_64' if os.name=='nt' else 'linux-x86_64';cc=pathlib.Path(a.ndk)/'toolchains/llvm/prebuilt'/host/'bin'/('clang.exe' if os.name=='nt' else 'clang')
  subprocess.run([str(cc),'--target=armv7a-linux-androideabi19',*common,'-fno-builtin','-fno-stack-protector','-fno-unwind-tables','-fno-asynchronous-unwind-tables','-fno-pie','-nostdlib','-static','-Wl,-e,_start','-Wl,--build-id=none','tools/portable/stat.S','tools/portable/runtime.c','tools/audio/runtime.c','tools/audio/syscalls.S','-o',str((out/'dex-patch').relative_to(ROOT))],cwd=ROOT,check=True)
 print('Built portable patchers in',out)
if __name__=='__main__':main()
