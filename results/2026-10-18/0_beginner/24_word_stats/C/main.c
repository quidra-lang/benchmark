#include <stdio.h>
#include <string.h>

int main(void) {
    char sentence[] = "we planted beans and carrots in the garden behind our old house";
    char *longest = NULL, *shortest = NULL;
    int count = 0, total = 0;
    for (char *w = strtok(sentence, " "); w; w = strtok(NULL, " ")) {
        int len = (int) strlen(w);
        count++;
        total += len;
        if (!longest || len > (int) strlen(longest))
            longest = w;
        if (!shortest || len < (int) strlen(shortest))
            shortest = w;
    }
    double avg = (double) total / count;
    int q = (int)(avg * 100 + 0.5);
    printf("words: %d\nlongest: %s\nshortest: %s\naverage length: %d.%02d\n", count, longest, shortest,
        q / 100, q % 100);
    return 0;
}
