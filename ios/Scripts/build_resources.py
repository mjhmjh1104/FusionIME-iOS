#!/usr/bin/env python3
"""Reproducible offline import of FusionIME's original data and keyboard tables."""
import ast, hashlib, json, math, re, shutil, sqlite3, struct, unicodedata
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT.parent / 'android'
OUT = ROOT / 'FusionCore/Sources/FusionCore/Resources'
LAYOUT = ANDROID / 'app/src/main/java/ee/oyatl/ime/fusion/layout'

def tables():
    data = {'layouts': {}, 'combinations': {}, 'hangul': {}}
    for file in ['Hangul2Set', 'Hangul3Set', 'HangulOld', 'LayoutKana', 'LayoutZhuyin', 'LayoutCangjie', 'LayoutSymbol', 'LayoutQwerty', 'LayoutLatin', 'LayoutExt', 'LayoutGodan']:
        source = (LAYOUT / (file + '.kt')).read_text()
        for name, body in re.findall(r'val (\w+)(?:\s*:\s*[^=]+)?\s*=\s*mapOf\((.*?)\n    \)', source, re.S):
            if name.startswith('TABLE'):
                rows = {}
                for key, values in re.findall(r'(?:KeyEvent|ExtKeyCode)\.KEYCODE_(\w+) to listOf\(([^\n]+)\)', body):
                    parsed = []
                    for match in re.finditer(r"(?:(?:COMB)\s+or\s+)*(0x[\da-fA-F]+|'(?:\\.|[^'])+'\.code|(?<![\w])\d+(?![\w]))",values):
                        value=match.group(1)
                        number=ord(ast.literal_eval(value[:-5])) if value.endswith('.code') else int(value,0)
                        parsed.append(number | (0x80000000 if 'COMB' in match.group(0) else 0))
                    if parsed: rows[key] = parsed
                if rows: data['layouts'][file + '.' + name] = rows
            elif name.startswith('COMB'):
                data['combinations'][file + '.' + name] = {
                    f'{int(a,16)},{int(b,16)}': int(c,16)
                    for a,b,c in re.findall(r'(0x[\da-fA-F]+) to (0x[\da-fA-F]+) to (0x[\da-fA-F]+)', body)
                }
    src = (ANDROID / 'app/korean/hangul/src/main/java/ee/oyatl/ime/fusion/hangul/Hangul.kt').read_text()
    for name, body in re.findall(r'val (CONVERT_\w+) = intArrayOf\((.*?)\n    \)', src, re.S):
        body = re.sub(r'//[^\n]*', '', body)
        data['hangul'][name] = [int(x,16) for x in re.findall(r'0x[0-9a-f]+', body)]
    source=(LAYOUT/'LayoutLatin.kt').read_text()
    maps={name:dict(re.findall(r'(?:KeyEvent|ExtKeyCode)\.KEYCODE_(\w+) to (?:KeyEvent|ExtKeyCode)\.KEYCODE_(\w+)',body)) for name,body in re.findall(r'val (\w*MAP\w*) = mapOf\((.*?)\n    \)',source,re.S)}
    (OUT/'latin-keymaps.json').write_text(json.dumps(maps,ensure_ascii=False,sort_keys=True)+'\n')
    (OUT / 'tables.json').write_text(json.dumps(data, ensure_ascii=False, sort_keys=True))
    extras={}
    for file in ['LatinMoreKeysTable','SymbolMoreKeysTable']:
        source=(LAYOUT/(file+'.kt')).read_text()
        extras[file]={ast.literal_eval(key):[ast.literal_eval(c) for c in re.findall(r"'(?:\\.|[^'])+'",body)]
            for key,body in re.findall(r"('(?:\\.|[^'])+') to listOf\(([^\n]+)\)",source)}
    source=(LAYOUT/'LayoutKana.kt').read_text()
    extras['kana']={name:value for name,value in re.findall(r'const val (KEYS_\w+|BOTTOM_\w+) = "([^"]+)"',source)}
    (OUT/'layout-extras.json').write_text(json.dumps(extras,ensure_ascii=False,sort_keys=True)+'\n')
    cycles={}
    for line in (ROOT/'Vendor/Mozc/src/data/preedit/flick-hiragana.tsv').read_text().splitlines():
        parts=line.split('\t')
        if len(parts)>=3 and len(parts[0])==2 and parts[0].endswith('*'):
            cycles[parts[0][0]]=parts[1]+parts[2]
    (OUT/'kana-modifiers.json').write_text(json.dumps(cycles,ensure_ascii=False,sort_keys=True)+'\n')

def vietnamese():
    destination=OUT/'Vietnamese'
    destination.mkdir(parents=True,exist_ok=True)
    for name in ['nom_qwerty','nom_quoc_ngu','quoc_ngu_qwerty']:
        shutil.copyfile(ANDROID/f'app/viet/src/main/res/raw/{name}.bin',destination/f'{name}.bin')

# AOSP readings contain no tone numbers. Zhuyin lookup consequently ignores tones.
def bopomofo(py):
    initials = {'zh':'ㄓ','ch':'ㄔ','sh':'ㄕ', **dict(zip('bpmfdtnlgkhjqxrzcs','ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄖㄗㄘㄙ'))}
    finals = dict(zip('a o e ai ei ao ou an en ang eng er i ia ie iao iu ian in iang ing iong u ua uo uai ui uan un uang ong v ve van vn'.split(), 'ㄚ ㄛ ㄜ ㄞ ㄟ ㄠ ㄡ ㄢ ㄣ ㄤ ㄥ ㄦ ㄧ ㄧㄚ ㄧㄝ ㄧㄠ ㄧㄡ ㄧㄢ ㄧㄣ ㄧㄤ ㄧㄥ ㄩㄥ ㄨ ㄨㄚ ㄨㄛ ㄨㄞ ㄨㄟ ㄨㄢ ㄨㄣ ㄨㄤ ㄨㄥ ㄩ ㄩㄝ ㄩㄢ ㄩㄣ'.split()))
    replacements = {'yi':'i','ya':'ia','ye':'ie','yao':'iao','you':'iu','yan':'ian','yin':'in','yang':'iang','ying':'ing','yong':'iong','yu':'v','yue':'ve','yuan':'van','yun':'vn','wu':'u','wa':'ua','wo':'uo','wai':'uai','wei':'ui','wan':'uan','wen':'un','wang':'uang','weng':'ueng'}
    py = replacements.get(py, py.replace('ü','v'))
    if py == 'ueng': return 'ㄨㄥ'
    initial = next((x for x in sorted(initials, key=len, reverse=True) if py.startswith(x)), '')
    final = py[len(initial):]
    if initial in ['zh','ch','sh','r','z','c','s'] and final == 'i': final = ''
    if initial in ['j','q','x'] and final.startswith('u'): final = 'v' + final[1:]
    return initials.get(initial,'') + finals.get(final,final)

def build():
    OUT.mkdir(parents=True, exist_ok=True)
    tables()
    vietnamese()
    korean=OUT/"Korean";korean.mkdir(exist_ok=True)
    for name in ["hanja_index","hanja_content","hanja_bigram"]:
        shutil.copyfile(ANDROID/f"app/korean/src/main/res/raw/{name}.bin",korean/f"{name}.bin")
    path = ROOT / 'Resources/lexicon.sqlite'
    temp = path.with_suffix('.building')
    temp.unlink(missing_ok=True)
    db = sqlite3.connect(temp)
    db.executescript('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA temp_store=MEMORY; CREATE TABLE entries (mode TEXT NOT NULL, reading TEXT NOT NULL, text TEXT NOT NULL, score REAL NOT NULL);')
    counts = {}
    def insert(mode, rows):
        count = 0
        batch = []
        for key, text, score in rows:
            key = unicodedata.normalize('NFC', key).lower().replace(' ', '').replace("'", '')
            if not key or not text: continue
            batch.append((mode,key,text,float(score)))
            count += 1
            if len(batch) >= 5000:
                db.executemany('INSERT INTO entries VALUES (?,?,?,?)', batch); batch.clear()
        db.executemany('INSERT INTO entries VALUES (?,?,?,?)', batch)
        counts[mode] = count
        print(mode, count, flush=True)
    def tsv(file):
        with file.open() as stream:
            for line in stream:
                cols=line.rstrip('\n').split('\t')
                if len(cols)>=2: yield cols
    ko = ANDROID / 'data/ko_dict_all.tsv'
    insert('hanja', ((r[0],r[1],math.log1p(max(float(r[2] or 0),0))) for r in tsv(ko)))
    insert('korean', ((r[0],r[0],math.log1p(max(float(r[2] or 0),0))) for r in tsv(ko)))
    db.execute('CREATE TABLE annotations (mode TEXT NOT NULL,reading TEXT NOT NULL,text TEXT NOT NULL,extra TEXT NOT NULL,PRIMARY KEY(mode,reading,text)) WITHOUT ROWID')
    db.executemany('INSERT OR REPLACE INTO annotations VALUES (?,?,?,?)',(('hanja',unicodedata.normalize('NFC',r[0]).lower().replace(' ','').replace("'",''),r[1],r[3]) for r in tsv(ko) if len(r)>3 and r[3]))
    def jeongun():
        data=(ANDROID/'app/korean/src/main/res/raw/jeongun.bin').read_bytes()
        def short(p): return struct.unpack_from('>H',data,p)[0]
        def integer(p): return struct.unpack_from('>I',data,p)[0]
        def string(p):
            end=p
            while short(end): end+=2
            return data[p:end].decode('utf-16-be'),end+2
        def walk(p,units):
            count=short(p); children=p+2; p+=2+count*6
            entries=short(p); p+=2
            reading=b''.join(struct.pack('>H',c) for c in units).decode('utf-16-be')
            for _ in range(entries):
                word,p=string(p); extra,p=string(p); score=short(p); p+=2
                yield reading,word,score
            for i in range(count):
                q=children+i*6
                yield from walk(integer(q+2),units+[short(q)])
        yield from walk(integer(len(data)-4),[])
    insert('jeongun',jeongun())
    db.execute('CREATE TABLE bigrams (previous TEXT NOT NULL,next TEXT NOT NULL,score REAL NOT NULL,PRIMARY KEY(previous,next)) WITHOUT ROWID')
    db.executemany('INSERT OR REPLACE INTO bigrams VALUES (?,?,?)', ((r[0],r[1],math.log1p(float(r[2]))) for r in tsv(ANDROID/'data/ko_bigrams.tsv') if len(r)==3))
    for mode,file in [('nom','nom_qwerty.tsv'),('vietnamese','quoc_ngu_qwerty.tsv')]:
        insert(mode, ((r[0],r[1],math.log1p(max(float(r[2] or 0),0))) for r in tsv(ANDROID/'data'/file)))
    insert('nomTelex', ((r[0] if r[2].isdigit() else r[0]+' '+r[1], r[1] if r[2].isdigit() else r[2], 0) for r in tsv(ANDROID/'data/nom_quoc_ngu.tsv')))
    jy = list(tsv(ANDROID/'data/jyutping.txt'))
    db.execute('CREATE TABLE cantonese (number INTEGER PRIMARY KEY,text TEXT NOT NULL,romanization TEXT NOT NULL,spell TEXT NOT NULL,anchors TEXT NOT NULL)')
    db.executemany('INSERT INTO cantonese VALUES (?,?,?,?,?)',((i,r[0],r[1],re.sub('[^a-z]','',r[1]),''.join(p[0] for p in r[1].split(' ') if p)) for i,r in enumerate(jy)))
    db.executescript('CREATE INDEX cantonese_spell ON cantonese(spell,number); CREATE INDEX cantonese_anchors ON cantonese(anchors,number);')
    aliases=dict(re.findall(r'"([a-z]+)" to "([a-z]+)"',(ANDROID/'app/jyutping/src/main/java/org/jyutping/jyutping/models/Syllables.kt').read_text()))
    (OUT/'jyutping-syllables.json').write_text(json.dumps(aliases,sort_keys=True)+'\n')
    insert('jyutping', ((r[1],r[0],-i/len(jy)) for i,r in enumerate(jy)))
    insert('jyutpingPlain', ((re.sub('[1-6]','',r[1]),r[0],-i/len(jy)) for i,r in enumerate(jy)))
    for mode,file in [('cangjie','cangjie3.txt'),('quick','quick-classic.txt')]:
        insert(mode, ((r[0],r[1],float(r[2])) for r in tsv(ANDROID/'app/cangjie/host/src/main/resources'/file)))
    def dayi():
        for line in (ANDROID/'app/cangjie/host/src/main/resources/dayi3.cin').read_text().splitlines():
            r=line.split()
            if len(r)==2 and not r[0].startswith('%'): yield r[0],r[1],0
    insert('dayi', dayi())
    for mode,suffix in [('pinyin',''),('pinyinTraditional','.hant')]:
        raw=(ANDROID/f'app/pinyin/src/main/jni/data/rawdict_utf16_65105_freq{suffix}.txt').read_text(encoding='utf-16').splitlines()
        rows=[line.split() for line in raw if len(line.split())>=4]
        insert(mode, ((''.join(r[3:]),r[0],math.log1p(float(r[1]))) for r in rows))
        if suffix:
            insert('zhuyin', ((''.join(map(bopomofo,r[3:])),r[0],math.log1p(float(r[1]))) for r in rows))
    def japanese():
        for file in sorted((ROOT/'Vendor/Mozc/src/data/dictionary_oss').glob('dictionary[0-9][0-9].txt')):
            for r in tsv(file):
                if len(r)>=5: yield r[0],r[4],-float(r[3])/1000
    insert('japanese', japanese())
    if counts['japanese']==0: raise RuntimeError('Run fetch_mozc.py first; refusing to ship an empty Japanese dictionary')
    print('Indexing and deduplicating…', flush=True)
    db.executescript('CREATE TABLE compact (mode TEXT NOT NULL,reading TEXT NOT NULL,text TEXT NOT NULL,score REAL NOT NULL,PRIMARY KEY(mode,reading,text)) WITHOUT ROWID; INSERT INTO compact SELECT mode,reading,text,MAX(score) FROM entries GROUP BY mode,reading,text; DROP TABLE entries; ALTER TABLE compact RENAME TO entries; PRAGMA user_version=1; VACUUM;')
    counts=dict(db.execute('SELECT mode, COUNT(*) FROM entries GROUP BY mode'))
    db.close()
    temp.replace(path)
    (ROOT/'Resources/manifest.json').write_text(json.dumps({'schema':1,'counts':counts,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()},indent=2)+'\n')
    licenses=ROOT/'Resources/Licenses'
    shutil.copy(ANDROID/'LICENSE', licenses/'FusionIME-GPL-3.0.txt')
    shutil.copy(ROOT/'Vendor/Mozc/LICENSE', licenses/'Mozc.txt')
    shutil.copy(ROOT/'Vendor/Mozc/src/data/dictionary_oss/README.txt', licenses/'Mozc-dictionary.txt')
    print(f'Wrote {path.stat().st_size/1024**2:.1f} MiB',flush=True)

if __name__=='__main__': build()
