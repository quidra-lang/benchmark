#include <stdio.h>
#include <string.h>

int main(void) {
    const char *words[] = {"listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist",
        "earth", "onset", "heart", "tones"};
    int signatures[12][26] = {{0}};
    _Bool used[12] = {0};
    for (int i = 0; i < 12; i++)
        for (int j = 0; words[i][j]; j++)
            signatures[i][words[i][j] - 'a']++;
    for (int i = 0; i < 12; i++)
        if (!used[i]) {
            int first = 1;
            for (int j = i; j < 12; j++)
                if (!used[j] && memcmp(signatures[i], signatures[j], sizeof signatures[i]) == 0) {
                    printf("%s%s", first ? "" : " ", words[j]);
                    first = 0;
                    used[j] = 1;
                }
            putchar('\n');
        }
    return 0;
}
