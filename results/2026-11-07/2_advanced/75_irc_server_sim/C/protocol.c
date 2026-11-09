#include "irc.h"
static char folded(char c) {
    if (c >= 'A' && c <= 'Z')
        return (char)(c - 'A' + 'a');
    if (c == '[')
        return '{';
    if (c == ']')
        return '}';
    if (c == '\\')
        return '|';
    if (c == '^')
        return '~';
    return c;
}
void fold(const char *value, char *out) {
    while (*value)
        *out++ = folded(*value++);
    *out = 0;
}
bool rfc_equal(const char *a, const char *b) {
    while (*a && *b) {
        if (folded(*a++) != folded(*b++))
            return false;
    }
    return *a == *b;
}
bool digits(const char *value) {
    if (!*value)
        return false;
    while (*value) {
        if (*value < '0' || *value > '9')
            return false;
        ++value;
    }
    return true;
}
static bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
static bool special(char c) { return strchr("[]\\`_^{}|", c) != NULL; }
bool valid_nickname(const char *value) {
    if (!*value || (!letter(*value) && !special(*value)))
        return false;
    for (const char *p = value + 1; *p; ++p)
        if (!letter(*p) && !special(*p) && !(*p >= '0' && *p <= '9') && *p != '-')
            return false;
    return true;
}
bool valid_channel(const char *value, int maximum) {
    size_t length = strlen(value);
    return length >= 2 && length <= (size_t)maximum && value[0] == '#' &&
           strchr(value, ':') == NULL;
}
void parse(const char *raw, Parsed *out) {
    memset(out, 0, sizeof *out);
    const char *p = raw;
    if (*p == ':') {
        p = strchr(p, ' ');
        if (!p)
            return;
    }
    while (*p == ' ')
        ++p;
    int count = 0;
    while (*p && *p != ' ') {
        char c = *p++;
        out->command[count++] = (c >= 'a' && c <= 'z') ? (char)(c - 'a' + 'A') : c;
    }
    out->command[count] = 0;
    if (count == 0)
        return;
    while (*p) {
        while (*p == ' ')
            ++p;
        if (!*p)
            break;
        if (*p == ':') {
            strcpy(out->parameters[out->count++], p + 1);
            break;
        }
        if (out->count == 14) {
            strcpy(out->parameters[out->count++], p);
            break;
        }
        count = 0;
        while (*p && *p != ' ')
            out->parameters[out->count][count++] = *p++;
        out->parameters[out->count++][count] = 0;
    }
}
