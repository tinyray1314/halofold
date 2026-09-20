from pathlib import Path
import subprocess,plistlib,shutil,os,json
work=Path('/tmp/halofold-assistant-check')
b=work/'Halofold Assistant Check.app'
(b/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(work/'.build/debug/CodexIsland',b/'Contents/MacOS/AssistantCheck')
(b/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.halofold.assistant-check','CFBundleName':'Halofold Assistant Check','CFBundleExecutable':'AssistantCheck','CFBundlePackageType':'APPL','NSHighResolutionCapable':True}))
data=work/'data'
data.mkdir(exist_ok=True)
env=dict(os.environ,HALOFOLD_SUPPORT_DIR=str(data))
with (work/'runtime.log').open('w') as log:
 p=subprocess.Popen([str(b/'Contents/MacOS/AssistantCheck'),'--ignore-codex-foreground','-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN'],env=env,stdout=log,stderr=log)
(work/'pid').write_text(str(p.pid))
print(p.pid)
