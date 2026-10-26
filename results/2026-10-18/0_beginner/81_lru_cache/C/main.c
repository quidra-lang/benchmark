#include <stdio.h>

int main(void) {
    const char *accesses = "BACBDABEADDCAEB";
    char cache[3];
    int length = 0, hits = 0, misses = 0;
    for (int k = 0; accesses[k]; k++) {
        char key = accesses[k], evicted = 0;
        int position = 0;
        while (position < length && cache[position] != key)
            position++;
        int hit = position < length;
        if (hit) {
            hits++;
            for (int j = position; j < length - 1; j++)
                cache[j] = cache[j + 1];
            length--;
        } else {
            misses++;
            if (length == 3)
                evicted = cache[--length];
        }
        for (int j = length; j > 0; j--)
            cache[j] = cache[j - 1];
        cache[0] = key;
        length++;
        printf("%c: %s", key, hit ? "hit" : "miss");
        if (evicted)
            printf(", evict %c", evicted);
        printf(" [");
        for (int j = 0; j < length; j++)
            printf("%s%c", j ? " " : "", cache[j]);
        puts("]");
    }
    printf("hits: %d misses: %d\n", hits, misses);
    return 0;
}
