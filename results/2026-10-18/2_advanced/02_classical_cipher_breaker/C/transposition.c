#include "cipher.h"

int rail_number(int position, int rails) {
    int cycle = 2 * rails - 2;
    int offset = position % cycle;
    return offset < cycle - offset ? offset : cycle - offset;
}

char *rail_fence(const char *text, int rails, bool decrypt) {
    size_t length = strlen(text);
    char *result = malloc(length + 1);
    if (!result)
        exit(EXIT_FAILURE);
    size_t next = 0;
    for (int rail = 0; rail < rails; ++rail)
        for (size_t i = 0; i < length; ++i)
            if (rail_number((int)i, rails) == rail) {
                if (decrypt)
                    result[i] = text[next++];
                else
                    result[next++] = text[i];
            }
    result[length] = '\0';
    return result;
}

void column_ranks(const char *key, int ranks[9]) {
    int length = (int)strlen(key);
    for (int i = 0; i < length; ++i) {
        ranks[i] = 1;
        for (int j = 0; j < length; ++j)
            if (key[j] < key[i] || (key[j] == key[i] && j < i))
                ++ranks[i];
    }
}

void rank_string(const char *key, char *result) {
    int ranks[9];
    column_ranks(key, ranks);
    size_t length = strlen(key);
    for (size_t i = 0; i < length; ++i)
        result[i] = (char)('0' + ranks[i]);
    result[length] = '\0';
}

char *columnar(const char *text, const char *key, bool decrypt) {
    size_t length = strlen(text);
    int width = (int)strlen(key);
    int ranks[9];
    column_ranks(key, ranks);
    char *result = malloc(length + 1);
    if (!result)
        exit(EXIT_FAILURE);
    size_t next = 0;
    for (int rank = 1; rank <= width; ++rank)
        for (int column = 0; column < width; ++column)
            if (ranks[column] == rank)
                for (size_t i = (size_t)column; i < length; i += (size_t)width) {
                    if (decrypt)
                        result[i] = text[next++];
                    else
                        result[next++] = text[i];
                }
    result[length] = '\0';
    return result;
}
