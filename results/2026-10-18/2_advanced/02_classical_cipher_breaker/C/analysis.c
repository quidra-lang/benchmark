#include "cipher.h"
#include <stdint.h>

void letter_counts(const char *text, int counts[26]) {
    memset(counts, 0, 26 * sizeof(*counts));
    for (; *text; ++text)
        ++counts[*text - 'A'];
}

static int counts_ioc(const int counts[26], int length) {
    int64_t sum = 0;
    for (int i = 0; i < 26; ++i)
        sum += (int64_t)counts[i] * (counts[i] - 1);
    return length < 2 ? 0 : (int)(100000 * sum / ((int64_t)length * (length - 1)));
}

int index_of_coincidence(const char *text) {
    int counts[26];
    letter_counts(text, counts);
    return counts_ioc(counts, (int)strlen(text));
}

void column_indices(const char *text, int period, int *indices) {
    int length = (int)strlen(text);
    for (int column = 0; column < period; ++column) {
        int counts[26] = {0};
        int count = 0;
        for (int i = column; i < length; i += period) {
            ++counts[text[i] - 'A'];
            ++count;
        }
        indices[column] = counts_ioc(counts, count);
    }
}

static int gcd(int a, int b) {
    while (b) {
        int remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static int trigram_code(const char *text) {
    return (text[0] - 'A') * 676 + (text[1] - 'A') * 26 + text[2] - 'A';
}

Profile *analyze_periods(const char *text, int max_length) {
    Profile *profile = calloc(1, sizeof(*profile));
    int *counts = calloc(17576, sizeof(*counts));
    int *lookup = malloc(17576 * sizeof(*lookup));
    if (!profile || !counts || !lookup)
        exit(EXIT_FAILURE);
    int length = (int)strlen(text);
    profile->max_length = max_length;
    for (int i = 0; i + 2 < length; ++i)
        ++counts[trigram_code(text + i)];
    for (int code = 0; code < 17576; ++code)
        if (counts[code] >= 2)
            ++profile->repeat_count;
    if (profile->repeat_count) {
        profile->repeats = calloc((size_t)profile->repeat_count, sizeof(*profile->repeats));
        if (!profile->repeats)
            exit(EXIT_FAILURE);
    }
    int next = 0;
    for (int code = 0; code < 17576; ++code) {
        lookup[code] = -1;
        if (counts[code] >= 2) {
            lookup[code] = next;
            Repeat *repeat = &profile->repeats[next++];
            repeat->code = code;
            repeat->positions = malloc((size_t)counts[code] * sizeof(*repeat->positions));
            if (!repeat->positions)
                exit(EXIT_FAILURE);
        }
    }
    for (int i = 0; i + 2 < length; ++i) {
        int index = lookup[trigram_code(text + i)];
        if (index >= 0) {
            Repeat *repeat = &profile->repeats[index];
            repeat->positions[repeat->count++] = i + 1;
        }
    }
    for (int i = 0; i < profile->repeat_count; ++i) {
        Repeat *repeat = &profile->repeats[i];
        for (int j = 1; j < repeat->count; ++j) {
            int gap = repeat->positions[j] - repeat->positions[j - 1];
            repeat->gcd = gcd(repeat->gcd, gap);
            ++profile->gap_count;
            for (int period = 1; period <= max_length; ++period)
                if (gap % period == 0)
                    ++profile->kasiski[period];
        }
    }
    for (int period = 1; period <= max_length; ++period) {
        column_indices(text, period, profile->indices[period]);
        int sum = 0;
        for (int column = 0; column < period; ++column)
            sum += profile->indices[period][column];
        profile->averages[period] = sum / period;
    }
    free(counts);
    free(lookup);
    return profile;
}

void free_profile(Profile *profile) {
    if (!profile)
        return;
    for (int i = 0; i < profile->repeat_count; ++i)
        free(profile->repeats[i].positions);
    free(profile->repeats);
    free(profile);
}

void percentage(int count, int total, char *result) {
    int tenths = (2000 * count + total) / (2 * total);
    sprintf(result, "%d.%d", tenths / 10, tenths % 10);
}

static int compare_pairs(const void *left, const void *right) {
    const PairCount *a = left;
    const PairCount *b = right;
    if (a->count != b->count)
        return a->count > b->count ? -1 : 1;
    return (a->pair > b->pair) - (a->pair < b->pair);
}

int pair_counts(const char *text, bool aligned, PairCount result[676]) {
    int counts[676] = {0};
    int step = aligned ? 2 : 1;
    int length = (int)strlen(text);
    for (int i = 0; i + 1 < length; i += step) {
        char a = text[i], b = text[i + 1];
        if (aligned) {
            if (a == 'J')
                a = 'I';
            if (b == 'J')
                b = 'I';
        }
        ++counts[(a - 'A') * 26 + b - 'A'];
    }
    int count = 0;
    for (int pair = 0; pair < 676; ++pair)
        if (counts[pair])
            result[count++] = (PairCount){pair, counts[pair]};
    qsort(result, (size_t)count, sizeof(*result), compare_pairs);
    return count;
}
