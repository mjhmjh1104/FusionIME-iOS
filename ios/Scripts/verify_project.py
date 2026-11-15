#!/usr/bin/env python3
import hashlib,json,plistlib,sqlite3,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
project=ROOT/'FusionIME.xcodeproj/project.pbxproj'
raw=subprocess.check_output(['plutil','-convert','json','-o','-',str(project)])
data=json.loads(raw);objects=data['objects']
assert objects[data['rootObject']]['isa']=='PBXProject'
for obj in objects.values():
    if obj['isa']=='PBXFileReference' and obj.get('sourceTree')=='<group>':
        assert (ROOT/obj['path']).exists(),obj['path']
targets=[o for o in objects.values() if o['isa']=='PBXNativeTarget']
assert len(targets)==3
for target in targets:
    resources=next(objects[p] for p in target['buildPhases'] if objects[p]['isa']=='PBXResourcesBuildPhase')
    paths=[objects[objects[b]['fileRef']]['path'] for b in resources['files']]
    assert ('Resources/lexicon.sqlite' in paths)==(target['name']=='FusionKeyboard')
    if target['name']!='FusionKeyboardTests':
        assert 'Resources/PrivacyInfo.xcprivacy' in paths
        assert 'Resources/Localizable.xcstrings' in paths
    assert ('Resources/Native' in paths)==(target['name']=='FusionKeyboard')
ext=plistlib.loads((ROOT/'Keyboard/Info.plist').read_bytes())['NSExtension']
assert ext['NSExtensionPointIdentifier']=='com.apple.keyboard-service'
assert ext['NSExtensionAttributes']['IsASCIICapable']
manifest=json.loads((ROOT/'Resources/manifest.json').read_text())
path=ROOT/'Resources/lexicon.sqlite'
assert hashlib.sha256(path.read_bytes()).hexdigest()==manifest['sha256']
with sqlite3.connect('file:'+str(path)+'?mode=ro',uri=True) as db:
    assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
    assert dict(db.execute('SELECT mode,count(*) FROM entries GROUP BY mode'))==manifest['counts']
    assert db.execute("SELECT count(*) FROM entries WHERE mode='nomTelex' AND text='0'").fetchone()[0]==0
    assert db.execute('SELECT count(*) FROM annotations').fetchone()[0]>1000
    assert db.execute('SELECT count(*) FROM cantonese').fetchone()[0]>10000
assert not (ROOT/'FusionCore/Sources/FusionCore/Resources/lexicon.sqlite').exists()
for name in ['nom_qwerty','nom_quoc_ngu','quoc_ngu_qwerty']:
    assert (ROOT/f'FusionCore/Sources/FusionCore/Resources/Vietnamese/{name}.bin').read_bytes()==(ROOT.parent/f'android/app/viet/src/main/res/raw/{name}.bin').read_bytes()
print(f"Project graph, resources, privacy manifests, dictionary hash and {sum(manifest['counts'].values()):,} entries verified.")
subprocess.run(['python3',str(ROOT/'Scripts/build_localizations.py'),'--check'],check=True)
