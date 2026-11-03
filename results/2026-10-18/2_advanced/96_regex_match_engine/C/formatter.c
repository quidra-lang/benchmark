#include "regex.h"
void quote(FILE *f, const char *s, size_t n) {
    fputc('"', f);
    for (size_t k = 0; k < n; ++k) {
        if (s[k] == '\\' || s[k] == '"') {
            fputc('\\', f);
            fputc(s[k], f);
        }
        else if (s[k] == '\n') fputs("\\n", f);
        else if (s[k] == '\t') fputs("\\t", f);
        else fputc(s[k], f);
    }
    fputc('"', f);
}
void display_character(FILE *f, int c) {
    if (c >= 33 && c <= 126 && c != '\\' && c != ']' && c != '^' && c != '-') fputc(c, f);
    else fprintf(f, "\\x%02X", c);
}
void display_set(FILE *f, Charset s, int neg) {
    fputc('[', f);
    if (neg) fputc('^', f);
    for (int a = 0; a < 128; ++a) if (s.bit[a]) {
        int b = a;
        while (b + 1 < 128 && s.bit[b+1]) ++b;
        display_character(f, a);
        if (b > a) {
            if (b > a + 1) fputc('-', f);
            display_character(f, b);
        }
        a = b;
    }
    fputc(']', f);
}
void display_instruction(FILE *f, Instruction i) {
    static const char *asserts[] = {
        "BOL", "EOL", "WORD", "NOTWORD"
    };
    static const char *looks[] = {
        "AHEAD", "NOT", "ATOMIC"
    };
    switch (i.op) {
        case I_CHAR: fputs("CHAR ", f);
        display_character(f, i.x);
        break;
        case I_ANY: fputs("ANY", f);
        break;
        case I_CLASS: fputs("CLASS ", f);
        display_set(f, i.set, i.neg);
        break;
        case I_SPLIT: fprintf(f, "SPLIT %d, %d", i.x, i.y);
        break;
        case I_JMP: fprintf(f, "JMP %d", i.x);
        break;
        case I_SAVE: fprintf(f, "SAVE %d", i.x);
        break;
        case I_ASSERT: fprintf(f, "ASSERT %s", asserts[i.kind]);
        break;
        case I_BACKREF: fprintf(f, "BACKREF %d", i.x);
        break;
        case I_LOOK: fprintf(f, "LOOK %s %d", looks[i.kind], i.x);
        break;
        default: fputs("MATCH", f);
        break;
    }
}
