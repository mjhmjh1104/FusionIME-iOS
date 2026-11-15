#!/usr/bin/env python3
"""Execute the original DeadKeyCombiner.java with minimal platform value adapters."""
from pathlib import Path
import json,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
work=Path(tempfile.mkdtemp(prefix='fusion-latin-oracle-'))
sources={
'android/text/TextUtils.java':'package android.text; public class TextUtils { public static boolean isEmpty(CharSequence x){return x==null||x.length()==0;} }',
'android/util/SparseIntArray.java':'package android.util; public class SparseIntArray { java.util.HashMap<Integer,Integer> m=new java.util.HashMap<>(); public void append(int k,int v){m.put(k,v);} public void put(int k,int v){m.put(k,v);} public int get(int k){return get(k,0);} public int get(int k,int d){return m.getOrDefault(k,d);} }',
'javax/annotation/Nonnull.java':'package javax.annotation; public @interface Nonnull {}',
'com/android/inputmethod/latin/common/Constants.java':'package com.android.inputmethod.latin.common; public class Constants { public static final int CODE_PERIOD=46,CODE_SINGLE_QUOTE=39,CODE_DASH=45,CODE_GRAVE_ACCENT=96,CODE_CIRCUMFLEX_ACCENT=94,CODE_TILDE=126,CODE_DELETE=-5; }',
'com/android/inputmethod/event/Event.java':'''package com.android.inputmethod.event;
public class Event {
 public int mCodePoint,mKeyCode; public boolean dead,consumed; public Event next;
 public Event(int c,boolean d){mCodePoint=c;mKeyCode=c;dead=d;}
 public boolean isDead(){return dead;} public boolean isFunctionalKeyEvent(){return mKeyCode<0;}
 public static Event createConsumedEvent(Event e){Event r=new Event(e.mCodePoint,e.dead);r.consumed=true;return r;}
 public static Event createHardwareKeypressEvent(int c,int k,Event n,boolean repeat){Event e=new Event(c,false);e.mKeyCode=k;e.next=n;return e;}
}''',
'LatinAudit.java':'''import java.nio.file.*;import java.util.*;import com.android.inputmethod.event.*;
public class LatinAudit { public static void main(String[] a)throws Exception {
 for(String line:Files.readAllLines(Path.of(a[0]))){DeadKeyCombiner c=new DeadKeyCombiner();StringBuilder result=new StringBuilder();
  for(String token:line.split(",")){String[] p=token.split(":");int point=Integer.parseInt(p[1]);Event e=c.processEvent(new ArrayList<>(),new Event(point,p[0].equals("d")));
   while(e!=null){if(!e.consumed){if(e.mKeyCode==-5){if(result.length()>0)result.deleteCharAt(result.length()-1);}else if(e.mCodePoint>=0)result.appendCodePoint(e.mCodePoint);}e=e.next;}
  } System.out.println(Base64.getEncoder().encodeToString(result.toString().getBytes("UTF-8"))+"\\t"+Base64.getEncoder().encodeToString(c.getCombiningStateFeedback().toString().getBytes("UTF-8")));
 }
}}'''}
for relative,text in sources.items():
    path=work/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
original=root/'android/app/latin/src/main/java/com/android/inputmethod/event'
subprocess.run(['javac','-encoding','UTF-8','-d',str(work),*[str(work/p) for p in sources],str(original/'Combiner.java'),str(original/'DeadKeyCombiner.java')],check=True)
accents="`ˋ´^ˆ~˜¯˘˙¨ˀ˚˝ˇˈʻ᾽ʽʼ'.¸˛ˌˍ-"
sequences=[]
for accent in accents:
    for base in 'aeiouyDGHILOTdghilot !':sequences.append([['d',ord(accent)],['t',ord(base)]])
    sequences += [[['d',ord(accent)],['d',ord(accent)]],[['d',ord(accent)],['t',-5],['t',ord('e')]], [['d',ord(accent)],['d',ord('´')],['t',ord('a')]]]
input=work/'input.txt';input.write_text(''.join(','.join(f'{kind}:{point}' for kind,point in s)+'\n' for s in sequences))
raw=subprocess.run(['java','-cp',str(work),'LatinAudit',str(input)],capture_output=True,text=True,check=True).stdout
import base64
fixtures=[]
for seq,line in zip(sequences,raw.splitlines()):
    result,pending=[base64.b64decode(t).decode() for t in line.split('\t')]
    fixtures.append({'events':[{'dead':kind=='d','code':point} for kind,point in seq],'text':result,'pending':pending})
assert len(fixtures)==len(sequences)
(root/'ios/FusionCore/Tests/FusionCoreTests/Fixtures/latin-dead-keys-upstream.json').write_text(json.dumps(fixtures,ensure_ascii=False,separators=(',',':'))+'\n')
print(json.dumps({'originalJavaCases':len(fixtures),'work':str(work)}))
