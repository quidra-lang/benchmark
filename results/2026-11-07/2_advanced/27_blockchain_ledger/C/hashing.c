#include "ledger.h"
char *digest(const char *text) {
    const Integer bases[] = {1000003, 1500007, 2750159, 4194301}, initial[] = {11, 23, 37, 53};
    char *result = malloc(33);
    size_t length = strlen(text);
    for (int lane = 0; lane < 4; ++lane) {
        Integer value = initial[lane];
        for (size_t i = 0; i < length; ++i)
            value = (value * bases[lane] + (unsigned char)text[i]) % 2147483647;
        value = (value * bases[lane] + (Integer)length) % 2147483647;
        value = value * bases[lane] % 2147483647;
        value = value * bases[lane] % 2147483647;
        snprintf(result + lane * 8, 9, "%08" PRIx64, (uint64_t)value);
    }
    return result;
}
char *merkle(char **ids, int count) {
    char **values = malloc((size_t)(count + 1) * sizeof *values);
    memcpy(values, ids, (size_t)count * sizeof *values);
    while (count > 1) {
        if (count % 2) {
            values[count] = values[count - 1];
            ++count;
        }
        for (int i = 0; i < count; i += 2)
            values[i / 2] = digest(format("%s%s", values[i], values[i + 1]));
        count /= 2;
    }
    char *result = values[0];
    free(values);
    return result;
}
char *short_hash(const char *hash) {
    char *result = malloc(9);
    memcpy(result, hash, 8);
    result[8] = 0;
    return result;
}
