#include <stdio.h>
#include <string.h>

int main(void) {
    enum { width = 30 };
    char paragraph[] = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.";
    char *words[100];
    int count = 0;
    for (char *w = strtok(paragraph, " "); w; w = strtok(NULL, " "))
        words[count++] = w;
    for (int start = 0; start < count;) {
        int end = start, letters = 0;
        while (end < count && letters + (int)strlen(words[end]) + end - start <= width) {
            letters += (int)strlen(words[end]);
            end++;
        }
        int gaps = end - start - 1, last = end == count;
        char line[width + 1];
        memset(line, ' ', width);
        line[width] = 0;
        int pos = 0;
        for (int i = start; i < end; i++) {
            int length = (int)strlen(words[i]);
            memcpy(line + pos, words[i], length);
            pos += length;
            if (i < end - 1) {
                int spaces = last || gaps == 0 ? 1 : (width - letters) / gaps + ((i - start) < (width - letters) % gaps);
                pos += spaces;
            }
        }
        printf("|%s|\n", line);
        start = end;
    }
    return 0;
}
