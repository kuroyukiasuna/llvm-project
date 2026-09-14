int main() {
    int calculate_until = 10;
    int x0 = 0, x1 = 1;
    for (int i = 0; i < calculate_until; i++) {
        int next = x0 + x1;
        if (i % 2 == 0) {
            x0 = next;
        } else {
            x1 = next;
        }
    }
    return calculate_until % 2 == 0 ? x0 : x1;
}