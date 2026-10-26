#include "classifier.h"

static char **names;
static int name_count, name_capacity, *buckets, bucket_capacity;
static uint64_t hash_text(const char *text) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const unsigned char *c = (const unsigned char *)text; *c; ++c) hash = (hash ^ *c) * UINT64_C(1099511628211);
    return hash;
}
static void resize_buckets(void) {
    bucket_capacity = bucket_capacity ? 2 * bucket_capacity : 1024;
    buckets = allocate((size_t)bucket_capacity * sizeof(int));
    for (int i = 0; i < name_count; ++i) {
        size_t position = hash_text(names[i]) & (size_t)(bucket_capacity - 1);
        while (buckets[position]) position = (position + 1) & (size_t)(bucket_capacity - 1);
        buckets[position] = i + 1;
    }
}
static int intern(char *text) {
    if (!bucket_capacity || 2 * (name_count + 1) > bucket_capacity) resize_buckets();
    size_t position = hash_text(text) & (size_t)(bucket_capacity - 1);
    while (buckets[position]) {
        int term = buckets[position] - 1;
        if (!strcmp(names[term], text)) return term;
        position = (position + 1) & (size_t)(bucket_capacity - 1);
    }
    if (name_count == name_capacity) {
        int capacity = name_capacity ? 2 * name_capacity : 1024;
        char **next = allocate((size_t)capacity * sizeof(*next));
        if (name_count) memcpy(next, names, (size_t)name_count * sizeof(*next));
        names = next;
        name_capacity = capacity;
    }
    int term = name_count++;
    names[term] = text;
    buckets[position] = term + 1;
    return term;
}
static bool word_character(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); }
Tokens tokenize(const char *text, Lines stopwords) {
    Tokens tokens = {0};
    tokens.words.items = allocate((strlen(text) + 1) * sizeof(int));
    size_t position = 0;
    while (text[position]) {
        if (!word_character(text[position])) { ++position; continue; }
        size_t start = position;
        while (word_character(text[position])) ++position;
        size_t length = position - start;
        char *word = allocate(length + 1);
        for (size_t i = 0; i < length; ++i) {
            char c = text[start + i];
            word[i] = c >= 'A' && c <= 'Z' ? (char)(c + 'a' - 'A') : c;
        }
        ++tokens.raw_count;
        bool stopped = false;
        for (int i = 0; i < stopwords.count; ++i) if (!strcmp(stopwords.items[i], word)) { stopped = true; break; }
        if (stopped) ++tokens.stopword_count;
        else if (length == 1) ++tokens.short_count;
        else tokens.words.items[tokens.words.count++] = intern(word);
    }
    tokens.bigram_terms.count = tokens.words.count ? 2 * tokens.words.count - 1 : 0;
    tokens.bigram_terms.items = allocate((size_t)tokens.bigram_terms.count * sizeof(int));
    if (tokens.words.count) memcpy(tokens.bigram_terms.items, tokens.words.items, (size_t)tokens.words.count * sizeof(int));
    for (int i = 0; i + 1 < tokens.words.count; ++i) tokens.bigram_terms.items[tokens.words.count + i] = intern(format("%s_%s", names[tokens.words.items[i]], names[tokens.words.items[i + 1]]));
    return tokens;
}
Terms token_terms(const Tokens *tokens, bool bigrams) { return bigrams ? tokens->bigram_terms : tokens->words; }
int term_count(void) { return name_count; }
const char *term_name(int term) { return names[term]; }
