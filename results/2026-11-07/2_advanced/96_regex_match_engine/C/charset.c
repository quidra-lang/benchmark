#include "regex.h"
int swap_case(int c) {
    if (c >= 'a' && c <= 'z') return c - 'a' + 'A';
    if (c >= 'A' && c <= 'Z') return c - 'A' + 'a';
    return c;
}
int word_character(int c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}
Charset predefined(int c) {
    Charset s = {
        {
            0
        }
    };
    int lower = tolower((unsigned char)c);
    for (int k = 0; k < 128; ++k) {
        int yes = lower == 'd' ? k >= '0' && k <= '9' : lower == 'w' ? word_character(k) : k == 9 || k == 10 || k == 11 || k == 12 || k == 13 || k == 32;
        s.bit[k] = (unsigned char)(isupper((unsigned char)c) ? !yes : yes);
    }
    return s;
}
int equal_character(const Pattern *p, int a, int b) {
    return a == b || (p->insensitive && swap_case(a) == b);
}
int class_character(const Pattern *p, Charset s, int neg, int c) {
    int yes = s.bit[c] || (p->insensitive && s.bit[swap_case(c)]);
    return yes != neg;
}
int assertion(const Pattern *p, int kind, const char *s, int n, int q) {
    if (kind == A_BOL) return q == 0 || (p->multiline && s[q-1] == '\n');
    if (kind == A_EOL) return q == n || (p->multiline && s[q] == '\n');
    int a = q > 0 && word_character((unsigned char)s[q-1]);
    int b = q < n && word_character((unsigned char)s[q]);
    return kind == A_WORD ? a != b : a == b;
}
int consumes(const Pattern *p, const Instruction *i, const char *s, int n, int q) {
    if (q >= n) return 0;
    int c = (unsigned char)s[q];
    if (i->op == I_CHAR) return equal_character(p, c, i->x);
    if (i->op == I_ANY) return p->dotall || c != '\n';
    return class_character(p, i->set, i->neg, c);
}
