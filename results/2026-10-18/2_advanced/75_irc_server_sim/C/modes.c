#include "irc.h"
Changes channel_items(const char *mode, const Parsed *parameters, int first_argument) {
    Changes out = {0};
    char sign = '+';
    int position = first_argument;
    for (const char *p = mode; *p; ++p) {
        char c = *p;
        if (c == '+' || c == '-') {
            sign = c;
            continue;
        }
        Change item = {0};
        item.sign = sign;
        item.character = c;
        if (c == 'o' || c == 'v' || c == 'b' || c == 'k' || (c == 'l' && sign == '+')) {
            if (position < parameters->count) {
                item.has_argument = true;
                strcpy(item.argument, parameters->parameters[position++]);
            }
        }
        if (c == 'k' && sign == '-') {
            item.has_argument = true;
            strcpy(item.argument, "*");
        } else if (c == 'l' && sign == '+') {
            if (!item.has_argument || !digits(item.argument) || strlen(item.argument) > 4 ||
                atoi(item.argument) < 1)
                item.has_argument = false;
        }
        Changes_append(&out, item);
    }
    return out;
}
char *change_string(const Changes *changes) {
    size_t capacity = 2 * changes->count + 1;
    for (size_t i = 0; i < changes->count; ++i)
        if (changes->items[i].has_argument)
            capacity += strlen(changes->items[i].argument) + 1;
    char *out = malloc(capacity);
    size_t n = 0;
    char previous = 0;
    for (size_t i = 0; i < changes->count; ++i) {
        const Change *change = &changes->items[i];
        if (change->sign != previous) {
            out[n++] = change->sign;
            previous = change->sign;
        }
        out[n++] = change->character;
    }
    for (size_t i = 0; i < changes->count; ++i)
        if (changes->items[i].has_argument) {
            out[n++] = ' ';
            size_t size = strlen(changes->items[i].argument);
            memcpy(out + n, changes->items[i].argument, size);
            n += size;
        }
    out[n] = 0;
    return out;
}
