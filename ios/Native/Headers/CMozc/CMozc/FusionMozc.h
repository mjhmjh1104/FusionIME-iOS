#ifndef FUSION_MOZC_H
#define FUSION_MOZC_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void *fm_create(const char *data_path, const char *profile_path);
void fm_destroy(void *engine);
int fm_configure(void *engine, const char *layout, int learning);
int fm_key(void *engine, const char *text);
int fm_special(void *engine, int key); /* 0 backspace, 1 space, 2 enter, 3 left, 4 right */
int fm_command(void *engine, int command, int argument, const char *text);
/* Commands: 0 reset, 1 submit, 2 submit candidate, 3 forget candidate,
   4 reverse conversion, 5 stop toggling, 6 clear history, 7 import dictionary,
   8 focus candidate, 9 move composition cursor. */
const char *fm_preedit(void *engine);
const char *fm_committed(void *engine);
int fm_cursor(void *engine);
int fm_candidate_count(void *engine);
int fm_candidate_id(void *engine, int index);
const char *fm_candidate_text(void *engine, int index);
const char *fm_candidate_reading(void *engine, int index);
const char *fm_candidate_annotation(void *engine, int index);
int fm_candidate_focused(void *engine, int index);
const char *fm_error(void);
#ifdef __cplusplus
}
#endif
#endif
