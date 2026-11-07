#include <stdio.h>

int gcd(int a, int b) {
    while (b) {
        int r = a % b;
        a = b;
        b = r;
    }
    return a;
}

int main(void) {
    int pairs[][2] = {{48, 180}, {1071, 462}, {7, 91}, {13, 97}, {36288, 98280}};
    for (int i = 0; i < 5; i++) {
        int a = pairs[i][0], b = pairs[i][1], g = gcd(a, b), l = a / g * b;
        printf("gcd(%d, %d) = %d, lcm(%d, %d) = %d\n", a, b, g, a, b, l);
    }
    return 0;
}
