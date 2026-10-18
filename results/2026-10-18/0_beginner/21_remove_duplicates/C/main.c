#include <stdio.h>

int main(void) {
    int values[] = {12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9}, unique[15], count = 0;
    for (int i = 0; i < 15; i++) {
        int seen = 0;
        for (int j = 0; j < count; j++)
            if (unique[j] == values[i])
                seen = 1;
        if (!seen)
            unique[count++] = values[i];
    }
    for (int i = 0; i < count; i++)
        printf("%s%d", i ? " ": "", unique[i]);
    printf("\nremoved: %d\n", 15 - count);
    return 0;
}
