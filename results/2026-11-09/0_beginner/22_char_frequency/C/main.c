#include <ctype.h>
#include <stdio.h>

int main(void) {
    const char *sentence = "Peter Piper picked a peck of pickled peppers!";
    int counts[26] = {0};
    for (int i = 0; sentence[i]; i++) {
        unsigned char c = (unsigned char)sentence[i];
        if (isalpha(c)) counts[tolower(c) - 'a']++;
    }
    for (int i = 0; i < 26; i++)
        if (counts[i])
            printf("%c: %d\n", 'a' + i, counts[i]);
    return 0;
}
