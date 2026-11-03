#include <stdio.h>

int main(void) {
    int a[] = {52, 17, 38, 9, 61, 38, 24, 45}, total = 0;
    for (int i = 1; i < 8; i++) {
        int v = a[i], j = i, shifts = 0;
        while (j > 0 && a[j - 1] > v) {
            a[j] = a[j - 1];
            j--;
            shifts++;
        }
        a[j] = v;
        total += shifts;
        printf("i=%d shifts=%d:", i, shifts);
        for (int k = 0; k < 8; k++)
            printf(" %d", a[k]);
        putchar('\n');
    }
    printf("total shifts: %d\n", total);
    return 0;
}
