from pathlib import Path
import subprocess, os, time, json, shutil, plistlib, sys
out=Path(__file__).resolve().parents[1]
work=Path('/tmp/halofold-ui-upgrade-capture')
bundle=work/'Halofold UI Atlas.app'
(bundle/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(work/'.build/debug/CodexIsland',bundle/'Contents/MacOS/HalofoldUIAtlas')
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.halofold.ui-atlas','CFBundleName':'Halofold UI Atlas','CFBundleExecutable':'HalofoldUIAtlas','CFBundlePackageType':'APPL','CFBundleDevelopmentRegion':'zh_CN','NSHighResolutionCapable':True}))
scenarios=sys.argv[1:] or ['activity-main','activity-completed','activity-paused','activity-empty','activity-warning','notes-main','notes-new','notes-many','schedule-empty','schedule-main','schedule-new','schedule-new-filled','schedule-edit','schedule-awaiting','schedule-overdue','schedule-running','schedule-completed','schedule-routine','schedule-routine-new','schedule-routine-daily','schedule-routine-edit','settings-features','settings-display','settings-voice','settings-general','settings-permission','collapsed-compact','collapsed-relaxed']
records=[]
for name in scenarios:
 data=work/'data'/name
 if data.exists(): shutil.rmtree(data)
 data.mkdir(parents=True)
 ready=data/'ready.json'
 env=dict(os.environ,HALOFOLD_SUPPORT_DIR=str(data),ATLAS_SCENARIO=name,ATLAS_READY=str(ready),CODEX_ISLAND_DEMO='1')
 with (data/'runtime.log').open('w') as log:
  proc=subprocess.Popen([str(bundle/'Contents/MacOS/HalofoldUIAtlas'),'-AppleLanguages','(zh-Hans)','-AppleLocale','zh_CN'],env=env,stdout=log,stderr=log)
  try:
   for _ in range(120):
    if ready.exists(): break
    if proc.poll() is not None: raise RuntimeError((data/'runtime.log').read_text())
    time.sleep(.1)
   info=json.loads(ready.read_text())
   target=out/'screenshots'/f'{name}.png'
   for attempt in range(3):
    result=subprocess.run(['python3','/tmp/halofold-screenshot-skill/take_screenshot.py','--window-id',str(info['windowID']),'--path',str(target)],text=True)
    if result.returncode == 0: break
    time.sleep(1)
   result.check_returncode()
   records.append(dict(info,file=str(target.relative_to(out)),status='captured'))
   print(name,'captured',flush=True)
   existing=out/'capture-log.json'
   old=json.loads(existing.read_text()) if existing.exists() else []
   by_id={r['scenario']:r for r in old+records}
   existing.write_text(json.dumps(list(by_id.values()),ensure_ascii=False,indent=2))
  finally:
   proc.terminate()
   proc.wait(timeout=5)
existing=out/'capture-log.json'
old=json.loads(existing.read_text()) if existing.exists() else []
by_id={r['scenario']:r for r in old+records}
existing.write_text(json.dumps(list(by_id.values()),ensure_ascii=False,indent=2))
