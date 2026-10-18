#include <stdio.h>
#include <string.h>

int main(void) {
    char sentence[] = "every program starts with a single line";
    const size_t length = strlen(sentence);
    for (size_t i = length; i > 0; --i) putchar(sentence[i - 1]);
    putchar('\n');
    char *words[7];
    int count = 0;
    for (char *word = strtok(sentence, " "); word != NULL; word = strtok(NULL, " ")) {
        words[count++] = word;
    }
    for (int i = count - 1; i >= 0; --i) {
        if (i != count - 1) putchar(' ');
        fputs(words[i], stdout);
    }
    putchar('\n');
    return 0;
}
