#include <stdio.h>
#include <string.h>

int main(void) {
    const char *words[] = {"listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist",
        "earth", "onset", "heart", "tones"};
    int signatures[12][26] = {{0}};
    for (int i = 0; i < 12; i++)
        for (int j = 0; words[i][j]; j++)
            signatures[i][words[i][j] - 'a']++;
    int groups[12][12], lengths[12] = {0}, count = 0;
    for (int i = 0; i < 12; ++i) {
        int g = 0;
        while (g < count && memcmp(signatures[i], signatures[groups[g][0]], sizeof signatures[i]) != 0)
            ++g;
        if (g == count) ++count;
        groups[g][lengths[g]++] = i;
    }
    for (int g = 0; g < count; ++g) {
        for (int j = 0; j < lengths[g]; ++j)
            printf("%s%s", j ? " " : "", words[groups[g][j]]);
        putchar('\n');
    }
    return 0;
}
