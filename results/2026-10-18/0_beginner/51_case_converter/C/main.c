#include <stdio.h>
#include <string.h>

int main(void) {
    const char *ids[] = {"user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
        "isEmailAddressValid"};
    for (int k = 0; k < 6; k++) {
        char words[8][64] = {{0}};
        int count = 0, len = 0;
        const char *s = ids[k];
        for (int i = 0;; i++) {
            char c = s[i];
            if (c == 0 || c == '_' || c == '-' || (c >= 'A' && c <= 'Z')) {
                if (len) {
                    words[count++][len] = 0;
                    len = 0;
                }
                if (c == 0)
                    break;
                if (c == '_' || c == '-')
                    continue;
            }
            if (c >= 'A' && c <= 'Z')
                c = (char)(c - 'A' + 'a');
            words[count][len++] = c;
        }
        char snake[256] = "", camel[256] = "", pascal[256] = "", kebab[256] = "";
        for (int i = 0; i < count; i++) {
            if (i) {
                strcat(snake, "_");
                strcat(kebab, "-");
            }
            strcat(snake, words[i]);
            strcat(kebab, words[i]);
            char cap[64];
            strcpy(cap, words[i]);
            cap[0] = (char)(cap[0] - 'a' + 'A');
            strcat(pascal, cap);
            strcat(camel, i ? cap: words[i]);
        }
        printf("%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n", s, snake, camel, pascal, kebab);
    }
    return 0;
}
