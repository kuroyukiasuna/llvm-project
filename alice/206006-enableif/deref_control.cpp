// Controls that isolate dereferenceability as the single variable.
// Every function here is the same early-exit search; they differ only in
// whether LV can prove the searched load is dereferenceable for the whole
// (symbolic max) trip count, and in the manual unroll factor.

int arr[1024];

// (1) deref provable, unit stride  -> vectorizes today (VF=8)
int g_plain(int v) {
  for (int i = 0; i < 1024; ++i)
    if (arr[i] == v) return i;
  return -1;
}

// (2) deref provable, 4x manually unrolled (libstdc++ shape) -> vectorizes today (VF=4)
int g_unrolled4(int v) {
  for (int i = 0; i < 1024; i += 4) {
    if (arr[i + 0] == v) return i + 0;
    if (arr[i + 1] == v) return i + 1;
    if (arr[i + 2] == v) return i + 2;
    if (arr[i + 3] == v) return i + 3;
  }
  return -1;
}

// (3) deref NOT provable, unit stride  -> scalar (this is std::find_if)
int p_plain(const int *p, int n, int v) {
  for (int i = 0; i < n; ++i)
    if (p[i] == v) return i;
  return -1;
}

// (4) deref NOT provable, 4x unrolled -> scalar
// (n & ~3 keeps the latch countable, so this differs from (3) only in stride)
int p_unrolled4(const int *p, int n, int v) {
  for (int i = 0, m = n & ~3; i < m; i += 4) {
    if (p[i + 0] == v) return i + 0;
    if (p[i + 1] == v) return i + 1;
    if (p[i + 2] == v) return i + 2;
    if (p[i + 3] == v) return i + 3;
  }
  return -1;
}
