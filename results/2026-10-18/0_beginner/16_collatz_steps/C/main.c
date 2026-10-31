#include <stdio.h>

int main(void) {
    long long starts[] = {1, 6, 27, 97, 871};
    for (int i = 0; i < 5; i++) {
        long long n = starts[i], m = n, k = 0;
        while (n != 1) {
            n = n % 2 == 0 ? n / 2 : 3 * n + 1;
            k++;
            if (n > m)
                m = n;
        }
        printf("%lld: steps=%lld max=%lld\n", starts[i], k, m);
    }
    return 0;
}
