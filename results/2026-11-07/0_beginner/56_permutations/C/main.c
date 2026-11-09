#include <stdio.h>

void search(int depth, char *p, _Bool *used, int *count) {
    if (depth == 4) {
        printf("%d: %s\n", ++*count, p);
        return;
    }
    for (int i = 0; i < 4; i++)
        if (!used[i]) {
            used[i] = 1;
            p[depth] = (char)('A' + i);
            search(depth + 1, p, used, count);
            used[i] = 0;
        }
}

int main(void) {
    char permutation[5] = {0};
    _Bool used[4] = {0};
    int count = 0;
    search(0, permutation, used, &count);
    return 0;
}
