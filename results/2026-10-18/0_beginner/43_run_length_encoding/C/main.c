#include <stdio.h>

int main(void) {
    const char *values[] = {"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",
        "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"};
    for (int k = 0; k < 5; k++) {
        const char *s = values[k];
        char encoded[256], decoded[256];
        int e = 0;
        for (int i = 0; s[i];) {
            int j = i + 1;
            while (s[j] && s[j] == s[i])
                j++;
            e += sprintf(encoded + e, "%d%c", j - i, s[i]);
            i = j;
        }
        int d = 0;
        for (int i = 0; encoded[i];) {
            int count = 0;
            while (encoded[i] >= '0' && encoded[i] <= '9')
                count = count * 10 + encoded[i++] - '0';
            char c = encoded[i++];
            while (count--)
                decoded[d++] = c;
        }
        decoded[d] = '\0';
        printf("%s -> %s -> %s\n", s, encoded, decoded);
    }
    return 0;
}
