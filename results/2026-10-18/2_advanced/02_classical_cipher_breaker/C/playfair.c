#include "cipher.h"

void playfair_square(const char *key, char square[26]) {
    bool seen[26] = {false};
    const char *parts[] = {key, "ABCDEFGHIKLMNOPQRSTUVWXYZ"};
    int next = 0;
    for (int part = 0; part < 2; ++part)
        for (const char *p = parts[part]; *p; ++p) {
            char c = *p == 'J' ? 'I' : *p;
            if (!seen[c - 'A']) {
                seen[c - 'A'] = true;
                square[next++] = c;
            }
        }
    square[next] = '\0';
}

bool valid_playfair(const char *text) {
    size_t length = strlen(text);
    if (length % 2 != 0)
        return false;
    for (size_t i = 0; i < length; i += 2) {
        char a = text[i] == 'J' ? 'I' : text[i];
        char b = text[i + 1] == 'J' ? 'I' : text[i + 1];
        if (a == b)
            return false;
    }
    return true;
}

char *playfair_prepare(const char *text) {
    size_t length = strlen(text);
    char *result = malloc(2 * length + 1);
    if (!result)
        exit(EXIT_FAILURE);
    size_t next = 0;
    for (size_t i = 0; i < length;) {
        char a = text[i] == 'J' ? 'I' : text[i];
        char b = i + 1 < length ? text[i + 1] : '\0';
        if (b == 'J')
            b = 'I';
        result[next++] = a;
        if (b && a != b) {
            result[next++] = b;
            i += 2;
        } else {
            result[next++] = a == 'X' ? 'Q' : 'X';
            ++i;
        }
    }
    result[next] = '\0';
    return result;
}

char *playfair_transform(const char *text, const char *key, bool decrypt) {
    char square[26];
    int positions[26];
    playfair_square(key, square);
    for (int i = 0; i < 25; ++i)
        positions[square[i] - 'A'] = i;
    positions['J' - 'A'] = positions['I' - 'A'];
    char *result;
    if (decrypt) {
        result = malloc(strlen(text) + 1);
        if (!result)
            exit(EXIT_FAILURE);
        strcpy(result, text);
    } else
        result = playfair_prepare(text);
    int step = decrypt ? 4 : 1;
    for (size_t i = 0; result[i]; i += 2) {
        int a = positions[result[i] - 'A'];
        int b = positions[result[i + 1] - 'A'];
        int ra = a / 5, ca = a % 5;
        int rb = b / 5, cb = b % 5;
        if (ra == rb) {
            ca = (ca + step) % 5;
            cb = (cb + step) % 5;
        } else if (ca == cb) {
            ra = (ra + step) % 5;
            rb = (rb + step) % 5;
        } else {
            int temporary = ca;
            ca = cb;
            cb = temporary;
        }
        result[i] = square[5 * ra + ca];
        result[i + 1] = square[5 * rb + cb];
    }
    return result;
}
