#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *word;
    int count;
} Entry;
int compare(const void *a, const void *b) {
    const Entry *x = a, *y = b;
    if (x -> count != y -> count)
        return y -> count - x -> count;
    return strcmp(x -> word, y -> word);
}

int main(void) {
    char text[] = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
    for (int i = 0; text[i]; i++) {
        if (text[i] >= 'A' && text[i] <= 'Z')
            text[i] = (char)(text[i] - 'A' + 'a');
        else if (text[i] < 'a' || text[i] > 'z')
            text[i] = ' ';
    }
    Entry entries[64];
    int count = 0;
    for (char *w = strtok(text, " "); w; w = strtok(NULL, " ")) {
        int j = 0;
        while (j < count && strcmp(entries[j].word, w))
            j++;
        if (j == count) {
            entries[count].word = w;
            entries[count++].count = 0;
        }
        entries[j].count++;
    }
    qsort(entries, count, sizeof(Entry), compare);
    for (int i = 0; i < 5; i++)
        printf("%s: %d\n", entries[i].word, entries[i].count);
    printf("distinct words: %d\n", count);
    return 0;
}
