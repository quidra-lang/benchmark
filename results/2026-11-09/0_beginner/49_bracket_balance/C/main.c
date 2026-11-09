#include <stdio.h>
#include <string.h>

int main(void) {
    const char *values[] = {"(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3",
        "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"};
    for (int k = 0; k < 7; k++) {
        const char *s = values[k];
        char stack[128];
        int top = 0, error = -1, len = (int)strlen(s);
        for (int i = 0; i < len; i++) {
            char c = s[i];
            if (c == '(' || c == '[' || c == '{') {
                stack[top++] = c;
            } else if (c == ')' || c == ']' || c == '}') {
                char expected = c == ')' ? '(' : c == ']' ? '[' : '{';
                if (!top || stack[top - 1] != expected) {
                    error = i;
                    break;
                }
                top--;
            }
        }
        if (error < 0 && top)
            error = len;
        if (error < 0)
            printf("%s -> balanced\n", s);
        else
            printf("%s -> error at index %d\n", s, error);
    }
    return 0;
}
