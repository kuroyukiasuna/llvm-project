// libc++ shape: plain early-exit loop
int *find_simple(int *first, int *last, int v) {
  for (; first != last; ++first)
    if (*first == v) return first;
  return last;
}
// libstdc++ shape: manually 4x unrolled while loop
int *find_unrolled4(int *first, int *last, int v) {
  for (long n = (last - first) >> 2; n > 0; --n) {
    if (*first == v) return first; ++first;
    if (*first == v) return first; ++first;
    if (*first == v) return first; ++first;
    if (*first == v) return first; ++first;
  }
  switch (last - first) {
  case 3: if (*first == v) return first; ++first; [[fallthrough]];
  case 2: if (*first == v) return first; ++first; [[fallthrough]];
  case 1: if (*first == v) return first; ++first; [[fallthrough]];
  case 0: default: return last;
  }
}
// bool-only variant (no live-out index)
bool any_eq(const int *first, const int *last, int v) {
  for (; first != last; ++first)
    if (*first == v) return true;
  return false;
}
