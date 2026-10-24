#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WORD_LENGTH 30
#define MAX_NUMBER_LENGTH 7
#define MAX_ARGUMENTS 11
#define KWIC_WIDTH 30
#define MAX_COUNT 100
#define MAX_DOCUMENT_NUMBER 999
#define MAX_LINE_NUMBER 999
#define LINE_CAPACITY 4096
#define WORD_CAPACITY 256
#define LENGTH(array) (sizeof(array) / sizeof((array)[0]))

typedef bool (*Condition)(const char *word, size_t length);

typedef struct {
    const char *suffix;
    const char *replacement;
    Condition condition;
} Rule;

typedef struct {
    const char *name;
    const Rule *rules;
    size_t rule_count;
} Step;

typedef struct {
    const char *step;
    char word[WORD_CAPACITY];
} Change;

typedef struct {
    char *form;
    char *stem;
    int line;
    int position;
    int start;
    int length;
} Token;

typedef struct {
    int number;
    char **lines;
    int line_count;
    int line_capacity;
    Token *tokens;
    int token_count;
    int token_capacity;
} Document;

typedef struct {
    const Document *document;
    const Token *token;
} Occurrence;

typedef struct {
    const char *word;
    int count;
} WordCount;

typedef struct {
    int number;
    int numerator;
    int denominator;
} Score;

typedef struct {
    int number;
    int matched;
    int total;
} RankEntry;

typedef enum {
    KIND_AND,
    KIND_OR,
    KIND_NOT,
    KIND_OPEN,
    KIND_CLOSE,
    KIND_TERM,
    KIND_PREFIX,
    KIND_END,
} Kind;

typedef struct {
    Kind kind;
    char spelling[MAX_WORD_LENGTH + 1];
} Item;

typedef struct {
    const Item *items;
    int count;
    int position;
} Parser;

typedef struct {
    char *canonical;
    bool documents[MAX_DOCUMENT_NUMBER + 1];
} Evaluation;

typedef void (*Handler)(char **arguments, int count);

typedef struct {
    const char *name;
    int minimum;
    int maximum;
    Handler handler;
} Command;

static const char VOWELS[] = "aeiou";

static Document *documents[MAX_DOCUMENT_NUMBER + 1];
static char **stopwords;
static int stopword_count;
static int stopword_capacity;

static void *xrealloc(void *pointer, size_t size)
{
    void *result = realloc(pointer, size);
    if (result == NULL) {
        fputs("out of memory\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}

static void *reserve(void *items, int *capacity, int needed, size_t item_size)
{
    if (needed <= *capacity) {
        return items;
    }
    *capacity = needed > 2 * *capacity ? needed : 2 * *capacity;
    return xrealloc(items, (size_t)*capacity * item_size);
}

static char *copy_string(const char *text, size_t length)
{
    char *copy = xrealloc(NULL, length + 1);
    memcpy(copy, text, length);
    copy[length] = '\0';
    return copy;
}

static char *format_string(const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(NULL, 0, format, arguments);
    va_end(arguments);
    char *text = xrealloc(NULL, (size_t)length + 1);
    va_start(arguments, format);
    vsnprintf(text, (size_t)length + 1, format, arguments);
    va_end(arguments);
    return text;
}

static void lowercase(char *text)
{
    for (; *text != '\0'; text++) {
        *text = (char)tolower((unsigned char)*text);
    }
}

static bool starts_with(const char *text, const char *prefix)
{
    return strncmp(text, prefix, strlen(prefix)) == 0;
}

static bool ends_with(const char *word, size_t length, const char *suffix)
{
    size_t suffix_length = strlen(suffix);
    return length >= suffix_length &&
           memcmp(word + length - suffix_length, suffix, suffix_length) == 0;
}

static const char *yes_no(bool flag)
{
    return flag ? "YES" : "NO";
}

static void letter_pattern(const char *word, size_t length, char *kinds)
{
    for (size_t index = 0; index < length; index++) {
        char letter = word[index];
        bool vowel = strchr(VOWELS, letter) != NULL ||
                     (letter == 'y' && index > 0 && kinds[index - 1] == 'C');
        kinds[index] = vowel ? 'V' : 'C';
    }
    kinds[length] = '\0';
}

static int measure(const char *word, size_t length)
{
    char kinds[WORD_CAPACITY];
    letter_pattern(word, length, kinds);
    int value = 0;
    for (size_t index = 1; index < length; index++) {
        if (kinds[index - 1] == 'V' && kinds[index] == 'C') {
            value++;
        }
    }
    return value;
}

static bool has_vowel(const char *word, size_t length)
{
    char kinds[WORD_CAPACITY];
    letter_pattern(word, length, kinds);
    return strchr(kinds, 'V') != NULL;
}

static bool ends_double(const char *word, size_t length)
{
    char kinds[WORD_CAPACITY];
    letter_pattern(word, length, kinds);
    return ends_with(kinds, length, "CC") && word[length - 1] == word[length - 2];
}

static bool ends_cvc(const char *word, size_t length)
{
    char kinds[WORD_CAPACITY];
    letter_pattern(word, length, kinds);
    return ends_with(kinds, length, "CVC") && strchr("wxy", word[length - 1]) == NULL;
}

static bool always(const char *word, size_t length)
{
    (void)word;
    (void)length;
    return true;
}

static bool measure_above_zero(const char *word, size_t length)
{
    return measure(word, length) > 0;
}

static bool measure_above_one(const char *word, size_t length)
{
    return measure(word, length) > 1;
}

static bool ion_condition(const char *word, size_t length)
{
    return measure(word, length) > 1 &&
           (ends_with(word, length, "s") || ends_with(word, length, "t"));
}

static bool final_e_condition(const char *word, size_t length)
{
    int value = measure(word, length);
    return value > 1 || (value == 1 && !ends_cvc(word, length));
}

static const Rule STEP_1A[] = {
    {"sses", "ss", always},
    {"ies", "i", always},
    {"ss", "ss", always},
    {"s", "", always},
};

static const Rule STEP_1B[] = {
    {"eed", "ee", measure_above_zero},
    {"ed", "", has_vowel},
    {"ing", "", has_vowel},
};

static const Rule STEP_1C[] = {
    {"y", "i", has_vowel},
};

static const Rule STEP_2[] = {
    {"ational", "ate", measure_above_zero}, {"tional", "tion", measure_above_zero},
    {"enci", "ence", measure_above_zero},   {"anci", "ance", measure_above_zero},
    {"izer", "ize", measure_above_zero},    {"abli", "able", measure_above_zero},
    {"alli", "al", measure_above_zero},     {"entli", "ent", measure_above_zero},
    {"eli", "e", measure_above_zero},       {"ousli", "ous", measure_above_zero},
    {"ization", "ize", measure_above_zero}, {"ation", "ate", measure_above_zero},
    {"ator", "ate", measure_above_zero},    {"alism", "al", measure_above_zero},
    {"iveness", "ive", measure_above_zero}, {"fulness", "ful", measure_above_zero},
    {"ousness", "ous", measure_above_zero}, {"aliti", "al", measure_above_zero},
    {"iviti", "ive", measure_above_zero},   {"biliti", "ble", measure_above_zero},
};

static const Rule STEP_3[] = {
    {"icate", "ic", measure_above_zero}, {"ative", "", measure_above_zero},
    {"alize", "al", measure_above_zero}, {"iciti", "ic", measure_above_zero},
    {"ical", "ic", measure_above_zero},  {"ful", "", measure_above_zero},
    {"ness", "", measure_above_zero},
};

static const Rule STEP_4[] = {
    {"al", "", measure_above_one},    {"ance", "", measure_above_one},
    {"ence", "", measure_above_one},  {"er", "", measure_above_one},
    {"ic", "", measure_above_one},    {"able", "", measure_above_one},
    {"ible", "", measure_above_one},  {"ant", "", measure_above_one},
    {"ement", "", measure_above_one}, {"ment", "", measure_above_one},
    {"ent", "", measure_above_one},   {"ion", "", ion_condition},
    {"ou", "", measure_above_one},    {"ism", "", measure_above_one},
    {"ate", "", measure_above_one},   {"iti", "", measure_above_one},
    {"ous", "", measure_above_one},   {"ive", "", measure_above_one},
    {"ize", "", measure_above_one},
};

static const Rule STEP_5A[] = {
    {"e", "", final_e_condition},
};

static const Step STEPS[] = {
    {"1a", STEP_1A, LENGTH(STEP_1A)}, {"1b", STEP_1B, LENGTH(STEP_1B)},
    {"1c", STEP_1C, LENGTH(STEP_1C)}, {"2", STEP_2, LENGTH(STEP_2)},
    {"3", STEP_3, LENGTH(STEP_3)},    {"4", STEP_4, LENGTH(STEP_4)},
    {"5a", STEP_5A, LENGTH(STEP_5A)}, {"5b", NULL, 0},
};

/* Applies the rule with the longest matching suffix in place; returns the applied rule. */
static const Rule *apply_rules(char *word, const Rule *rules, size_t rule_count)
{
    size_t length = strlen(word);
    const Rule *selected = NULL;
    for (size_t index = 0; index < rule_count; index++) {
        const Rule *rule = &rules[index];
        if (ends_with(word, length, rule->suffix) &&
            (selected == NULL || strlen(rule->suffix) > strlen(selected->suffix))) {
            selected = rule;
        }
    }
    if (selected == NULL) {
        return NULL;
    }
    size_t remainder = length - strlen(selected->suffix);
    if (!selected->condition(word, remainder)) {
        return NULL;
    }
    strcpy(word + remainder, selected->replacement);
    return selected;
}

static void tidy_step_1b(char *word)
{
    size_t length = strlen(word);
    if (ends_with(word, length, "at") || ends_with(word, length, "bl") ||
        ends_with(word, length, "iz")) {
        strcat(word, "e");
    } else if (ends_double(word, length) && strchr("lsz", word[length - 1]) == NULL) {
        word[length - 1] = '\0';
    } else if (measure(word, length) == 1 && ends_cvc(word, length)) {
        strcat(word, "e");
    }
}

static void apply_step(const Step *step, char *word)
{
    size_t length = strlen(word);
    if (step->rules == NULL) {
        if (measure(word, length) > 1 && ends_double(word, length) && word[length - 1] == 'l') {
            word[length - 1] = '\0';
        }
        return;
    }
    const Rule *rule = apply_rules(word, step->rules, step->rule_count);
    if (strcmp(step->name, "1b") == 0 && rule != NULL &&
        (strcmp(rule->suffix, "ed") == 0 || strcmp(rule->suffix, "ing") == 0)) {
        tidy_step_1b(word);
    }
}

static int stemming_steps(const char *word, char *stem, Change *changes)
{
    strcpy(stem, word);
    if (strlen(word) <= 2) {
        return 0;
    }
    int change_count = 0;
    for (size_t index = 0; index < LENGTH(STEPS); index++) {
        char before[WORD_CAPACITY];
        strcpy(before, stem);
        apply_step(&STEPS[index], stem);
        if (strcmp(before, stem) != 0) {
            changes[change_count].step = STEPS[index].name;
            strcpy(changes[change_count].word, stem);
            change_count++;
        }
    }
    return change_count;
}

static void porter_stem(const char *word, char *stem)
{
    Change changes[LENGTH(STEPS)];
    stemming_steps(word, stem, changes);
}

static int find_stopword(const char *word)
{
    for (int index = 0; index < stopword_count; index++) {
        if (strcmp(stopwords[index], word) == 0) {
            return index;
        }
    }
    return -1;
}

static bool is_stopword(const char *word)
{
    return find_stopword(word) >= 0;
}

static void add_stopword(const char *word)
{
    stopwords = reserve(stopwords, &stopword_capacity, stopword_count + 1, sizeof *stopwords);
    stopwords[stopword_count++] = copy_string(word, strlen(word));
}

static void remove_stopword(const char *word)
{
    int index = find_stopword(word);
    free(stopwords[index]);
    stopwords[index] = stopwords[--stopword_count];
}

static bool is_indexed(const Token *token)
{
    return !is_stopword(token->form);
}

static Document *create_document(int number)
{
    Document *document = xrealloc(NULL, sizeof *document);
    *document = (Document){.number = number};
    documents[number] = document;
    return document;
}

static void free_document(Document *document)
{
    for (int index = 0; index < document->line_count; index++) {
        free(document->lines[index]);
    }
    for (int index = 0; index < document->token_count; index++) {
        free(document->tokens[index].form);
        free(document->tokens[index].stem);
    }
    free(document->lines);
    free(document->tokens);
    free(document);
}

static void add_token(Document *document, const char *text, int start, int length)
{
    document->tokens = reserve(document->tokens, &document->token_capacity,
                               document->token_count + 1, sizeof *document->tokens);
    char *form = copy_string(text + start, (size_t)length);
    lowercase(form);
    char stem[WORD_CAPACITY];
    porter_stem(form, stem);
    document->tokens[document->token_count] = (Token){
        .form = form,
        .stem = copy_string(stem, strlen(stem)),
        .line = document->line_count,
        .position = document->token_count + 1,
        .start = start,
        .length = length,
    };
    document->token_count++;
}

static void add_line(Document *document, const char *text)
{
    document->lines = reserve(document->lines, &document->line_capacity, document->line_count + 1,
                              sizeof *document->lines);
    document->lines[document->line_count++] = copy_string(text, strlen(text));
    int start = 0;
    while (text[start] != '\0') {
        if (!isalpha((unsigned char)text[start])) {
            start++;
            continue;
        }
        int end = start;
        while (isalpha((unsigned char)text[end])) {
            end++;
        }
        add_token(document, text, start, end - start);
        start = end;
    }
}

static void print_reference(const Document *document, const Token *token)
{
    printf(" %d:%d:%d", document->number, token->line, token->position);
}

static int compare_strings(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static int compare_by_count(const void *left, const void *right)
{
    const WordCount *first = left;
    const WordCount *second = right;
    if (first->count != second->count) {
        return second->count - first->count;
    }
    return strcmp(first->word, second->word);
}

static WordCount *count_words(const char **words, int total, int *distinct)
{
    qsort(words, (size_t)total, sizeof *words, compare_strings);
    WordCount *counts = xrealloc(NULL, ((size_t)total + 1) * sizeof *counts);
    int count = 0;
    for (int index = 0; index < total; index++) {
        if (count > 0 && strcmp(counts[count - 1].word, words[index]) == 0) {
            counts[count - 1].count++;
        } else {
            counts[count++] = (WordCount){words[index], 1};
        }
    }
    *distinct = count;
    return counts;
}

static int collect_stems(const Document *document, const char **stems, int total)
{
    for (int index = 0; index < document->token_count; index++) {
        if (is_indexed(&document->tokens[index])) {
            stems[total++] = document->tokens[index].stem;
        }
    }
    return total;
}

static WordCount *term_frequencies(const Document *document, int *distinct)
{
    const char **stems = xrealloc(NULL, ((size_t)document->token_count + 1) * sizeof *stems);
    int total = collect_stems(document, stems, 0);
    WordCount *counts = count_words(stems, total, distinct);
    free(stems);
    return counts;
}

static WordCount *total_frequencies(int *distinct)
{
    size_t capacity = 1;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        if (documents[number] != NULL) {
            capacity += (size_t)documents[number]->token_count;
        }
    }
    const char **stems = xrealloc(NULL, capacity * sizeof *stems);
    int total = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        if (documents[number] != NULL) {
            total = collect_stems(documents[number], stems, total);
        }
    }
    WordCount *counts = count_words(stems, total, distinct);
    free(stems);
    return counts;
}

static int term_frequency(const Document *document, const char *stem)
{
    int count = 0;
    for (int index = 0; index < document->token_count; index++) {
        const Token *token = &document->tokens[index];
        if (is_indexed(token) && strcmp(token->stem, stem) == 0) {
            count++;
        }
    }
    return count;
}

static int indexed_count(const Document *document)
{
    int count = 0;
    for (int index = 0; index < document->token_count; index++) {
        if (is_indexed(&document->tokens[index])) {
            count++;
        }
    }
    return count;
}

static bool contains_stem(const Document *document, const char *stem, bool as_prefix)
{
    for (int index = 0; index < document->token_count; index++) {
        const Token *token = &document->tokens[index];
        if (is_indexed(token) &&
            (as_prefix ? starts_with(token->stem, stem) : strcmp(token->stem, stem) == 0)) {
            return true;
        }
    }
    return false;
}

static Occurrence *collect_occurrences(const char *stem, int *count)
{
    Occurrence *occurrences = NULL;
    int capacity = 0;
    *count = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *document = documents[number];
        if (document == NULL) {
            continue;
        }
        for (int index = 0; index < document->token_count; index++) {
            const Token *token = &document->tokens[index];
            if (is_indexed(token) && (stem == NULL || strcmp(token->stem, stem) == 0)) {
                occurrences = reserve(occurrences, &capacity, *count + 1, sizeof *occurrences);
                occurrences[(*count)++] = (Occurrence){document, token};
            }
        }
    }
    return occurrences;
}

static int compare_occurrences(const void *left, const void *right)
{
    const Occurrence *first = left;
    const Occurrence *second = right;
    int order = strcmp(first->token->stem, second->token->stem);
    if (order != 0) {
        return order;
    }
    if (first->document->number != second->document->number) {
        return first->document->number - second->document->number;
    }
    return first->token->position - second->token->position;
}

static int group_end(const Occurrence *occurrences, int count, int first)
{
    int end = first;
    while (end < count &&
           strcmp(occurrences[end].token->stem, occurrences[first].token->stem) == 0) {
        end++;
    }
    return end;
}

static int document_count(const Occurrence *occurrences, int count)
{
    int documents_found = 0;
    for (int index = 0; index < count; index++) {
        if (index == 0 || occurrences[index].document != occurrences[index - 1].document) {
            documents_found++;
        }
    }
    return documents_found;
}

static int form_count(const char *form)
{
    int count = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *document = documents[number];
        for (int index = 0; document != NULL && index < document->token_count; index++) {
            if (strcmp(document->tokens[index].form, form) == 0) {
                count++;
            }
        }
    }
    return count;
}

static int closest_distance(const Document *document, const char *first, const char *second)
{
    int best = -1;
    int last_first = 0;
    int last_second = 0;
    for (int index = 0; index < document->token_count; index++) {
        const Token *token = &document->tokens[index];
        if (!is_indexed(token)) {
            continue;
        }
        bool is_first = strcmp(token->stem, first) == 0;
        bool is_second = strcmp(token->stem, second) == 0;
        if (!is_first && !is_second) {
            continue;
        }
        int previous = is_first ? last_second : last_first;
        if (previous > 0 && (best < 0 || token->position - previous < best)) {
            best = token->position - previous;
        }
        if (is_first) {
            last_first = token->position;
        }
        if (is_second) {
            last_second = token->position;
        }
    }
    return best;
}

static bool token_matches(const Token *token, const char *target)
{
    return strcmp(target, "?") == 0 || (is_indexed(token) && strcmp(token->stem, target) == 0);
}

static bool phrase_matches_at(const Document *document, int start, char targets[][WORD_CAPACITY],
                              int count)
{
    for (int offset = 0; offset < count; offset++) {
        if (!token_matches(&document->tokens[start + offset], targets[offset])) {
            return false;
        }
    }
    return true;
}

static int gcd(int a, int b)
{
    return b == 0 ? a : gcd(b, a % b);
}

static Score make_score(int number, int shared, int union_size)
{
    if (union_size == 0) {
        return (Score){number, 0, 1};
    }
    int divisor = gcd(shared, union_size);
    return (Score){number, shared / divisor, union_size / divisor};
}

static int compare_scores(const void *left, const void *right)
{
    const Score *first = left;
    const Score *second = right;
    int difference =
        second->numerator * first->denominator - first->numerator * second->denominator;
    if (difference != 0) {
        return difference;
    }
    return first->number - second->number;
}

static int compare_rank_entries(const void *left, const void *right)
{
    const RankEntry *first = left;
    const RankEntry *second = right;
    if (first->matched != second->matched) {
        return second->matched - first->matched;
    }
    if (first->total != second->total) {
        return second->total - first->total;
    }
    return first->number - second->number;
}

static int shared_count(const WordCount *stems, int count, const WordCount *others, int other_count)
{
    int shared = 0;
    int index = 0;
    int other = 0;
    while (index < count && other < other_count) {
        int order = strcmp(stems[index].word, others[other].word);
        if (order == 0) {
            shared++;
        }
        if (order <= 0) {
            index++;
        }
        if (order >= 0) {
            other++;
        }
    }
    return shared;
}

static bool is_word(const char *text, size_t length)
{
    if (length < 1 || length > MAX_WORD_LENGTH) {
        return false;
    }
    for (size_t index = 0; index < length; index++) {
        if (!isalpha((unsigned char)text[index])) {
            return false;
        }
    }
    return true;
}

static bool word_argument(const char *text, char *word)
{
    if (!is_word(text, strlen(text))) {
        printf("ERROR BAD WORD %s\n", text);
        return false;
    }
    strcpy(word, text);
    lowercase(word);
    return true;
}

static bool number_argument(const char *text, int minimum, int maximum, int *value)
{
    size_t length = strlen(text);
    int number = atoi(text);
    if (length < 1 || length > MAX_NUMBER_LENGTH || strspn(text, "0123456789") != length ||
        number < minimum || number > maximum) {
        printf("ERROR BAD NUMBER %s\n", text);
        return false;
    }
    *value = number;
    return true;
}

static bool term_argument(const char *text, char *stem)
{
    char word[WORD_CAPACITY];
    if (!word_argument(text, word)) {
        return false;
    }
    if (is_stopword(word)) {
        printf("ERROR STOPWORD %s\n", word);
        return false;
    }
    porter_stem(word, stem);
    return true;
}

static Document *document_argument(const char *text)
{
    int number;
    if (!number_argument(text, 1, MAX_DOCUMENT_NUMBER, &number)) {
        return NULL;
    }
    if (documents[number] == NULL) {
        printf("ERROR NO DOC %d\n", number);
    }
    return documents[number];
}

static bool classify(const char *text, size_t length, Item *item)
{
    static const struct {
        const char *text;
        Kind kind;
    } SYMBOLS[] = {
        {"AND", KIND_AND}, {"OR", KIND_OR}, {"NOT", KIND_NOT}, {"(", KIND_OPEN}, {")", KIND_CLOSE},
    };
    for (size_t index = 0; index < LENGTH(SYMBOLS); index++) {
        if (strlen(SYMBOLS[index].text) == length &&
            strncmp(SYMBOLS[index].text, text, length) == 0) {
            item->kind = SYMBOLS[index].kind;
            return true;
        }
    }
    size_t letters = length;
    item->kind = KIND_TERM;
    if (length > 1 && text[length - 1] == '*') {
        letters = length - 1;
        item->kind = KIND_PREFIX;
    }
    if (!is_word(text, letters)) {
        return false;
    }
    memcpy(item->spelling, text, letters);
    item->spelling[letters] = '\0';
    lowercase(item->spelling);
    return true;
}

static Kind peek(const Parser *parser)
{
    return parser->position < parser->count ? parser->items[parser->position].kind : KIND_END;
}

static void combine(Evaluation *left, Evaluation *right, const char *operator_name)
{
    char *canonical = format_string("(%s %s %s)", left->canonical, operator_name, right->canonical);
    free(left->canonical);
    free(right->canonical);
    left->canonical = canonical;
    bool is_or = strcmp(operator_name, "OR") == 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        left->documents[number] = is_or ? left->documents[number] || right->documents[number]
                                        : left->documents[number] && right->documents[number];
    }
}

static void select_documents(Evaluation *result, const char *stem, bool as_prefix)
{
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        result->documents[number] =
            documents[number] != NULL && contains_stem(documents[number], stem, as_prefix);
    }
}

static bool parse_expression(Parser *parser, Evaluation *result);

static bool parse_element(Parser *parser, Evaluation *result)
{
    if (parser->position >= parser->count) {
        return false;
    }
    const Item *item = &parser->items[parser->position++];
    switch (item->kind) {
    case KIND_OPEN:
        if (!parse_expression(parser, result)) {
            return false;
        }
        if (peek(parser) != KIND_CLOSE) {
            free(result->canonical);
            return false;
        }
        parser->position++;
        return true;
    case KIND_TERM: {
        char stem[WORD_CAPACITY];
        porter_stem(item->spelling, stem);
        result->canonical = copy_string(stem, strlen(stem));
        select_documents(result, stem, false);
        return true;
    }
    case KIND_PREFIX:
        result->canonical = format_string("%s*", item->spelling);
        select_documents(result, item->spelling, true);
        return true;
    default:
        return false;
    }
}

static bool parse_negation(Parser *parser, Evaluation *result)
{
    if (peek(parser) != KIND_NOT) {
        return parse_element(parser, result);
    }
    parser->position++;
    Evaluation operand;
    if (!parse_negation(parser, &operand)) {
        return false;
    }
    result->canonical = format_string("(NOT %s)", operand.canonical);
    free(operand.canonical);
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        result->documents[number] = documents[number] != NULL && !operand.documents[number];
    }
    return true;
}

static bool continues_conjunction(Kind kind)
{
    return kind == KIND_AND || kind == KIND_NOT || kind == KIND_OPEN || kind == KIND_TERM ||
           kind == KIND_PREFIX;
}

static bool parse_conjunction(Parser *parser, Evaluation *result)
{
    if (!parse_negation(parser, result)) {
        return false;
    }
    while (continues_conjunction(peek(parser))) {
        if (peek(parser) == KIND_AND) {
            parser->position++;
        }
        Evaluation right;
        if (!parse_negation(parser, &right)) {
            free(result->canonical);
            return false;
        }
        combine(result, &right, "AND");
    }
    return true;
}

static bool parse_expression(Parser *parser, Evaluation *result)
{
    if (!parse_conjunction(parser, result)) {
        return false;
    }
    while (peek(parser) == KIND_OR) {
        parser->position++;
        Evaluation right;
        if (!parse_conjunction(parser, &right)) {
            free(result->canonical);
            return false;
        }
        combine(result, &right, "OR");
    }
    return true;
}

static bool parse_query(Parser *parser, Evaluation *result)
{
    if (!parse_expression(parser, result)) {
        return false;
    }
    if (parser->position == parser->count) {
        return true;
    }
    free(result->canonical);
    return false;
}

static void stem_words(char **arguments, int count)
{
    char words[MAX_ARGUMENTS][WORD_CAPACITY];
    for (int index = 0; index < count; index++) {
        if (!word_argument(arguments[index], words[index])) {
            return;
        }
    }
    printf("STEM");
    for (int index = 0; index < count; index++) {
        char stem[WORD_CAPACITY];
        porter_stem(words[index], stem);
        printf(" %s:%s", words[index], stem);
    }
    putchar('\n');
}

static void show_steps(char **arguments, int count)
{
    char word[WORD_CAPACITY];
    if (!word_argument(arguments[0], word)) {
        return;
    }
    char stem[WORD_CAPACITY];
    Change changes[LENGTH(STEPS)];
    int change_count = stemming_steps(word, stem, changes);
    printf("STEPS %s", word);
    if (change_count == 0) {
        printf(" NONE");
    }
    for (int index = 0; index < change_count; index++) {
        printf(" %s:%s", changes[index].step, changes[index].word);
    }
    putchar('\n');
}

static void show_measure(char **arguments, int count)
{
    char word[WORD_CAPACITY];
    if (!word_argument(arguments[0], word)) {
        return;
    }
    size_t length = strlen(word);
    char kinds[WORD_CAPACITY];
    letter_pattern(word, length, kinds);
    printf("MEASURE %s %s m=%d vowel=%s double=%s cvc=%s\n", word, kinds, measure(word, length),
           yes_no(has_vowel(word, length)), yes_no(ends_double(word, length)),
           yes_no(ends_cvc(word, length)));
}

static void show_index(char **arguments, int count)
{
    char prefix[WORD_CAPACITY] = "";
    if (count == 1 && !word_argument(arguments[0], prefix)) {
        return;
    }
    int total;
    Occurrence *occurrences = collect_occurrences(NULL, &total);
    qsort(occurrences, (size_t)total, sizeof *occurrences, compare_occurrences);
    int stems = 0;
    for (int first = 0; first < total; first = group_end(occurrences, total, first)) {
        if (starts_with(occurrences[first].token->stem, prefix)) {
            stems++;
        }
    }
    printf("INDEX stems=%d\n", stems);
    for (int first = 0; first < total;) {
        int end = group_end(occurrences, total, first);
        const char *stem = occurrences[first].token->stem;
        if (starts_with(stem, prefix)) {
            printf("%s df=%d", stem, document_count(occurrences + first, end - first));
            for (int index = first; index < end; index++) {
                print_reference(occurrences[index].document, occurrences[index].token);
            }
            putchar('\n');
        }
        first = end;
    }
    free(occurrences);
}

static void search(char **arguments, int count)
{
    const char *expression = arguments[0];
    Item *items = xrealloc(NULL, (strlen(expression) + 1) * sizeof *items);
    int item_count = 0;
    for (const char *cursor = expression; *cursor != '\0';) {
        if (*cursor == ' ') {
            cursor++;
            continue;
        }
        size_t length = *cursor == '(' || *cursor == ')' ? 1 : strcspn(cursor, " ()");
        if (!classify(cursor, length, &items[item_count])) {
            printf("ERROR BAD TERM %.*s\n", (int)length, cursor);
            free(items);
            return;
        }
        item_count++;
        cursor += length;
    }
    Parser parser = {items, item_count, 0};
    Evaluation result;
    if (!parse_query(&parser, &result)) {
        puts("ERROR SYNTAX");
        free(items);
        return;
    }
    for (int index = 0; index < item_count; index++) {
        if (items[index].kind == KIND_TERM && is_stopword(items[index].spelling)) {
            printf("ERROR STOPWORD %s\n", items[index].spelling);
            free(result.canonical);
            free(items);
            return;
        }
    }
    int matches = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        matches += result.documents[number];
    }
    printf("SEARCH %s count=%d", result.canonical, matches);
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        if (result.documents[number]) {
            printf(" %d", number);
        }
    }
    putchar('\n');
    free(result.canonical);
    free(items);
}

static void phrase(char **arguments, int count)
{
    char words[MAX_ARGUMENTS][WORD_CAPACITY];
    bool all_stopwords = true;
    for (int index = 0; index < count; index++) {
        if (!word_argument(arguments[index], words[index])) {
            return;
        }
        all_stopwords = all_stopwords && is_stopword(words[index]);
    }
    if (all_stopwords) {
        puts("ERROR STOPWORDS ONLY");
        return;
    }
    char targets[MAX_ARGUMENTS][WORD_CAPACITY];
    for (int index = 0; index < count; index++) {
        if (is_stopword(words[index])) {
            strcpy(targets[index], "?");
        } else {
            porter_stem(words[index], targets[index]);
        }
    }
    int matches = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *document = documents[number];
        for (int start = 0; document != NULL && start + count <= document->token_count; start++) {
            matches += phrase_matches_at(document, start, targets, count);
        }
    }
    printf("PHRASE \"");
    for (int index = 0; index < count; index++) {
        printf(index == 0 ? "%s" : " %s", targets[index]);
    }
    printf("\" matches=%d", matches);
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *document = documents[number];
        for (int start = 0; document != NULL && start + count <= document->token_count; start++) {
            if (phrase_matches_at(document, start, targets, count)) {
                print_reference(document, &document->tokens[start]);
            }
        }
    }
    putchar('\n');
}

static void near(char **arguments, int count)
{
    char first[WORD_CAPACITY];
    char second[WORD_CAPACITY];
    int limit;
    if (!term_argument(arguments[0], first) || !term_argument(arguments[1], second) ||
        !number_argument(arguments[2], 1, MAX_COUNT, &limit)) {
        return;
    }
    int distances[MAX_DOCUMENT_NUMBER + 1];
    int found = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        distances[number] =
            documents[number] == NULL ? -1 : closest_distance(documents[number], first, second);
        if (distances[number] > limit) {
            distances[number] = -1;
        }
        found += distances[number] >= 0;
    }
    printf("NEAR %s %s %d count=%d", first, second, limit, found);
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        if (distances[number] >= 0) {
            printf(" %d:%d", number, distances[number]);
        }
    }
    putchar('\n');
}

static void top(char **arguments, int count)
{
    int limit;
    if (!number_argument(arguments[0], 1, MAX_COUNT, &limit)) {
        return;
    }
    int distinct;
    WordCount *counts;
    if (count == 2) {
        const Document *document = document_argument(arguments[1]);
        if (document == NULL) {
            return;
        }
        counts = term_frequencies(document, &distinct);
        printf("TOP %d doc=%d", limit, document->number);
    } else {
        counts = total_frequencies(&distinct);
        printf("TOP %d", limit);
    }
    qsort(counts, (size_t)distinct, sizeof *counts, compare_by_count);
    for (int index = 0; index < distinct && index < limit; index++) {
        printf(" %s:%d", counts[index].word, counts[index].count);
    }
    putchar('\n');
    free(counts);
}

static void kwic(char **arguments, int count)
{
    char stem[WORD_CAPACITY];
    if (!term_argument(arguments[0], stem)) {
        return;
    }
    int total;
    Occurrence *occurrences = collect_occurrences(stem, &total);
    printf("KWIC %s count=%d\n", stem, total);
    for (int index = 0; index < total; index++) {
        const Document *document = occurrences[index].document;
        const Token *token = occurrences[index].token;
        const char *text = document->lines[token->line - 1];
        int before = token->start < KWIC_WIDTH ? token->start : KWIC_WIDTH;
        printf("|%*.*s[%.*s]%-*.*s|", KWIC_WIDTH, before, text + token->start - before,
               token->length, text + token->start, KWIC_WIDTH, KWIC_WIDTH,
               text + token->start + token->length);
        print_reference(document, token);
        putchar('\n');
    }
    free(occurrences);
}

static void show_term_frequency(char **arguments, int count)
{
    const Document *document = document_argument(arguments[0]);
    char stem[WORD_CAPACITY];
    if (document == NULL || !term_argument(arguments[1], stem)) {
        return;
    }
    printf("TF %d %s %d\n", document->number, stem, term_frequency(document, stem));
}

static void show_document_frequency(char **arguments, int count)
{
    char stem[WORD_CAPACITY];
    if (!term_argument(arguments[0], stem)) {
        return;
    }
    int total;
    Occurrence *occurrences = collect_occurrences(stem, &total);
    printf("DF %s %d\n", stem, document_count(occurrences, total));
    free(occurrences);
}

static void variants(char **arguments, int count)
{
    char stem[WORD_CAPACITY];
    if (!term_argument(arguments[0], stem)) {
        return;
    }
    int total;
    Occurrence *occurrences = collect_occurrences(stem, &total);
    const char **forms = xrealloc(NULL, ((size_t)total + 1) * sizeof *forms);
    for (int index = 0; index < total; index++) {
        forms[index] = occurrences[index].token->form;
    }
    int distinct;
    WordCount *counts = count_words(forms, total, &distinct);
    printf("VARIANTS %s count=%d", stem, distinct);
    for (int index = 0; index < distinct; index++) {
        printf(" %s:%d", counts[index].word, counts[index].count);
    }
    putchar('\n');
    free(counts);
    free(forms);
    free(occurrences);
}

static void similar(char **arguments, int count)
{
    const Document *document = document_argument(arguments[0]);
    int limit;
    if (document == NULL || !number_argument(arguments[1], 1, MAX_COUNT, &limit)) {
        return;
    }
    int stem_count;
    WordCount *stems = term_frequencies(document, &stem_count);
    Score scores[MAX_DOCUMENT_NUMBER];
    int score_count = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *other = documents[number];
        if (other == NULL || other == document) {
            continue;
        }
        int other_count;
        WordCount *other_stems = term_frequencies(other, &other_count);
        int shared = shared_count(stems, stem_count, other_stems, other_count);
        scores[score_count++] = make_score(number, shared, stem_count + other_count - shared);
        free(other_stems);
    }
    qsort(scores, (size_t)score_count, sizeof *scores, compare_scores);
    printf("SIMILAR %d", document->number);
    for (int index = 0; index < score_count && index < limit; index++) {
        printf(" %d:%d/%d", scores[index].number, scores[index].numerator,
               scores[index].denominator);
    }
    putchar('\n');
    free(stems);
}

static void rank(char **arguments, int count)
{
    int limit;
    if (!number_argument(arguments[0], 1, MAX_COUNT, &limit)) {
        return;
    }
    char query[MAX_ARGUMENTS][WORD_CAPACITY];
    int query_count = 0;
    for (int index = 1; index < count; index++) {
        char stem[WORD_CAPACITY];
        if (!term_argument(arguments[index], stem)) {
            return;
        }
        bool duplicate = false;
        for (int other = 0; other < query_count; other++) {
            duplicate = duplicate || strcmp(query[other], stem) == 0;
        }
        if (!duplicate) {
            strcpy(query[query_count++], stem);
        }
    }
    RankEntry entries[MAX_DOCUMENT_NUMBER];
    int entry_count = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        if (documents[number] == NULL) {
            continue;
        }
        RankEntry entry = {number, 0, 0};
        for (int index = 0; index < query_count; index++) {
            int frequency = term_frequency(documents[number], query[index]);
            entry.matched += frequency > 0;
            entry.total += frequency;
        }
        if (entry.matched > 0) {
            entries[entry_count++] = entry;
        }
    }
    qsort(entries, (size_t)entry_count, sizeof *entries, compare_rank_entries);
    printf("RANK count=%d", entry_count);
    for (int index = 0; index < entry_count && index < limit; index++) {
        printf(" %d:%d:%d", entries[index].number, entries[index].matched, entries[index].total);
    }
    putchar('\n');
}

static void info(char **arguments, int count)
{
    const Document *document = document_argument(arguments[0]);
    if (document == NULL) {
        return;
    }
    int distinct;
    WordCount *counts = term_frequencies(document, &distinct);
    qsort(counts, (size_t)distinct, sizeof *counts, compare_by_count);
    printf("INFO %d lines=%d tokens=%d indexed=%d stems=%d top=", document->number,
           document->line_count, document->token_count, indexed_count(document), distinct);
    if (distinct > 0) {
        printf("%s:%d\n", counts[0].word, counts[0].count);
    } else {
        puts("-");
    }
    free(counts);
}

static void show_line(char **arguments, int count)
{
    const Document *document = document_argument(arguments[0]);
    int line_number;
    if (document == NULL || !number_argument(arguments[1], 1, MAX_LINE_NUMBER, &line_number)) {
        return;
    }
    if (line_number > document->line_count) {
        printf("ERROR NO LINE %d:%d\n", document->number, line_number);
        return;
    }
    int tokens = 0;
    for (int index = 0; index < document->token_count; index++) {
        tokens += document->tokens[index].line == line_number;
    }
    printf("LINE %d:%d tokens=%d", document->number, line_number, tokens);
    for (int index = 0; index < document->token_count; index++) {
        const Token *token = &document->tokens[index];
        if (token->line != line_number) {
            continue;
        }
        if (is_indexed(token)) {
            printf(" %s/%s", token->form, token->stem);
        } else {
            printf(" %s/-", token->form);
        }
    }
    putchar('\n');
}

static void stats(char **arguments, int count)
{
    int document_total = 0;
    int lines = 0;
    int tokens = 0;
    int indexed = 0;
    for (int number = 1; number <= MAX_DOCUMENT_NUMBER; number++) {
        const Document *document = documents[number];
        if (document != NULL) {
            document_total++;
            lines += document->line_count;
            tokens += document->token_count;
            indexed += indexed_count(document);
        }
    }
    int stems;
    WordCount *totals = total_frequencies(&stems);
    free(totals);
    printf("STATS docs=%d lines=%d tokens=%d indexed=%d stems=%d stopwords=%d\n", document_total,
           lines, tokens, indexed, stems, stopword_count);
}

static void stop(char **arguments, int count)
{
    char word[WORD_CAPACITY];
    if (!word_argument(arguments[0], word)) {
        return;
    }
    if (is_stopword(word)) {
        printf("ERROR ALREADY STOPWORD %s\n", word);
        return;
    }
    add_stopword(word);
    printf("STOP %s unindexed=%d\n", word, form_count(word));
}

static void unstop(char **arguments, int count)
{
    char word[WORD_CAPACITY];
    if (!word_argument(arguments[0], word)) {
        return;
    }
    if (!is_stopword(word)) {
        printf("ERROR NOT STOPWORD %s\n", word);
        return;
    }
    remove_stopword(word);
    printf("UNSTOP %s indexed=%d\n", word, form_count(word));
}

static void append(char **arguments, int count)
{
    int number;
    if (!number_argument(arguments[0], 1, MAX_DOCUMENT_NUMBER, &number)) {
        return;
    }
    bool created = documents[number] == NULL;
    Document *document = created ? create_document(number) : documents[number];
    int first = document->token_count;
    add_line(document, arguments[1]);
    int indexed = 0;
    for (int index = first; index < document->token_count; index++) {
        indexed += is_indexed(&document->tokens[index]);
    }
    printf("APPEND %d line=%d tokens=%d indexed=%d new=%s\n", number, document->line_count,
           document->token_count - first, indexed, yes_no(created));
}

static void delete(char **arguments, int count)
{
    Document *document = document_argument(arguments[0]);
    if (document == NULL) {
        return;
    }
    printf("DELETE %d lines=%d tokens=%d\n", document->number, document->line_count,
           document->token_count);
    documents[document->number] = NULL;
    free_document(document);
}

static const Command COMMANDS[] = {
    {"STEM", 1, 10, stem_words},
    {"STEPS", 1, 1, show_steps},
    {"MEASURE", 1, 1, show_measure},
    {"INDEX", 0, 1, show_index},
    {"SEARCH", 1, 1, search},
    {"PHRASE", 2, 10, phrase},
    {"NEAR", 3, 3, near},
    {"TOP", 1, 2, top},
    {"KWIC", 1, 1, kwic},
    {"TF", 2, 2, show_term_frequency},
    {"DF", 1, 1, show_document_frequency},
    {"VARIANTS", 1, 1, variants},
    {"SIMILAR", 2, 2, similar},
    {"RANK", 2, 11, rank},
    {"INFO", 1, 1, info},
    {"LINE", 2, 2, show_line},
    {"STATS", 0, 0, stats},
    {"STOP", 1, 1, stop},
    {"UNSTOP", 1, 1, unstop},
    {"APPEND", 2, 2, append},
    {"DELETE", 1, 1, delete},
};

static int split_arguments(const char *name, char *rest, char **arguments)
{
    if (strcmp(name, "SEARCH") == 0) {
        arguments[0] = rest;
        return 1;
    }
    bool is_append = strcmp(name, "APPEND") == 0;
    int count = 0;
    char *part = rest;
    while (true) {
        char *space = strchr(part, ' ');
        if (count < MAX_ARGUMENTS) {
            arguments[count] = part;
        }
        count++;
        if (space == NULL || (is_append && count == 2)) {
            return count;
        }
        *space = '\0';
        part = space + 1;
    }
}

static void execute(char *line)
{
    char *rest = strchr(line, ' ');
    if (rest != NULL) {
        *rest++ = '\0';
    }
    const Command *command = NULL;
    for (size_t index = 0; index < LENGTH(COMMANDS); index++) {
        if (strcmp(COMMANDS[index].name, line) == 0) {
            command = &COMMANDS[index];
        }
    }
    if (command == NULL) {
        printf("ERROR UNKNOWN COMMAND %s\n", line);
        return;
    }
    char *arguments[MAX_ARGUMENTS];
    int count = rest == NULL ? 0 : split_arguments(command->name, rest, arguments);
    if (count < command->minimum || count > command->maximum) {
        printf("ERROR BAD ARGUMENTS %s\n", command->name);
        return;
    }
    command->handler(arguments, count);
}

static bool read_line(char *line)
{
    if (fgets(line, LINE_CAPACITY, stdin) == NULL) {
        return false;
    }
    line[strcspn(line, "\r\n")] = '\0';
    return true;
}

int main(void)
{
    char line[LINE_CAPACITY];
    if (!read_line(line)) {
        return EXIT_FAILURE;
    }
    strtok(line, " ");
    for (char *word = strtok(NULL, " "); word != NULL; word = strtok(NULL, " ")) {
        add_stopword(word);
    }
    bool more = read_line(line);
    while (more && strncmp(line, "DOC ", 4) == 0) {
        Document *document = create_document(atoi(line + 4));
        while (read_line(line) && strcmp(line, "ENDDOC") != 0) {
            add_line(document, line);
        }
        more = read_line(line);
    }
    while (more && strcmp(line, "END") != 0) {
        execute(line);
        more = read_line(line);
    }
    return EXIT_SUCCESS;
}
