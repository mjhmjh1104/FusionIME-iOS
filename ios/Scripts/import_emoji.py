#!/usr/bin/env python3
"""Import the exact EmojiPicker version used by the Android app.

Usage: python3 ios/Scripts/import_emoji.py path/to/emoji2-emojipicker-1.7.0.aar
Official artifact: https://dl.google.com/dl/android/maven2/androidx/emoji2/emoji2-emojipicker/1.7.0/emoji2-emojipicker-1.7.0.aar
"""
import hashlib,json,sys,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
archive=Path(sys.argv[1])
expected='ec2e12c7c2cb7c3e2358c92847f60c7557dc0cbce17945382b3d69d3e6dbb899'
if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected:
    raise SystemExit('Expected the pinned EmojiPicker 1.7.0 AAR; checksum mismatch')
names=['emotions','people_gender_inclusive','animals_nature','food_drink','travel_places','activity','objects','symbols','flags']
with zipfile.ZipFile(archive) as package:
    groups=[]
    for name in names:
        rows=[list(dict.fromkeys(row.split(','))) for row in package.read(f'res/raw/emoji_category_{name}.csv').decode().splitlines() if row]
        groups.append({'id':name,'items':rows})
    (root/'FusionCore/Sources/FusionCore/Resources/emoji.json').write_text(json.dumps(groups,ensure_ascii=False,separators=(',',':'))+'\n')
    (root/'Resources/Licenses/AndroidX-EmojiPicker.txt').write_bytes(package.read('META-INF/androidx/emoji2/emoji2-emojipicker/LICENSE.txt'))
(root/'Resources/emoji-source.json').write_text(json.dumps({'version':'1.7.0','sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'groups':len(groups),'baseEmoji':sum(len(g['items']) for g in groups),'variants':sum(len(v) for g in groups for v in g['items'])},indent=2)+'\n')
print('Imported',sum(len(g['items']) for g in groups),'emoji groups and variants.')
