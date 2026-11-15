#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *fl_create(const char *dictionary);
void fl_destroy(void *handle);
void fl_set_history(void *handle,const char *path,const char *locale);
void fl_flush(void *handle);
int fl_probability(void *handle,const int32_t *word,int count);
void fl_learn(void *handle,const int32_t *word,int count,const int32_t *previous,int previous_count,int is_valid,int occurrences);
void fl_forget(void *handle,const int32_t *word,int count);
int fl_suggest(void *handle,const int32_t *word,int count,const int32_t *previous,int previous_count);
const int32_t *fl_candidate(void *handle,int index);
int fl_score(void *handle,int index);
int fl_whitelisted(void *handle,int index);
int fl_autocorrection(void *handle,const int32_t *word,int count,float threshold);
#ifdef __cplusplus
}
#endif
