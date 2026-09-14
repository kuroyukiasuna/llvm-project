int LICM(int scale_factor, int data[]) {
    int adjusted_value = 0;
    for (int i = 0; i < 4; i++) {
        adjusted_value += data[i] + (scale_factor * 5);
    }
    return  adjusted_value;
}

int main() {
    int data[] = {1, 2, 3, 4};
    return LICM(7, data);
}