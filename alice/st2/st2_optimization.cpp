void single_loop(const float* __restrict src, float* __restrict dst, unsigned n) {
    float* pA = dst;
    float* pB = dst + 1;

    //std::cout << *pA << " " << *pB << "\n";

    for (unsigned i = 0; i < n; i++) {
        *pA = src[i] * 2.0f;
        *pB = src[i] * 3.0f;
        pA += 2;
        pB += 2;
    }
}

void nested_loop(const float* __restrict src, float* __restrict dst,
                 unsigned width, unsigned height, unsigned srcStride) {
    float* pA = dst;
    float* pB = dst + 1;
    for (unsigned y = 0; y < height; y++) {
        const float* row = src + y * srcStride;
        for (unsigned x = 0; x < width; x++) {
            *pA = row[x] * 2.0f;
            *pB = row[x] * 3.0f;
            pA += 2;
            pB += 2;
        }
    }
}

/*
int main() {
    float *src = new float[4];
    float *dst = new float[8];

    src[0] = 1.1f;
    src[1] = 2.2f;
    src[2] = 3.3f;
    src[3] = 4.4f;

    dst[0] = 0;
    dst[1] = 0;
    dst[2] = 0;
    dst[3] = 0;
    dst[4] = 0;
    dst[5] = 0;
    dst[6] = 0;
    dst[7] = 0;

    single_loop(src, dst, 4);

    for (unsigned i = 0; i < 8; i++) {
        std::cout << dst[i] << "\n";
    }

    return 0;
}*/