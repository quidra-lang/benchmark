#include <stdio.h>

void cipher(char *s, int shift) {
    for (int i = 0; s[i]; i++) {
        char c = s[i];
        if (c >= 'a' && c <= 'z')
            s[i] = (char)('a' + (c - 'a' + shift) % 26);
        else if (c >= 'A' && c <= 'Z')
            s[i] = (char)('A' + (c - 'A' + shift) % 26);
    }
}

int main(void) {
    char message[] = "Zoe, meet Max by the Old Bridge at six!";
    cipher(message, 3);
    puts(message);
    cipher(message, 23);
    puts(message);
    return 0;
}
