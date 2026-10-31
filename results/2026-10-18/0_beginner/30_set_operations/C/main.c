#include <stdio.h>

int main(void) {
    int a[] = {12, 5, 8, 21, 5, 17, 3, 12, 9}, b[] = {8, 14, 21, 6, 14, 3, 25, 6};
    _Bool sa[26] = {0}, sb[26] = {0};
    for (int i = 0; i < 9; i++)
        sa[a[i]] = 1;
    for (int i = 0; i < 8; i++)
        sb[b[i]] = 1;
    const char *labels[] = {"union", "intersection", "difference", "symmetric difference"};
    for (int op = 0; op < 4; op++) {
        printf("%s:", labels[op]);
        for (int n = 0; n < 26; n++) {
            int keep = op == 0   ? (sa[n] || sb[n])
                       : op == 1 ? (sa[n] && sb[n])
                       : op == 2 ? (sa[n] && !sb[n])
                                 : (sa[n] != sb[n]);
            if (keep)
                printf(" %d", n);
        }
        putchar('\n');
    }
    return 0;
}
