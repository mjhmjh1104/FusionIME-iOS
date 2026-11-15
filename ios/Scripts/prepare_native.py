#!/usr/bin/env python3
"""Fetch pinned sources, verify archives, and apply the small Apple C ABI patch."""
from pathlib import Path
import hashlib,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
native=ROOT/'Native'
manifest=json.loads((ROOT/'Scripts/native-sources.json').read_text())
for name,item in manifest.items():
    target=native/'Sources'/name
    if target.exists(): continue
    archives=native/'Archives';archives.mkdir(parents=True,exist_ok=True)
    archive=archives/item['archive']
    if not archive.exists():
        subprocess.run(['curl','--fail','--location','--retry','3',item['url'],'-o',str(archive)],check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']:
        raise SystemExit('Source checksum mismatch: '+name)
    target.mkdir(parents=True)
    subprocess.run(['tar','-xf',str(archive),'--strip-components=1','-C',str(target)],check=True)

mozc=native/'Sources/mozc/src'
for name in ['FusionMozc.h','FusionMozc.cc']:
    shutil.copyfile(native/'Bridge'/name,mozc/'ios'/name)
build=mozc/'ios/BUILD.bazel'
marker='# FusionIME C ABI'
build.write_text(build.read_text().split(marker)[0]+'\n'+marker+'\n'+(native/'Bridge/mozc.BUILD').read_text())
engine=mozc/'ios/ios_engine.cc'
original='key_event->set_key_code(Util::Utf8ToCodepoint(character));'
patched='if (character.size() == 1) { '+original+' } else { key_event->set_key_string(character); }'
text=engine.read_text()
if patched not in text:
    if original not in text: raise SystemExit('Mozc SendKey patch no longer applies')
    engine.write_text(text.replace(original,patched))
build=mozc/'base/BUILD.bazel'
text=build.read_text()
if 'ios = ["--target_platform=iOS"]' not in text:
    build.write_text(text.replace('android = ["--target_platform=Android"],','android = ["--target_platform=Android"],\n               ios = ["--target_platform=iOS"],'))
for module,header in [('CMozc',native/'Bridge/FusionMozc.h'),('CChewing',native/'Sources/libchewing-0.12.0/capi/include/chewing.h')]:
    headers=native/'Headers'/module/module;headers.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(header,headers/header.name)
    (headers/'module.modulemap').write_text(f'module {module} {{ header "{header.name}" export * }}\n')
print('Pinned Mozc and Chewing sources prepared.')
