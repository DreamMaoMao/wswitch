/* src/data.c - Data structures for wswitch Switcher */
#include "data.h"
#include <stdlib.h>
#include <string.h>

#define INITIAL_CAPACITY 32

void app_state_init(AppState *state) {
  state->windows = NULL;
  state->count = 0;
  state->capacity = 0;
  state->selected_index = 0;
  state->width = 200; /* Default safe size */
  state->height = 100;
}
int app_state_add(AppState *state, WindowInfo *info) {
  if (state->count >= state->capacity) {
    int new_cap = state->capacity == 0 ? INITIAL_CAPACITY : state->capacity * 2;
    WindowInfo *new_ptr = realloc(state->windows, new_cap * sizeof(WindowInfo));
    if (!new_ptr)
      return -1;
    state->windows = new_ptr;
    state->capacity = new_cap;
  }
  state->windows[state->count++] = *info;
  return 0;
}
void app_state_free(AppState *state) {
  if (state) {
    if (state->windows) {
      for (int i = 0; i < state->count; i++) {
        window_info_free(&state->windows[i]);
      }
      free(state->windows);
    }
    state->windows = NULL;
    state->count = 0;
    state->capacity = 0;
  }
}
void window_info_free(WindowInfo *info) {
  if (info) {
    free(info->address);
    free(info->title);
    free(info->class_name);
    memset(info, 0, sizeof(WindowInfo));
  }
}