#include "phylogeny.h"
int base_index(char c) {
    static const char bases[] = "ACGT";
    const char *found = strchr(bases, c);
    return found ? (int)(found - bases) : -1;
}
unsigned base_set(char c) {
    switch (c) {
    case 'A':
        return 1;
    case 'C':
        return 2;
    case 'G':
        return 4;
    case 'T':
        return 8;
    case 'R':
        return 5;
    case 'Y':
        return 10;
    case 'S':
        return 6;
    case 'W':
        return 9;
    case 'K':
        return 12;
    case 'M':
        return 3;
    case 'B':
        return 14;
    case 'D':
        return 13;
    case 'H':
        return 11;
    case 'V':
        return 7;
    case 'N':
    case '-':
        return 15;
    default:
        return 0;
    }
}
Records read_fasta(void) {
    Records out = {0};
    FILE *in = fopen("input/alignment.fasta", "r");
    char *value;
    int number = 0;
    Text sequence = {0};
    while ((value = read_line(in))) {
        ++number;
        if (value[0] == '>') {
            if (out.count)
                out.values[out.count - 1].sequence = sequence.data;
            sequence = (Text){0};
            Record *record = &out.values[out.count++];
            record->line = number;
            int n = 0;
            while (value[n + 1] && value[n + 1] != ' ') {
                record->name[n] = value[n + 1];
                ++n;
            }
            record->name[n] = 0;
        } else
            for (int i = 0; value[i]; ++i)
                text(&sequence, "%c", toupper((unsigned char)value[i]));
        free(value);
    }
    out.values[out.count - 1].sequence = sequence.data;
    fclose(in);
    return out;
}
Patterns *compress_patterns(char **sequences, int count, int length) {
    Patterns *out = calloc(1, sizeof(Patterns));
    out->length = length;
    for (int c = 0; c < length; ++c) {
        char pattern[17];
        for (int t = 0; t < count; ++t)
            pattern[t] = sequences[t][c];
        pattern[count] = 0;
        int index = 0;
        while (index < out->count && strcmp(out->text[index], pattern))
            ++index;
        if (index == out->count) {
            strcpy(out->text[out->count++], pattern);
            for (int t = 0; t < count; ++t)
                out->encoded[index][t] = base_set(pattern[t]);
        }
        out->columns[c] = index;
        ++out->weights[index];
    }
    return out;
}
Classes classify(char **sequences, int count, int length) {
    Classes out = {0};
    for (int c = 0; c < length; ++c) {
        int counts[4] = {0}, kinds = 0, multiple = 0, gapped = 0;
        for (int t = 0; t < count; ++t) {
            int base = base_index(sequences[t][c]);
            if (base >= 0)
                ++counts[base];
            gapped |= sequences[t][c] == '-';
        }
        for (int b = 0; b < 4; ++b) {
            kinds += counts[b] > 0;
            multiple += counts[b] >= 2;
        }
        out.empty += !kinds;
        out.constant += kinds == 1;
        out.variable += kinds >= 2;
        out.informative += multiple >= 2;
        out.gapped += gapped;
    }
    return out;
}
