#include <stdint.h>

#ifndef BAR_H
#define BAR_H

typedef struct
{
    int t;
    float f;
    int64_t i64;
} bar_struct;

static int max_value = 15;

void foo(void);

static int bar(int x){
  return x;
}

void init_bar(bar_struct *b);
void clear_bar(bar_struct *b);

#endif