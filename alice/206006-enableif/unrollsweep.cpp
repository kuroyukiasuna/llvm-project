int *u1(int *f, int *l, int v) {                      // plain
  for (; f != l; ++f) if (*f == v) return f;
  return l;
}
int *u2(int *f, int *l, int v) {                      // 2x unrolled
  for (long n = (l - f) >> 1; n > 0; --n) {
    if (*f == v) return f; ++f;
    if (*f == v) return f; ++f;
  }
  for (; f != l; ++f) if (*f == v) return f;
  return l;
}
int *u4(int *f, int *l, int v) {                      // 4x unrolled (libstdc++ shape)
  for (long n = (l - f) >> 2; n > 0; --n) {
    if (*f == v) return f; ++f;
    if (*f == v) return f; ++f;
    if (*f == v) return f; ++f;
    if (*f == v) return f; ++f;
  }
  for (; f != l; ++f) if (*f == v) return f;
  return l;
}
