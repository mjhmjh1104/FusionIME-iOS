#include "Public/FusionPinyin.h"
#include "include/matrixsearch.h"
#include "include/utf16char.h"
#include <cstring>
#include <memory>
#include <algorithm>
struct Pinyin {
  ime_pinyin::MatrixSearch search;
  uint16_t buffer[256] = {};
  uint16_t predictions[512][ime_pinyin::kMaxPredictSize+1] = {};
  size_t prediction_count=0;
};
extern "C" {
void *fp_create(const char *dictionary, const char *user_dictionary) {
  if (!dictionary || !user_dictionary) return nullptr;
  auto p=std::make_unique<Pinyin>();
  if (!p->search.init(dictionary,user_dictionary)) return nullptr;
  p->search.set_max_lens(120,120);
  return p.release();
}
void fp_destroy(void *raw) { delete static_cast<Pinyin *>(raw); }
int fp_search(void *raw,const char *text) {
  if (!raw || !text || std::strlen(text)>120) return 0;
  auto &s=static_cast<Pinyin *>(raw)->search;
  s.search(text,std::strlen(text)); return s.get_candidate_num();
}
void fp_reset(void *raw) { if(raw) static_cast<Pinyin *>(raw)->search.reset_search(); }
int fp_choose(void *raw,int index) {
  if(!raw || index<0 || index>=fp_candidate_count(raw)) return 0;
  return static_cast<Pinyin *>(raw)->search.choose(index);
}
int fp_cancel_choice(void *raw) { return raw ? static_cast<Pinyin *>(raw)->search.cancel_last_choice():0; }
int fp_candidate_count(void *raw) { return raw ? static_cast<Pinyin *>(raw)->search.get_candidate_num():0; }
const uint16_t *fp_candidate(void *raw,int index) {
  if (!raw || index<0 || index>=fp_candidate_count(raw)) return nullptr;
  auto p=static_cast<Pinyin *>(raw); std::memset(p->buffer,0,sizeof(p->buffer));
  return p->search.get_candidate(index,p->buffer,256);
}
const char *fp_pinyin(void *raw) {
  if (!raw) return ""; size_t n=0; return static_cast<Pinyin *>(raw)->search.get_pystr(&n);
}
int fp_fixed_length(void *raw) { return raw ? static_cast<Pinyin *>(raw)->search.get_fixedlen():0; }
int fp_fixed_pinyin_length(void *raw) {
  if (!raw) return 0; const ime_pinyin::uint16 *positions=nullptr;
  auto &s=static_cast<Pinyin *>(raw)->search; auto n=s.get_spl_start(positions);
  return positions ? positions[std::min(n,s.get_fixedlen())]:0;
}
int fp_fully_selected(void *raw) {
  if(!raw) return 0; const ime_pinyin::uint16 *positions=nullptr;
  auto &s=static_cast<Pinyin *>(raw)->search; auto n=s.get_spl_start(positions);
  return n>0 && n==s.get_fixedlen();
}
void fp_flush(void *raw) { if(raw) static_cast<Pinyin *>(raw)->search.flush_cache(); }
int fp_predict(void *raw,const uint16_t *context) {
  if(!raw || !context) return 0;
  auto p=static_cast<Pinyin *>(raw);
  p->prediction_count=p->search.get_predicts(context,p->predictions,512);
  return static_cast<int>(p->prediction_count);
}
const uint16_t *fp_prediction(void *raw,int index) {
  if(!raw || index<0) return nullptr;
  auto p=static_cast<Pinyin *>(raw);
  return static_cast<size_t>(index)<p->prediction_count ? p->predictions[index]:nullptr;
}
}
