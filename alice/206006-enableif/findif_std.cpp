// The real thing, against whatever libc++/libstdc++ is in scope.
// Host build (macOS => libc++). Compare against findif.cpp's hand-written shapes.
#include <algorithm>
int *find_std(int *first, int *last, int v) {
  return std::find_if(first, last, [v](int x) { return x == v; });
}
bool any_std(const int *first, const int *last, int v) {
  return std::any_of(first, last, [v](int x) { return x == v; });
}
