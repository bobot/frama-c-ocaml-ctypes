#include <stdint.h>

typedef struct
{
    int t;
    float f;
    int64_t i64;
} bar_struct;

int max_value = 15;

void foo(void);

int bar(int x){
  return x;
}