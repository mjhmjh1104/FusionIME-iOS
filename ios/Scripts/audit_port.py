#!/usr/bin/env python3
"""Read-only upstream/iOS port audit. Reports observations; does not change app code.

Run from any directory with Xcode and a JDK installed. Native profiles and build
products stay in a temporary directory. No network or device connection is used.
"""
import ast
import hashlib
import json
import os
import re
import random
import subprocess
import struct
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

IOS=Path(__file__).resolve().parents[1]
ANDROID=IOS.parent/'android'
LAYOUT=ANDROID/'app/src/main/java/ee/oyatl/ime/fusion/layout'
OUTPUT=IOS/'Validation/2026-11-15'
WORK=Path(tempfile.gettempdir())/'FusionIME-PortAudit'
WORK.mkdir(exist_ok=True)
OUTPUT.mkdir(parents=True,exist_ok=True)

def run(args,**kwargs):
    return subprocess.run(list(map(str,args)),check=True,**kwargs)

def upstream_tables(file):
    tables={}
    source=file.read_text()
    for name,body in re.findall(r'val (\w+)(?:\s*:\s*[^=]+)?\s*=\s*mapOf\((.*?)\n    \)',source,re.S):
        rows={}
        for key,items in re.findall(r'(?:KeyEvent|ExtKeyCode)\.KEYCODE_(\w+) to listOf\(([^\n]+)\)',body):
            values=[]
            for value in re.findall(r"(?:(?:COMB\s+or\s+)+)?(?:0x[\da-fA-F]+|'(?:\\.|[^'])+'\.code|(?<![\w])\d+(?![\w]))",items):
                dead="COMB" in value
                value=re.sub(r"(?:COMB\s+or\s+)+","",value).strip()
                if re.fullmatch(r'0x[\da-fA-F]+',value): values.append(int(value,16))
                elif re.fullmatch(r"'.*'\.code",value): values.append(ord(ast.literal_eval(value[:-5])))
                elif value.isdigit(): values.append(int(value))
                if dead and values: values[-1] |= 0x80000000
            if values: rows[key]=values
        if rows: tables[name]=rows
    return tables

# Capture the source settings surface, including all five separate `layout` keys.
preferences=[]
for path in sorted((ANDROID/'app/src/main/res/xml').glob('pref_*.xml')):
    for element in ET.parse(path).iter():
        attrs={k.rsplit('}',1)[-1]:v for k,v in element.attrib.items()}
        if 'key' in attrs and not attrs['key'].endswith('_header'):
            preferences.append({'file':str(path.relative_to(IOS.parent)),**attrs})

# Original test vectors; unlike a port's own tests these were not selected to fit it.
source=(ANDROID/'app/pinyin/src/test/java/ee/oyatl/ime/fusion/pinyin/DoublePinyinSchemeTest.kt').read_text()
vectors=[]
for scheme,body in re.findall(r'assertCases\(DoublePinyinScheme\.(\w+), mapOf\((.*?)\)\)',source,re.S):
    vectors += [{'scheme':scheme,'keys':key,'expected':value} for key,value in re.findall(r'"([^"]+)" to "([^"]+)"',body)]
for scheme,body in re.findall(r'DoublePinyinScheme\.(\w+) to mapOf\((.*?)\)',source,re.S):
    vectors += [{'scheme':scheme,'keys':key,'expected':value} for key,value in re.findall(r'"([^"]+)" to "([^"]+)"',body)]

viet_inputs={
    'telex':['aas','awz','ddz','tieengs','hoaf','hoas','quas','thuowng','ddawng','owf','uow','aafz','aass','oong','tieesng','nguowif','huyeefn','vieetj','Vieetj','asb','aa','aw','dd','ddawngj'],
    'vni':['a61','a80','d90','tie6ng1','hoa2','hoa1','qua1','thu7o7ng','da8ng','o72','u7o7','a620','a11','o6ng','vie6t5','Vie6t5','a1b','a6','a8','d9','da8ng5']}
# Exercise branch boundaries, capitalization, repeated/removal marks, punctuation,
# multiple words and deterministic arbitrary sequences against the real Java.
randomizer=random.Random(20261115)
for mode,keys in viet_inputs.items():
    marks='sfrxjaeowdz' if mode=='telex' else '0123456789'
    for word in ['a','e','i','o','u','y','d','â','ă','ê','ô','ơ','ư','đ','á','ấ','ờ','ự','hoa','hoe','huy','quy','qua','gia','giu','nghieng','nghieeng','truong','thuong','tuoi','huou','nguyen','uy','uo','uơ','ưo','ươ','uông','loán','toán','a123456','a1234567','a,','a.','a0','tieng viet','xin chao']:
        for mark in marks:
            keys += [word+mark,word+mark+mark,word+mark+('z' if mode=='telex' else '0'),word.upper()+mark.upper()]
    alphabet='aaeeiioouuybdghkmnpqtv '+marks
    keys += [''.join(randomizer.choices(alphabet,k=randomizer.randint(1,18))) for _ in range(2000)]
    keys += ['aaa','banana','dduwowngf','d9u7o7ng2','tieengs Vieetj','tie6ng1 Vie6t5']
    keys += [word+mark for word in ['a\u0301','a\u0302','a\u0323','đ','Đ','quá','GIÁ','uờ','ưó','1','12345678'] for mark in marks]
    viet_inputs[mode]=list(dict.fromkeys(keys))
viet_file=WORK/'vietnamese-input.tsv'
viet_file.write_text(''.join(f'{mode}\t{keys}\n' for mode,keys_list in viet_inputs.items() for keys in keys_list))
java_dir=ANDROID/'app/viet/src/main/java/net/sourceforge/vietpad/inputmethod'
classes=WORK/'java';classes.mkdir(exist_ok=True)
run(['javac','-encoding','UTF-8','-d',classes,*[java_dir/name for name in ['InputMethod.java','TelexIM.java','VniIM.java','VietKeyInput.java']],IOS/'Scripts/PortAudit/VietnameseAudit.java'])
java_output=run(['java','-cp',classes,'VietnameseAudit',viet_file],capture_output=True,text=True).stdout
viet_vectors=[dict(zip(['mode','keys','expected'],line.split('\t'))) for line in java_output.splitlines()]
input_file=WORK/'input.json'
# Independent reader for Android DiskDictionary's big-endian trie format.
# Compare every stored reading and extra space/case/prefix probes. Expected
# candidates use VietnameseConverter's stable length/score ordering.
dictionary_vectors=[]
dictionary_counts={}
for name in ['nom_qwerty','nom_quoc_ngu','quoc_ngu_qwerty']:
    data=(ANDROID/f'app/viet/src/main/res/raw/{name}.bin').read_bytes()
    entries={}
    def short(p): return struct.unpack_from('>H',data,p)[0]
    def integer(p): return struct.unpack_from('>I',data,p)[0]
    def string(p):
        end=p
        while short(end): end+=2
        return data[p:end].decode('utf-16-be'),end+2
    def walk(p,key):
        children=short(p)
        for child in range(children):
            edge=p+2+child*6
            walk(integer(edge+2),key+data[edge:edge+2])
        p+=2+children*6;count=short(p);p+=2
        values=[]
        for _ in range(count):
            text,p=string(p);extra,p=string(p)
            score=struct.unpack_from('>h',data,p)[0];p+=2
            values.append((text,score))
        if values: entries[key.decode('utf-16-be')]=values
    walk(integer(len(data)-4),b'')
    dictionary_counts[name]={'readings':len(entries),'entries':sum(map(len,entries.values()))}
    inputs=list(entries)
    inputs+=['tieng viet','tiếng việt','a a',' a','a ','TIENG','tiếng ','đi ','VIỆT','unknown']
    for text in inputs:
        hits=[]
        for length in range(1,len(text)+1):
            reading=text[:length]
            for value,score in entries.get(reading.replace(' ',''),[]):
                hits.append({'text':value,'reading':reading,'score':score,'consumedUTF16':len(reading.encode('utf-16-le'))//2})
        hits.sort(key=lambda x:(-x['consumedUTF16'],-x['score']))
        seen=set();expected=[]
        for hit in hits:
            if hit['text'] not in seen: seen.add(hit['text']);expected.append(hit)
        dictionary_vectors.append({'dictionary':name,'input':text,'expected':expected})
input_file.write_text(json.dumps({'doublePinyin':vectors,'vietnamese':viet_vectors,'vietnameseDictionaries':dictionary_vectors},ensure_ascii=False))
env={**os.environ,'DEVELOPER_DIR':os.environ.get('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')}
raw=run(['xcrun','swift','run','--disable-sandbox','--package-path',IOS/'Scripts/PortAudit','--scratch-path',WORK/'build','--cache-path',WORK/'packages','PortAudit',IOS,input_file],env=env,capture_output=True,text=True)
(WORK/'build.log').write_text(raw.stderr)
observations=json.loads(raw.stdout)
(OUTPUT/'port-audit-observations.json').write_text(json.dumps(observations,ensure_ascii=False,indent=2)+'\n')

imported=json.loads((IOS/'FusionCore/Sources/FusionCore/Resources/tables.json').read_text())['layouts']
import_errors=[]
for table,actual in imported.items():
    file,name=table.split('.')
    expected=upstream_tables(LAYOUT/(file+'.kt'))[name]
    for key,values in expected.items():
        if values != actual.get(key): import_errors.append({'table':table,'key':key,'expected':values,'actual':actual.get(key)})

kana_source=(LAYOUT/'LayoutKana.kt').read_text()
kana=[]
for entry in observations['kanaDirections']:
    name='KEYS_AIUEO' if entry['layout']=='kanaSyllables' else 'KEYS_IROHA'
    text=re.search(r'const val '+name+r' = "([^"]+)"',kana_source).group(1)
    direction=entry['direction']
    groups=[text[i:i+5] for i in range(0,len(text),5)]
    if direction=='right': groups.reverse()
    expected=[text[i:i+10] for i in range(0,len(text),10)] if direction=='horizontal' else [''.join(row) for row in zip(*groups)]
    kana.append({**entry,'expectedRows':expected,'matches':entry['rows']==expected})

variants=observations['layouts']
dayi=next(v for v in variants if v['language']=='dayi' and not v['shifted'])
dayi_keys={key['values'][0]:key['label'] for row in dayi['rows'] for key in row}
punctuation={'GRAVE':'`','MINUS':'-','EQUALS':'=','LEFT_BRACKET':'[','RIGHT_BRACKET':']','BACKSLASH':'\\','SEMICOLON':';','APOSTROPHE':"'",'COMMA':',','PERIOD':'.','SLASH':'/'}
dayi_labels=[]
for key,values in upstream_tables(LAYOUT/'LayoutCangjie.kt')['TABLE_DAYI3'].items():
    code=punctuation.get(key,key.lower())
    if dayi_keys.get(code)!=chr(values[0]): dayi_labels.append({'key':code,'expectedLabel':chr(values[0]),'actualLabel':dayi_keys.get(code)})

long_press=[]
english=next(v for v in variants if v['language']=='english' and v['layout']=='qwerty' and not v['shifted'])
english_values={key['values'][0]:key['values'][1:] for row in english['rows'] for key in row}
more_source=(LAYOUT/'LatinMoreKeysTable.kt').read_text()
for key,body in re.findall(r"('(?:\\.|[^'])+') to listOf\(([^\n]+)\)",more_source):
    base=ast.literal_eval(key)
    if base not in english_values: continue
    expected=[ast.literal_eval(m) for m in re.findall(r"'(?:\\.|[^'])+'",body)]
    missing=[x for x in expected if x not in english_values[base]]
    if missing: long_press.append({'base':base,'missing':missing})

summary={
    'scope':'Source audit plus real FusionCore API / upstream Vietnamese Java execution; not Android UI or physical iPhone equivalence testing.',
    'preferenceFiles':20,'keyedPreferenceOccurrences':len(preferences),'distinctPreferenceKeys':len({p['key'] for p in preferences}),
    'preferences':preferences,'layoutVariantsExecuted':len(variants),
    'kanaDirections':kana,'importedTableMismatches':import_errors,'dayiLabelDifferences':dayi_labels,
    'numberRowLongPressMissing':long_press,
    'doublePinyinVectorCount':len(vectors),'doublePinyinMismatches':[x for x in observations['doublePinyinExamples'] if x['actual']!=x['expected']],
    'vietnameseVectorCount':len(viet_vectors),'vietnameseMismatches':[x for x in observations['vietnameseExamples'] if x['actual']!=x['expected']],
    'vietnameseDictionarySourceCounts':dictionary_counts,'vietnameseDictionaries':observations['vietnameseDictionaries'],
    'imports':observations['imports'],'dayiAcceptance':observations['dayiAcceptance'],
    'doublePinyinSemicolon':observations['doublePinyinSemicolon'],'koreanPrefixCommit':observations.get('koreanPrefixCommit'),
    'probes':observations['probes'],
    'sourceHashes':{str(p.relative_to(IOS.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [
        IOS/'FusionCore/Sources/FusionCore/Layouts.swift',IOS/'FusionCore/Sources/FusionCore/SettingsImport.swift',
        IOS/'FusionCore/Sources/FusionCore/CompositionEngine.swift',IOS/'FusionCore/Sources/FusionCore/Transliteration.swift',
        IOS/'FusionCore/Sources/FusionCore/VietnameseComposer.swift',IOS/'FusionCore/Sources/FusionCore/VietnameseDictionary.swift',
        IOS/'FusionCore/Sources/FusionCore/Models.swift',IOS/'FusionCore/Sources/FusionCore/LatinInput.swift',IOS/'FusionCore/Sources/FusionCore/HanjaDictionary.swift',
        *[ANDROID/f'app/viet/src/main/res/raw/{name}.bin' for name in dictionary_counts],
        LAYOUT/'LayoutKana.kt',LAYOUT/'HangulOld.kt',java_dir/'VietKeyInput.java']}}
target=OUTPUT/'port-audit.json'
target.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ['keyedPreferenceOccurrences','distinctPreferenceKeys','layoutVariantsExecuted','importedTableMismatches','doublePinyinVectorCount','doublePinyinMismatches','vietnameseVectorCount','vietnameseMismatches','vietnameseDictionaries','koreanPrefixCommit']},ensure_ascii=False,indent=2))
print(f'Report: {target}')
