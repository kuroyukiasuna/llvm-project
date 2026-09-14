#include <stdint.h>
#include <stdlib.h>

#define BITCAST(DST_TYPE, SRC_TYPE, VALUE)                                     \
    (union {                                                                   \
        SRC_TYPE src;                                                          \
        DST_TYPE dst                                                           \
    }){ VALUE }                                                                \
        .dst
typedef uint16_t v4u16 __attribute__((vector_size(8)));
uint32_t g1 = 1662431956;
_Bool g19, f29_c9;
uint16_t g30;
int main()
{
    v4u16 bc4 = { 0, 13133 };
    uint64_t ov7;
    uint16_t v10 = 24726;
    int32_t __ov_tmp_g25;
lbl_b59:
    g30 = __builtin_bswap16(v10);
    bc4 = __builtin_shufflevector(bc4, bc4, 0, 7, 6, 1);
    ov7 = BITCAST(uint64_t, v4u16, bc4);
    bc4[0] = g30;
    if (__builtin_clzll(ov7) == 2)
    {
        f29_c9;
        goto lbl_br68;
    }
    abort();
lbl_br68:
    v10 = bc4[__builtin_add_overflow(g1, g1, &__ov_tmp_g25) ? 0 : g30];
    g19 = 0 >= (int16_t)v10;
    v10 = 36918 + v10;
    switch (v10)
    {
        case 9878:
        case 26065: return 0;
        default: goto lbl_b59;
    }
    
}