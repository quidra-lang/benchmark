#include "irc.h"
bool matches(const char *mask, const char *value) {
    char pattern[512], text[512];
    fold(mask, pattern);
    fold(value, text);
    size_t p = 0, position = 0, restart = 0;
    int star = -1;
    while (text[position]) {
        if (pattern[p] == '*') {
            star = (int)p++;
            restart = position;
        } else if (pattern[p] && (pattern[p] == '?' || pattern[p] == text[position])) {
            ++p;
            ++position;
        } else if (star >= 0) {
            position = ++restart;
            p = (size_t)star + 1;
        } else
            return false;
    }
    while (pattern[p] == '*')
        ++p;
    return pattern[p] == 0;
}
void normalize(const char *argument, char out[406]) {
    bool bang = strchr(argument, '!') != NULL, at = strchr(argument, '@') != NULL;
    if (bang && at)
        strcpy(out, argument);
    else if (at)
        snprintf(out, 406, "*!%s", argument);
    else if (bang)
        snprintf(out, 406, "%s@*", argument);
    else if (strchr(argument, '.'))
        snprintf(out, 406, "*!*@%s", argument);
    else
        snprintf(out, 406, "%s!*@*", argument);
}
