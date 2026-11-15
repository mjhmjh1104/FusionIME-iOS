#include "Public/FusionLatin.h"
#include "Engine/dictionary/structure/dictionary_structure_with_buffer_policy_factory.h"
#include "Engine/dictionary/property/ngram_context.h"
#include "Engine/suggest/core/dictionary/dictionary.h"
#include "Engine/suggest/core/layout/proximity_info.h"
#include "Engine/suggest/core/session/dic_traverse_session.h"
#include "Engine/suggest/core/result/suggestion_results.h"
#include "Engine/suggest/core/suggest_options.h"
#include "Engine/utils/jni_data_utils.h"
#include "Engine/utils/log_utils.h"
#include "Engine/utils/autocorrection_threshold_utils.h"
#include <memory>
#include <sys/stat.h>
#include <string>
#include <ctime>
#include "Engine/utils/time_keeper.h"
namespace latinime {
void LogUtils::logToJava(JNIEnv*,const char*,...) {}
const int JniDataUtils::CODE_POINT_REPLACEMENT_CHARACTER=0xFFFD;
const int JniDataUtils::CODE_POINT_NULL=0;
}
using namespace latinime;
namespace {
struct Latin {
 JNIEnv env;
 std::unique_ptr<Dictionary> dictionary,history;
 std::string historyPath;
 bool dirty=false;
 std::unique_ptr<DicTraverseSession> historySession;
 std::unique_ptr<ProximityInfo> proximity;
 std::unique_ptr<DicTraverseSession> session;
 std::vector<int> codes=std::vector<int>(MAX_RESULTS*MAX_WORD_LENGTH),scores=std::vector<int>(MAX_RESULTS),types=std::vector<int>(MAX_RESULTS);
 std::vector<int> lastInput,lastContext;
 int count=0;
 void flush() {
  if(!history || !dirty || historyPath.empty()) return;
  const bool ok=history->needsToRunGC(false) ? history->flushWithGC(historyPath.c_str()):history->flush(historyPath.c_str());
  if(ok) dirty=false;
 }
 ~Latin(){flush();}
};
std::vector<int> ascii(const char*s){return std::vector<int>(s,s+strlen(s));}
NgramContext makeContext(const int32_t*input,int size) {
 int words[MAX_PREV_WORD_COUNT_FOR_N_GRAM][MAX_WORD_LENGTH]={};
 int lengths[MAX_PREV_WORD_COUNT_FOR_N_GRAM]={};bool begins[MAX_PREV_WORD_COUNT_FOR_N_GRAM]={};
 int count=0,offset=0;
 if(size==0) return NgramContext(nullptr,0,true);
 while(offset<size && count<MAX_PREV_WORD_COUNT_FOR_N_GRAM) {
  int length=0;bool invalid=false;
  while(offset<size && input[offset]!=0) {
   int value=input[offset++];
   if(value==-1) begins[count]=true;
   else if(value<0 || length>=MAX_WORD_LENGTH-1) invalid=true;
   else words[count][length++]=value;
  }
  ++offset;lengths[count]=invalid ? 0:length;++count;
 }
 return NgramContext(words,lengths,begins,count);
}
}
extern "C" {
void *fl_create(const char*path) {
 struct stat info{};
 if(!path || stat(path,&info)!=0 || info.st_size>INT32_MAX) return nullptr;
 auto policy=DictionaryStructureWithBufferPolicyFactory::newPolicyForExistingDictFile(path,0,int(info.st_size),false);
 if(!policy) return nullptr;
 auto p=std::make_unique<Latin>();
 p->dictionary=std::make_unique<Dictionary>(&p->env,std::move(policy));
 // Character distance works for all scripts, including Korean. Touch positions are optional.
 std::vector<int> grid(MAX_PROXIMITY_CHARS_SIZE,NOT_A_CODE_POINT);
 p->proximity=std::make_unique<ProximityInfo>(&p->env,1,1,1,1,1,1,&grid,0,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr,nullptr);
 p->session=std::make_unique<DicTraverseSession>(&p->env,nullptr,false);
 return p.release();
}
void fl_destroy(void*p){delete static_cast<Latin*>(p);}
void fl_set_history(void*raw,const char*path,const char*locale){
 auto p=static_cast<Latin*>(raw);if(!p || !path || !locale) return;
 TimeKeeper::setCurrentTime();
 DictionaryHeaderStructurePolicy::AttributeMap attributes;
 attributes[ascii("USES_FORGETTING_CURVE")]=ascii("1");
 attributes[ascii("HAS_HISTORICAL_INFO")]=ascii("1");
 struct stat info{};
 auto policy=stat(path,&info)==0 && S_ISDIR(info.st_mode)
  ? DictionaryStructureWithBufferPolicyFactory::newPolicyForExistingDictFile(path,0,0,true)
  : DictionaryStructureWithBufferPolicyFactory::newPolicyForOnMemoryDict(403,ascii(locale),&attributes);
 if(!policy) return;
 p->history=std::make_unique<Dictionary>(&p->env,std::move(policy));p->historyPath=path;
 p->historySession=std::make_unique<DicTraverseSession>(&p->env,nullptr,false);
}
void fl_flush(void*raw){if(raw) static_cast<Latin*>(raw)->flush();}
int fl_probability(void*raw,const int32_t*word,int n){
 auto p=static_cast<Latin*>(raw);return p && n>0 && n<MAX_WORD_LENGTH ? p->dictionary->getProbability(CodePointArrayView(word,n)):-1;
}
void fl_learn(void*raw,const int32_t*word,int n,const int32_t*previous,int prevN,int valid,int count){
 auto p=static_cast<Latin*>(raw);if(!p || !p->history || n<=0 || n>=MAX_WORD_LENGTH) return;
 TimeKeeper::setCurrentTime();const auto context=makeContext(previous,prevN);
 p->dirty |= p->history->updateEntriesForWordWithNgramContext(&context,CodePointArrayView(word,n),valid,HistoricalInfo(int(time(nullptr)),0,std::max(1,count)));
 if(p->history->needsToRunGC(false)) p->flush();
}
void fl_forget(void*raw,const int32_t*word,int n){
 auto p=static_cast<Latin*>(raw);if(p && p->history && n>0 && n<MAX_WORD_LENGTH){p->dirty |= p->history->removeUnigramEntry(CodePointArrayView(word,n));p->flush();}
}
int fl_suggest(void*raw,const int32_t*word,int n,const int32_t*previous,int prevN){
 if(!raw) return 0;
 auto p=static_cast<Latin*>(raw);p->count=0;
 if(n<0 || n>=MAX_WORD_LENGTH || prevN<0) return 0;
 TimeKeeper::setCurrentTime();
 const std::vector<int> currentContext=prevN ? std::vector<int>(previous,previous+prevN):std::vector<int>();
 if(n<int(p->lastInput.size()) || !std::equal(p->lastInput.begin(),p->lastInput.end(),word) || currentContext!=p->lastContext) {
  p->session=std::make_unique<DicTraverseSession>(&p->env,nullptr,false);
  if(p->history) p->historySession=std::make_unique<DicTraverseSession>(&p->env,nullptr,false);
 }
 p->lastInput=n ? std::vector<int>(word,word+n):std::vector<int>();p->lastContext=currentContext;
 const auto context=makeContext(previous,prevN);
 struct Entry{std::vector<int> word;int score,type;};std::vector<Entry> entries;
 auto query=[&](Dictionary*dict,DicTraverseSession*session){
  SuggestionResults results(MAX_RESULTS);
  if(n){
   std::vector<int> input(word,word+n),coords(n,NOT_A_COORDINATE),times(n,0),ids(n,0);
   const int options[]={0,1,0,0,1000};SuggestOptions opt(options,5);
   dict->getSuggestions(p->proximity.get(),session,coords.data(),coords.data(),times.data(),ids.data(),input.data(),n,&context,&opt,NOT_A_WEIGHT_OF_LANG_MODEL_VS_SPATIAL_MODEL,&results);
  } else {dict->getPredictions(&context,&results);}
  std::vector<int> count(1),codes(MAX_RESULTS*MAX_WORD_LENGTH),scores(MAX_RESULTS),types(MAX_RESULTS),spaces(MAX_RESULTS),confidence(1);std::vector<float> weight(1);
  results.outputSuggestions(&p->env,&count,&codes,&scores,&spaces,&types,&confidence,&weight);
  for(int i=0;i<count[0];++i){auto begin=codes.begin()+i*MAX_WORD_LENGTH;auto end=std::find(begin,begin+MAX_WORD_LENGTH,0);entries.push_back({std::vector<int>(begin,end),scores[i],types[i]});}
 };
 query(p->dictionary.get(),p->session.get());if(p->history) query(p->history.get(),p->historySession.get());
 // DictionaryFacilitatorImpl + SuggestionResults: score, length, lexical order.
 std::stable_sort(entries.begin(),entries.end(),[](const Entry&a,const Entry&b){return a.score!=b.score ? a.score>b.score:a.word.size()!=b.word.size() ? a.word.size()<b.word.size():a.word<b.word;});
 entries.erase(std::unique(entries.begin(),entries.end(),[](const Entry&a,const Entry&b){return a.score==b.score && a.word==b.word;}),entries.end());
 p->count=std::min(int(entries.size()),MAX_RESULTS);std::fill(p->codes.begin(),p->codes.end(),0);
 for(int i=0;i<p->count;++i){int j=p->count-i-1;std::copy(entries[i].word.begin(),entries[i].word.end(),p->codes.begin()+j*MAX_WORD_LENGTH);p->scores[j]=entries[i].score;p->types[j]=entries[i].type;}
 return p->count;
}
const int32_t*fl_candidate(void*raw,int i){auto p=static_cast<Latin*>(raw);return p&&i>=0&&i<p->count ? p->codes.data()+(p->count-i-1)*MAX_WORD_LENGTH:nullptr;}
int fl_score(void*raw,int i){auto p=static_cast<Latin*>(raw);return p&&i>=0&&i<p->count ? p->scores[p->count-i-1]:0;}
int fl_whitelisted(void*raw,int index){auto p=static_cast<Latin*>(raw);return p && index>=0 && index<p->count && (p->types[p->count-index-1]&Dictionary::KIND_MASK_KIND)==Dictionary::KIND_WHITELIST;}
int fl_autocorrection(void*raw,const int32_t*word,int n,float threshold){
 auto p=static_cast<Latin*>(raw);
 if(!p || !word || n<1 || n>=MAX_WORD_LENGTH || p->count==0) return -1;
 const int i=p->count-1,kind=p->types[i]&Dictionary::KIND_MASK_KIND;
 if(kind==Dictionary::KIND_SHORTCUT) return -1;
 if(kind==Dictionary::KIND_WHITELIST) return 0;
 if(!(p->types[i]&Dictionary::KIND_FLAG_APPROPRIATE_FOR_AUTOCORRECTION)) return -1;
 const int*after=p->codes.data()+i*MAX_WORD_LENGTH;
 int length=0;while(length<MAX_WORD_LENGTH && after[length]) ++length;
 return AutocorrectionThresholdUtils::calcNormalizedScore(word,n,after,length,p->scores[i])>=threshold ? 0:-1;
}
}
