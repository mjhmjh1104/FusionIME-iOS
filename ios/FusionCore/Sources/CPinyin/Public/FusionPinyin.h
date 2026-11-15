#ifndef FUSION_PINYIN_H
#define FUSION_PINYIN_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *fp_create(const char *dictionary, const char *user_dictionary);
void fp_destroy(void *p);
int fp_search(void *p, const char *text);
void fp_reset(void *p);
int fp_choose(void *p, int index);
int fp_cancel_choice(void *p);
int fp_candidate_count(void *p);
const uint16_t *fp_candidate(void *p, int index);
const char *fp_pinyin(void *p);
int fp_fixed_length(void *p);
int fp_fixed_pinyin_length(void *p);
int fp_fully_selected(void *p);
void fp_flush(void *p);
int fp_predict(void *p,const uint16_t *context);
const uint16_t *fp_prediction(void *p,int index);
#ifdef __cplusplus
}
#endif
#endif
