#!/usr/bin/env python3
"""Independent oracle for the original Kotlin Hanja converters and binary files."""
from pathlib import Path
import json,struct,functools
root=Path(__file__).resolve().parents[2]
raw=root/'android/app/korean/src/main/res/raw'
index,content,bigram=[(raw/f'hanja_{name}.bin').read_bytes() for name in ('index','content','bigram')]
def u16(data,p):return struct.unpack_from('>H',data,p)[0]
def i32(data,p):return struct.unpack_from('>I',data,p)[0]
def string(data,p):
    end=p
    while u16(data,end):end+=2
    return data[p:end].decode('utf-16-be'),end+2
def length(text):return len(text.encode('utf-16-be'))//2
@functools.cache
def word(id):
    p=i32(content,id*4);reading,p=string(content,p);text,p=string(content,p)
    score=i32(content,p);extra,p=string(content,p+4)
    return (id,text,score,extra)
@functools.cache
def lookup(reading):
    node=i32(index,len(index)-4)
    for char in reading:
        edges={u16(index,node+2+i*6):i32(index,node+4+i*6) for i in range(u16(index,node))}
        if ord(char) not in edges:return []
        node=edges[ord(char)]
    p=node+2+6*u16(index,node)
    return [word(i32(index,p+2+i*4)) for i in range(u16(index,p))]
@functools.cache
def following(id):
    node=i32(bigram,len(bigram)-4)
    edges={i32(bigram,node+8+i*8):i32(bigram,node+12+i*8) for i in range(i32(bigram,node+4))}
    if id not in edges:return set()
    node=edges[id]
    return {i32(bigram,node+8+i*8) for i in range(i32(bigram,node+4))}
def f32(x):return struct.unpack('f',struct.pack('f',x))[0]
def score(path):
    total=0.
    for w in path:total=f32(total+f32(w[2]))
    return f32(total/len(path))
def candidates(text,phrase):
    @functools.cache
    def single(text):return [w for n in range(1,len(text)+1) for w in lookup(text[:n]) if phrase or length(w[1])==n]
    def visit(context,text,depth):
        if not text or depth>4:return [context]
        available=[w for w in single(text) if depth==0 or w[0] in following(context[-1][0])]
        if not available:return [context]
        return [context+tail for w in available for tail in visit((w,),text[length(w[1]):],depth+1)]+[context]
    paths=visit((),text,0) if phrase else [(w,) for w in single(text)]
    paths=[p for p in paths if p];paths.sort(key=lambda p:-score(p));seen=set();unique=[]
    for p in paths:
        t=''.join(w[1] for w in p)
        if t not in seen:seen.add(t);unique.append(p)
    if phrase:
        unique.sort(key=lambda p:-sum(0x4e00<=ord(c)<=0x9fff for w in p for c in w[1]))
        unique.sort(key=len)
    unique.sort(key=lambda p:-sum(length(w[1]) for w in p))
    return [{'text':''.join(w[1] for w in p),'score':score(p),'annotation':p[0][3] if len(p)==1 else ''} for p in unique]
texts=['가','대','하','댛','대하','한국','한국어','대한민국','대한민국사람','한자변환','문맥','사람','학교','사회','경제','문화','민주주의','가나다','대한민국국민','한국어'*10,'대하'*20,'아'*65,'한국사람은한자변환후보를입력하고있습니다']
fixtures=[{'input':t,'phrase':p,'expected':candidates(t,p)} for t in texts for p in [False,True]]
output=root/'ios/FusionCore/Tests/FusionCoreTests/Fixtures/hanja-upstream.json'
output.write_text(json.dumps(fixtures,ensure_ascii=False,separators=(',',':'))+'\n')
print(json.dumps({'fixtures':len(fixtures),'candidates':sum(len(x['expected']) for x in fixtures),'largest':max(len(x['expected']) for x in fixtures)}))
