#include "cipher.h"

int letter_value(char character) {
    if (character >= 'A' && character <= 'Z')
        return character - 'A';
    if (character >= 'a' && character <= 'z')
        return character - 'a';
    return -1;
}

char *letter_string(const char *text) {
    char *letters = malloc(strlen(text) + 1);
    if (!letters)
        exit(EXIT_FAILURE);
    size_t length = 0;
    for (; *text; ++text) {
        int value = letter_value(*text);
        if (value >= 0)
            letters[length++] = (char)('A' + value);
    }
    letters[length] = '\0';
    return letters;
}

bool read_weights(const char *path, Weights *weights) {
    FILE *file = fopen(path, "r");
    if (!file)
        return false;
    char heading[16];
    bool valid = fscanf(file, "%15s", heading) == 1 &&
                 strcmp(heading, "MONOGRAMS") == 0;
    for (int i = 0; valid && i < 26; ++i)
        valid = fscanf(file, "%d", &weights->mono[i]) == 1;
    if (valid)
        valid = fscanf(file, "%15s", heading) == 1 &&
                strcmp(heading, "BIGRAMS") == 0;
    for (int i = 0; valid && i < 26; ++i)
        for (int j = 0; valid && j < 26; ++j)
            valid = fscanf(file, "%d", &weights->bigram[i][j]) == 1;
    fclose(file);
    return valid;
}

int monogram_fitness(const Weights *weights, const char *text) {
    int score = 0;
    for (; *text; ++text)
        score += weights->mono[*text - 'A'];
    return score;
}

int bigram_fitness(const Weights *weights, const char *text) {
    int score = 0;
    for (size_t i = 1; text[i - 1] && text[i]; ++i)
        score += weights->bigram[text[i - 1] - 'A'][text[i] - 'A'];
    return score;
}
