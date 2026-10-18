#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    const char *expressions[] = {"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",
        "4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"};
    for (int k = 0; k < 7; k++) {
        char text[128];
        strcpy(text, expressions[k]);
        long long stack[64];
        int top = 0;
        const char *error = NULL;
        for (char *token = strtok(text, " "); token; token = strtok(NULL, " ")) {
            if (strlen(token) == 1 && strchr("+-*/", token[0])) {
                if (top < 2) {
                    error = "stack underflow";
                    break;
                }
                long long b = stack[--top], a = stack[--top], v = 0;
                if (token[0] == '/' && b == 0) {
                    error = "division by zero";
                    break;
                }
                switch (token[0]) {
                    case '+':
                        v = a + b;
                        break;
                    case '-':
                        v = a - b;
                        break;
                    case '*':
                        v = a * b;
                        break;
                    case '/':
                        v = a / b;
                        break;
                }
                stack[top++] = v;
            } else
                stack[top++] = strtoll(token, NULL, 10);
        }
        if (!error && top != 1)
            error = "leftover operands";
        if (error)
            printf("%s => error: %s\n", expressions[k], error);
        else
            printf("%s => %lld\n", expressions[k], stack[0]);
    }
    return 0;
}
