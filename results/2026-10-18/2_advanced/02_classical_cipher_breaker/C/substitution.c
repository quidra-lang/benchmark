#include "cipher.h"

static int mod26(int value) {
    int remainder = value % 26;
    return remainder < 0 ? remainder + 26 : remainder;
}

char *substitute(Cipher cipher, const char *text, const char *key, bool decrypt) {
    char *result = malloc(strlen(text) + 1);
    if (!result)
        exit(EXIT_FAILURE);
    int a = 1, b = 0, inverse = 1;
    int key_length = (int)strlen(key);
    if (cipher == CAESAR)
        b = atoi(key);
    else if (cipher == AFFINE) {
        sscanf(key, "%d,%d", &a, &b);
        while (a * inverse % 26 != 1)
            ++inverse;
    }
    int previous[20] = {0};
    int letter_index = 0;
    size_t i = 0;
    for (; text[i]; ++i) {
        int x = letter_value(text[i]);
        if (x < 0) {
            result[i] = text[i];
            continue;
        }
        int y;
        if (cipher == CAESAR || cipher == AFFINE)
            y = decrypt ? mod26(inverse * (x - b)) : mod26(a * x + b);
        else {
            int slot = letter_index % key_length;
            int shift = cipher == VIGENERE || letter_index < key_length
                        ? key[slot] - 'A' : previous[slot];
            y = mod26(x + (decrypt ? -shift : shift));
            previous[slot] = decrypt ? y : x;
        }
        result[i] = (char)((text[i] >= 'a' && text[i] <= 'z' ? 'a' : 'A') + y);
        ++letter_index;
    }
    result[i] = '\0';
    return result;
}
