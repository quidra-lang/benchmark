#include <stdio.h>

int main(void) {
    const char *phrases[] = {"Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
        "Step on no pets.", "No lemon, no melon"};
    for (int k = 0; k < 6; k++) {
        char clean[128];
        int len = 0;
        for (int i = 0; phrases[k][i]; i++) {
            char c = phrases[k][i];
            if (c >= 'A' && c <= 'Z')
                c = (char)(c - 'A' + 'a');
            if (c >= 'a' && c <= 'z')
                clean[len++] = c;
        }
        int yes = 1;
        for (int i = 0; i < len / 2; i++)
            if (clean[i] != clean[len - 1 - i])
                yes = 0;
        printf("%s -> %s\n", phrases[k], yes ? "yes": "no");
    }
    return 0;
}
