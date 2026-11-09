#include "crossword.h"

bool valid_word(const char *text) {
    size_t length = strlen(text);
    if (length < 3 || length > 15) return false;
    for (size_t i = 0; i < length; ++i) if (text[i] < 'A' || text[i] > 'Z') return false;
    return true;
}

bool valid_integer(const char *text, int low, int high) {
    if (!text[0] || text[0] == '0') return false;
    int value = 0;
    for (const char *digit = text; *digit; ++digit) {
        if (*digit < '0' || *digit > '9' || value > high / 10) return false;
        value = value * 10 + *digit - '0';
        if (value > high) return false;
    }
    return value >= low;
}

const char *word_line_error(const char *line) {
    const char *space = strchr(line, ' ');
    if (!space || strchr(space + 1, ' ')) return "bad format";
    char word[41];
    size_t length = (size_t)(space - line);
    memcpy(word, line, length);
    word[length] = '\0';
    if (!valid_word(word)) return "bad word";
    return valid_integer(space + 1, 1, 100) ? NULL : "bad score";
}

const char *clue_line_error(const char *line) {
    const char *bar = strchr(line, '|');
    if (!bar || strchr(bar + 1, '|')) return "bad format";
    char word[101];
    size_t length = (size_t)(bar - line);
    memcpy(word, line, length);
    word[length] = '\0';
    if (!valid_word(word)) return "bad word";
    size_t clue_length = strlen(bar + 1);
    return clue_length < 1 || clue_length > 60 || bar[1] == ' ' || bar[clue_length] == ' ' ? "bad clue" : NULL;
}

static int rank_order(const void *first, const void *second) {
    const Word *a = first, *b = second;
    return a->score != b->score ? b->score - a->score : strcmp(a->text, b->text);
}

void build_index(WordIndex *index) {
    qsort(index->words, (size_t)index->count, sizeof(*index->words), rank_order);
    for (int i = 0; i < index->count; ++i) {
        Word *word = &index->words[i];
        int length = (int)strlen(word->text);
        ++index->length[length].count;
        for (int position = 0; position < length; ++position) ++index->letter[length][position][word->text[position] - 'A'].count;
    }
    for (int length = 3; length <= 15; ++length) {
        IntList *bucket = &index->length[length];
        bucket->values = allocate((size_t)bucket->count * sizeof(int));
        bucket->count = 0;
        for (int position = 0; position < length; ++position) {
            for (int letter = 0; letter < 26; ++letter) {
                bucket = &index->letter[length][position][letter];
                bucket->values = allocate((size_t)bucket->count * sizeof(int));
                bucket->count = 0;
            }
        }
    }
    for (int i = 0; i < index->count; ++i) {
        Word *word = &index->words[i];
        int length = (int)strlen(word->text);
        IntList *bucket = &index->length[length];
        bucket->values[bucket->count++] = i;
        for (int position = 0; position < length; ++position) {
            bucket = &index->letter[length][position][word->text[position] - 'A'];
            bucket->values[bucket->count++] = i;
        }
    }
}

int find_word(const WordIndex *index, const char *word) {
    for (int i = 0; i < index->count; ++i) if (!strcmp(index->words[i].text, word)) return i;
    return -1;
}

bool word_matches(const char *word, const char *pattern) {
    for (int i = 0; pattern[i]; ++i) if (pattern[i] != '.' && pattern[i] != word[i]) return false;
    return true;
}

int candidates(const WordIndex *index, const char *pattern, int min_score, const bool *used, int *result) {
    int length = (int)strlen(pattern);
    const IntList *pool = &index->length[length];
    for (int i = 0; i < length; ++i) if (pattern[i] != '.') {
        const IntList *bucket = &index->letter[length][i][pattern[i] - 'A'];
        if (bucket->count < pool->count) pool = bucket;
    }
    int count = 0;
    for (int i = 0; i < pool->count; ++i) {
        int word = pool->values[i];
        if (index->words[word].score < min_score) break;
        if (!used[word] && word_matches(index->words[word].text, pattern)) {
            if (result) result[count] = word;
            ++count;
        }
    }
    return count;
}
