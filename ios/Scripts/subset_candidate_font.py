#!/usr/bin/env python3
"""Rebuild the checked-in small supplementary-Hanja font (optional maintainer tool).

Requires fonttools 4.61+ and the original Noto Sans CJK KR Regular 2.004 OTF:
https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf
Usage: python3 subset_candidate_font.py /path/to/NotoSansCJKkr-Regular.otf
Normal app builds use the checked-in subset and do not download fonts.
The optional rebuild also reads the pinned Mozc dictionary fetched by fetch_mozc.py.
"""
import hashlib
from pathlib import Path
import struct
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
assert hashlib.sha256(source.read_bytes()).hexdigest()=="6bcb2a0703aa137e874fc2dffa85f6c21ba9a67fa329e81b8c801663af7e992a", "Unexpected upstream font version"
data=(ROOT.parent/'android/app/korean/src/main/res/raw/hanja_content.bin').read_bytes()
integer=lambda p:struct.unpack_from('>I',data,p)[0]
characters=set()
for i in range(integer(0)//4):
    offset=integer(i*4)
    for field in range(2):
        start=offset
        while data[offset:offset+2]!=b'\0\0': offset+=2
        if field==1:
            characters.update(ord(c) for c in data[start:offset].decode('utf-16-be') if ord(c)>0xffff)
        offset+=2
mozc=sorted((ROOT/'Vendor/Mozc/src/data/dictionary_oss').glob('dictionary[0-9][0-9].txt'))
assert mozc, "Run Scripts/fetch_mozc.py before rebuilding the font"
for dictionary in mozc:
    for line in dictionary.open(encoding='utf-8'):
        fields=line.rstrip('\n').split('\t')
        if len(fields)>=5:
            characters.update(ord(c) for c in fields[4] if 0x20000<=ord(c)<=0x323af)
font=TTFont(source,recalcTimestamp=False)
assert characters<=font.getBestCmap().keys(), "The upstream font does not cover every supplementary Hanja"
options=subset.Options()
options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*']
worker=subset.Subsetter(options=options);worker.populate(unicodes=characters);worker.subset(font)
names={1:'Fusion Candidate Fallback',2:'Regular',3:'FusionCandidateFallback-Regular-1',4:'Fusion Candidate Fallback Regular',6:'FusionCandidateFallback-Regular',16:'Fusion Candidate Fallback',17:'Regular'}
for record in font['name'].names:
    if record.nameID in names:record.string=names[record.nameID].encode(record.getEncoding())
cff=font['CFF '].cff
cff.fontNames=['FusionCandidateFallback-Regular']
cff.topDictIndex[0].FullName=names[4];cff.topDictIndex[0].FamilyName=names[1]
output=ROOT/'Resources/Fonts/FusionCandidateFallback.otf'
output.parent.mkdir(exist_ok=True)
font.save(output)
print(f'{len(characters)} characters, {output.stat().st_size} bytes: {output}')
