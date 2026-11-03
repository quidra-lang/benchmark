#include <ctype.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_WORD_LENGTH 30
#define MAX_FREQUENCY 1000000
#define MAX_LISTED 20
#define MAX_LIMIT 3
#define MAX_SUGGESTIONS 10
#define REPORT_SIZE 10
#define MAX_ENTRIES 512
#define MAX_COMMANDS 512
#define MAX_LINE 256
#define MAX_TOKENS (MAX_LINE / 2)
#define MAX_OUTPUT (MAX_LINE * (MAX_WORD_LENGTH + 1))
#define TEXT_ARGUMENTS -1

enum { CHECKED, UNKNOWN, CASE, CAPITAL, REPEATS, CORRECTED, COUNTER_COUNT };

static const char *const COUNTER_NAMES[COUNTER_COUNT] = {
    "checked", "unknown", "case", "capital", "repeats", "corrected",
};
static const char *const FINDING_LABELS[COUNTER_COUNT] = {
    [CASE] = "CASE", [CAPITAL] = "CAPITAL", [REPEATS] = "REPEAT",
};
static const char *const ADJACENT_KEYS[26] = {
    "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy", "jkou",
    "hikmnu", "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo", "aw", "deft",
    "adewxz", "fgry", "hijy", "bcfg", "aeqs", "cdsz", "ghtu", "asx",
};
static const char SOUNDEX_DIGITS[] = "01230120022455012623010202";

typedef char Word[MAX_WORD_LENGTH + 1];

typedef struct {
    Word word;
    int frequency;
} Entry;

typedef struct {
    Word source;
    Word target;
} Rule;

typedef struct {
    Entry entries[MAX_ENTRIES];
    int entry_count;
    Word ignored[MAX_ENTRIES];
    int ignored_count;
    Rule rules[MAX_ENTRIES];
    int rule_count;
} Lexicon;

typedef struct {
    const char *name;
    Lexicon *lexicon;
} UndoRecord;

typedef struct {
    char word[MAX_LINE];
    Word correction;
    int count;
} LogEntry;

typedef struct {
    LogEntry *items;
    int count;
    int capacity;
} Log;

typedef struct {
    int number;
    int start;
    int end;
    int gap_start;
    char text[MAX_LINE];
    char word[MAX_LINE];
    bool sentence_start;
    bool repeat;
} Token;

typedef struct {
    int kind;
    const Token *token;
} Finding;

typedef struct {
    const char *word;
    int distance;
    int frequency;
} Candidate;

typedef struct {
    const char *name;
    int arity;
    void (*run)(char **arguments);
} Command;

static Lexicon lexicon;
static bool keyboard;
static int base_limit = 2;
static int suggestion_count = 5;
static UndoRecord undo_history[MAX_COMMANDS];
static int undo_count;
static Log unknown_log;
static Log correction_log;
static int counters[COUNTER_COUNT];
static int table[MAX_LINE + 1][MAX_LINE + 1];

static int min(int first, int second)
{
    return first < second ? first : second;
}

static bool word_argument(const char *text, Word word)
{
    size_t length = strlen(text);
    bool valid = length >= 1 && length <= MAX_WORD_LENGTH;
    for (size_t i = 0; valid && i < length; i++)
        valid = isalpha((unsigned char)text[i]);
    if (!valid) {
        printf("ERROR BAD WORD %s\n", text);
        return false;
    }
    for (size_t i = 0; i <= length; i++)
        word[i] = (char)tolower((unsigned char)text[i]);
    return true;
}

static bool number_argument(const char *text, int minimum, int maximum, int *value)
{
    size_t length = strlen(text);
    bool valid = length >= 1 && length <= 7;
    for (size_t i = 0; valid && i < length; i++)
        valid = isdigit((unsigned char)text[i]);
    if (valid) {
        *value = atoi(text);
        valid = *value >= minimum && *value <= maximum;
    }
    if (!valid)
        printf("ERROR BAD NUMBER %s\n", text);
    return valid;
}

static void decimal_text(long long numerator, long long denominator, int digits, char *text)
{
    long long scale = 1;
    for (int i = 0; i < digits; i++)
        scale *= 10;
    long long value = (2 * numerator * scale + denominator) / (2 * denominator);
    sprintf(text, "%lld.%0*lld", value / scale, digits, value % scale);
}

static bool all_upper(const char *text)
{
    for (; *text != '\0'; text++) {
        if (!isupper((unsigned char)*text))
            return false;
    }
    return true;
}

static void apply_case(const char *token_text, const char *word, char *result)
{
    strcpy(result, word);
    if (strlen(token_text) >= 2 && all_upper(token_text)) {
        for (char *character = result; *character != '\0'; character++)
            *character = (char)toupper((unsigned char)*character);
    } else if (isupper((unsigned char)token_text[0])) {
        result[0] = (char)toupper((unsigned char)result[0]);
    }
}

static bool mixed_case(const char *text)
{
    bool inner_upper = false;
    for (size_t i = 1; text[i] != '\0'; i++) {
        if (isupper((unsigned char)text[i]))
            inner_upper = true;
    }
    return inner_upper && !all_upper(text);
}

static int tokenize(const char *text, Token *tokens)
{
    int count = 0;
    int position = 0;
    int i = 0;
    while (text[i] != '\0') {
        if (!isalpha((unsigned char)text[i])) {
            i++;
            continue;
        }
        Token *token = &tokens[count];
        token->start = i;
        while (isalpha((unsigned char)text[i]))
            i++;
        int length = i - token->start;
        token->number = count + 1;
        token->end = i;
        token->gap_start = position;
        memcpy(token->text, text + token->start, length);
        token->text[length] = '\0';
        for (int k = 0; k <= length; k++)
            token->word[k] = (char)tolower((unsigned char)token->text[k]);
        bool marked = false;
        bool spaces = true;
        for (int k = position; k < token->start; k++) {
            if (strchr(".!?", text[k]) != NULL)
                marked = true;
            if (text[k] != ' ')
                spaces = false;
        }
        token->sentence_start = count == 0 || marked;
        token->repeat = count > 0 && strcmp(token->word, tokens[count - 1].word) == 0 && spaces;
        position = i;
        count++;
    }
    return count;
}

static int gap_cost(void)
{
    return keyboard ? 2 : 1;
}

static int current_limit(void)
{
    return keyboard ? 2 * base_limit : base_limit;
}

static int substitution_cost(char first, char second)
{
    if (first == second)
        return 0;
    if (!keyboard)
        return 1;
    return strchr(ADJACENT_KEYS[first - 'a'], second) != NULL ? 1 : 2;
}

static bool is_swap(const char *first, const char *second, int i, int j)
{
    return i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1];
}

static void fill_table(const char *first, const char *second)
{
    int gap = gap_cost();
    int rows = (int)strlen(first);
    int columns = (int)strlen(second);
    for (int i = 0; i <= rows; i++)
        table[i][0] = i * gap;
    for (int j = 0; j <= columns; j++)
        table[0][j] = j * gap;
    for (int i = 1; i <= rows; i++) {
        for (int j = 1; j <= columns; j++) {
            int best = min(table[i - 1][j] + gap, table[i][j - 1] + gap);
            best = min(best,
                       table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1]));
            if (is_swap(first, second, i, j))
                best = min(best, table[i - 2][j - 2] + 1);
            table[i][j] = best;
        }
    }
}

static int edit_distance(const char *first, const char *second)
{
    fill_table(first, second);
    return table[strlen(first)][strlen(second)];
}

static int prefix_distance(const char *word, const char *other)
{
    fill_table(word, other);
    size_t rows = strlen(word);
    size_t columns = strlen(other);
    int best = table[rows][0];
    for (size_t j = 1; j <= columns; j++)
        best = min(best, table[rows][j]);
    return best;
}

static int edit_operations(const char *first, const char *second, char operations[][12])
{
    fill_table(first, second);
    int gap = gap_cost();
    int count = 0;
    int i = (int)strlen(first);
    int j = (int)strlen(second);
    while (i > 0 || j > 0) {
        if (i >= 1 && j >= 1 &&
            table[i][j] == table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1])) {
            if (first[i - 1] != second[j - 1])
                sprintf(operations[count++], "sub:%c>%c", first[i - 1], second[j - 1]);
            i--;
            j--;
        } else if (is_swap(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1) {
            sprintf(operations[count++], "swap:%c%c", first[i - 2], first[i - 1]);
            i -= 2;
            j -= 2;
        } else if (i >= 1 && table[i][j] == table[i - 1][j] + gap) {
            sprintf(operations[count++], "del:%c", first[i - 1]);
            i--;
        } else {
            sprintf(operations[count++], "ins:%c", second[j - 1]);
            j--;
        }
    }
    return count;
}

static void soundex(const char *word, char code[5])
{
    int length = 0;
    code[length++] = (char)toupper((unsigned char)word[0]);
    char previous = SOUNDEX_DIGITS[word[0] - 'a'];
    for (size_t i = 1; word[i] != '\0'; i++) {
        if (word[i] == 'h' || word[i] == 'w')
            continue;
        char digit = SOUNDEX_DIGITS[word[i] - 'a'];
        if (digit != '0' && digit != previous && length < 4)
            code[length++] = digit;
        previous = digit;
    }
    while (length < 4)
        code[length++] = '0';
    code[4] = '\0';
}

static int find_entry(const char *word)
{
    for (int i = 0; i < lexicon.entry_count; i++) {
        if (strcmp(lexicon.entries[i].word, word) == 0)
            return i;
    }
    return -1;
}

static int find_ignored(const char *word)
{
    for (int i = 0; i < lexicon.ignored_count; i++) {
        if (strcmp(lexicon.ignored[i], word) == 0)
            return i;
    }
    return -1;
}

static int find_rule(const char *word)
{
    for (int i = 0; i < lexicon.rule_count; i++) {
        if (strcmp(lexicon.rules[i].source, word) == 0)
            return i;
    }
    return -1;
}

static bool is_known(const char *word)
{
    return find_entry(word) >= 0 || find_ignored(word) >= 0;
}

static void add_entry(const char *word, int frequency)
{
    Entry *entry = &lexicon.entries[lexicon.entry_count++];
    strcpy(entry->word, word);
    entry->frequency = frequency;
}

static void discard_ignored(const char *word)
{
    int index = find_ignored(word);
    if (index >= 0)
        strcpy(lexicon.ignored[index], lexicon.ignored[--lexicon.ignored_count]);
}

static int require_entry(const char *word)
{
    int index = find_entry(word);
    if (index < 0)
        printf("ERROR NOT FOUND %s\n", word);
    return index;
}

static int compare_frequency(const void *a, const void *b)
{
    const Entry *first = a;
    const Entry *second = b;
    if (first->frequency != second->frequency)
        return second->frequency - first->frequency;
    return strcmp(first->word, second->word);
}

static int compare_words(const void *a, const void *b)
{
    const Entry *first = a;
    const Entry *second = b;
    return strcmp(first->word, second->word);
}

static int compare_rules(const void *a, const void *b)
{
    const Rule *first = a;
    const Rule *second = b;
    return strcmp(first->source, second->source);
}

static int compare_candidates(const void *a, const void *b)
{
    const Candidate *first = a;
    const Candidate *second = b;
    if (first->distance != second->distance)
        return first->distance - second->distance;
    if (first->frequency != second->frequency)
        return second->frequency - first->frequency;
    return strcmp(first->word, second->word);
}

static int compare_log_entries(const void *a, const void *b)
{
    const LogEntry *first = a;
    const LogEntry *second = b;
    if (first->count != second->count)
        return second->count - first->count;
    int order = strcmp(first->word, second->word);
    return order != 0 ? order : strcmp(first->correction, second->correction);
}

static int frequency_order(Entry *order)
{
    memcpy(order, lexicon.entries, lexicon.entry_count * sizeof *order);
    qsort(order, lexicon.entry_count, sizeof *order, compare_frequency);
    return lexicon.entry_count;
}

static int find_candidates(const char *word, Candidate *found)
{
    int limit = current_limit();
    int gap = gap_cost();
    int length = (int)strlen(word);
    int count = 0;
    for (int i = 0; i < lexicon.entry_count; i++) {
        const Entry *entry = &lexicon.entries[i];
        if (strcmp(entry->word, word) == 0 ||
            abs((int)strlen(entry->word) - length) * gap > limit)
            continue;
        int distance = edit_distance(word, entry->word);
        if (distance <= limit)
            found[count++] = (Candidate){entry->word, distance, entry->frequency};
    }
    qsort(found, count, sizeof *found, compare_candidates);
    return count;
}

static const char *correction(const char *word)
{
    if (is_known(word))
        return NULL;
    int rule = find_rule(word);
    if (rule >= 0)
        return lexicon.rules[rule].target;
    Candidate found[MAX_ENTRIES];
    return find_candidates(word, found) > 0 ? found[0].word : NULL;
}

static void record_undo(const char *name)
{
    Lexicon *copy = malloc(sizeof *copy);
    *copy = lexicon;
    undo_history[undo_count++] = (UndoRecord){name, copy};
}

static void log_increment(Log *log, const char *word, const char *correction)
{
    for (int i = 0; i < log->count; i++) {
        LogEntry *item = &log->items[i];
        if (strcmp(item->word, word) == 0 && strcmp(item->correction, correction) == 0) {
            item->count++;
            return;
        }
    }
    if (log->count == log->capacity) {
        log->capacity = log->capacity == 0 ? 16 : 2 * log->capacity;
        log->items = realloc(log->items, log->capacity * sizeof *log->items);
    }
    LogEntry *item = &log->items[log->count++];
    strcpy(item->word, word);
    strcpy(item->correction, correction);
    item->count = 1;
}

static void log_correction(const char *word, const char *replacement)
{
    log_increment(&correction_log, word, replacement);
    counters[CORRECTED]++;
}

static void print_entries(const Entry *entries, int count, int limit)
{
    for (int i = 0; i < count && i < limit; i++)
        printf(" %s:%d", entries[i].word, entries[i].frequency);
    putchar('\n');
}

static void print_unknown_finding(const Token *token)
{
    printf("UNKNOWN %d %s", token->number, token->text);
    int rule = find_rule(token->word);
    if (rule >= 0) {
        printf(" RULE %s\n", lexicon.rules[rule].target);
        return;
    }
    Candidate found[MAX_ENTRIES];
    int count = find_candidates(token->word, found);
    if (count == 0) {
        puts(" NONE");
        return;
    }
    printf(" SUGGEST");
    for (int i = 0; i < count && i < suggestion_count; i++)
        printf(" %s", found[i].word);
    putchar('\n');
}

static void check(char **arguments)
{
    Token tokens[MAX_TOKENS];
    Finding findings[4 * MAX_TOKENS];
    int counts[COUNTER_COUNT] = {0};
    int finding_count = 0;
    int token_count = tokenize(arguments[0], tokens);
    for (int i = 0; i < token_count; i++) {
        const Token *token = &tokens[i];
        bool found[COUNTER_COUNT] = {false};
        found[UNKNOWN] = !is_known(token->word);
        found[CASE] = mixed_case(token->text);
        found[CAPITAL] = token->sentence_start && islower((unsigned char)token->text[0]);
        found[REPEATS] = token->repeat;
        for (int kind = UNKNOWN; kind <= REPEATS; kind++) {
            if (found[kind]) {
                findings[finding_count++] = (Finding){kind, token};
                counts[kind]++;
            }
        }
        if (found[UNKNOWN])
            log_increment(&unknown_log, token->word, "");
    }
    counters[CHECKED] += token_count;
    printf("CHECK words=%d", token_count);
    for (int kind = UNKNOWN; kind <= REPEATS; kind++) {
        counters[kind] += counts[kind];
        printf(" %s=%d", COUNTER_NAMES[kind], counts[kind]);
    }
    putchar('\n');
    for (int i = 0; i < finding_count; i++) {
        const Token *token = findings[i].token;
        if (findings[i].kind == UNKNOWN)
            print_unknown_finding(token);
        else
            printf("%s %d %s\n", FINDING_LABELS[findings[i].kind], token->number, token->text);
    }
}

static void correct(char **arguments)
{
    const char *text = arguments[0];
    Token tokens[MAX_TOKENS];
    int count = tokenize(text, tokens);
    char result[MAX_OUTPUT] = "";
    int position = 0;
    int changed = 0;
    for (int i = 0; i < count; i++) {
        const Token *token = &tokens[i];
        const char *replacement = correction(token->word);
        strncat(result, text + token->gap_start, token->start - token->gap_start);
        if (replacement == NULL) {
            strcat(result, token->text);
        } else {
            Word cased;
            apply_case(token->text, replacement, cased);
            strcat(result, cased);
            log_correction(token->word, replacement);
            changed++;
        }
        position = token->end;
    }
    strcat(result, text + position);
    printf("CORRECT changed=%d: %s\n", changed, result);
}

static void fix(char **arguments)
{
    const char *text = arguments[0];
    Token tokens[MAX_TOKENS];
    int count = tokenize(text, tokens);
    char result[MAX_OUTPUT] = "";
    int position = 0;
    int removed = 0;
    int replaced = 0;
    int recased = 0;
    for (int i = 0; i < count; i++) {
        const Token *token = &tokens[i];
        position = token->end;
        if (token->repeat) {
            removed++;
            continue;
        }
        const char *replacement = correction(token->word);
        char fixed[MAX_LINE];
        apply_case(token->text, replacement == NULL ? token->word : replacement, fixed);
        if (token->sentence_start && islower((unsigned char)fixed[0]))
            fixed[0] = (char)toupper((unsigned char)fixed[0]);
        if (replacement != NULL) {
            log_correction(token->word, replacement);
            replaced++;
        } else if (strcmp(fixed, token->text) != 0) {
            recased++;
        }
        strncat(result, text + token->gap_start, token->start - token->gap_start);
        strcat(result, fixed);
    }
    strcat(result, text + position);
    printf("FIX removed=%d replaced=%d recased=%d: %s\n", removed, replaced, recased, result);
}

static void profile(char **arguments)
{
    Token tokens[MAX_TOKENS];
    int count = tokenize(arguments[0], tokens);
    int distinct = 0;
    int unknown = 0;
    int sentences = 0;
    int characters = 0;
    int longest = 0;
    for (int i = 0; i < count; i++) {
        const Token *token = &tokens[i];
        bool seen = false;
        for (int k = 0; k < i && !seen; k++)
            seen = strcmp(tokens[k].word, token->word) == 0;
        int length = token->end - token->start;
        distinct += !seen;
        unknown += !is_known(token->word);
        sentences += token->sentence_start;
        characters += length;
        if (length > tokens[longest].end - tokens[longest].start)
            longest = i;
    }
    char rate[16] = "0.0";
    char average[16] = "0.00";
    const char *longest_word = "-";
    if (count > 0) {
        decimal_text(100 * unknown, count, 1, rate);
        decimal_text(characters, count, 2, average);
        longest_word = tokens[longest].word;
    }
    printf("PROFILE words=%d distinct=%d unknown=%d rate=%s avglen=%s longest=%s sentences=%d\n",
           count, distinct, unknown, rate, average, longest_word, sentences);
}

static void learn(char **arguments)
{
    record_undo("LEARN");
    Token tokens[MAX_TOKENS];
    int count = tokenize(arguments[0], tokens);
    int updated = 0;
    int added = 0;
    int skipped = 0;
    for (int i = 0; i < count; i++) {
        const char *word = tokens[i].word;
        int index = find_entry(word);
        if (strlen(word) > MAX_WORD_LENGTH) {
            skipped++;
        } else if (index >= 0) {
            lexicon.entries[index].frequency++;
            updated++;
        } else {
            add_entry(word, 1);
            discard_ignored(word);
            added++;
        }
    }
    printf("LEARN updated=%d added=%d skipped=%d\n", updated, added, skipped);
}

static void suggest(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    int rule = find_rule(word);
    if (is_known(word)) {
        printf("SUGGEST %s KNOWN\n", word);
    } else if (rule >= 0) {
        printf("SUGGEST %s RULE %s\n", word, lexicon.rules[rule].target);
    } else {
        Candidate found[MAX_ENTRIES];
        int count = find_candidates(word, found);
        printf("SUGGEST %s found=%d", word, count);
        for (int i = 0; i < count && i < suggestion_count; i++)
            printf(" %s:%d", found[i].word, found[i].distance);
        putchar('\n');
    }
}

static void dist(char **arguments)
{
    Word first;
    Word second;
    if (!word_argument(arguments[0], first) || !word_argument(arguments[1], second))
        return;
    char operations[2 * MAX_WORD_LENGTH][12];
    int count = edit_operations(first, second, operations);
    printf("DIST %s %s %d", first, second, table[strlen(first)][strlen(second)]);
    while (count > 0)
        printf(" %s", operations[--count]);
    putchar('\n');
}

static void soundex_code(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    char code[5];
    soundex(word, code);
    printf("SOUNDEX %s %s\n", word, code);
}

static void sounds(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    char code[5];
    soundex(word, code);
    Entry order[MAX_ENTRIES];
    int total = frequency_order(order);
    const char *matches[MAX_ENTRIES];
    int count = 0;
    for (int i = 0; i < total; i++) {
        char other[5];
        soundex(order[i].word, other);
        if (strcmp(order[i].word, word) != 0 && strcmp(other, code) == 0)
            matches[count++] = order[i].word;
    }
    printf("SOUNDS %s %s count=%d", word, code, count);
    for (int i = 0; i < count && i < REPORT_SIZE; i++)
        printf(" %s", matches[i]);
    putchar('\n');
}

static long long segment(const char *word, int *next)
{
    int length = (int)strlen(word);
    long long ways[MAX_WORD_LENGTH + 1] = {0};
    int counts[MAX_WORD_LENGTH + 1] = {0};
    ways[length] = 1;
    next[length] = length;
    for (int start = length - 1; start >= 0; start--) {
        for (int end = start + 1; end <= length; end++) {
            Word piece;
            memcpy(piece, word + start, end - start);
            piece[end - start] = '\0';
            if (find_entry(piece) < 0 || ways[end] == 0)
                continue;
            if (ways[start] == 0 || counts[end] + 1 < counts[start]) {
                counts[start] = counts[end] + 1;
                next[start] = end;
            }
            ways[start] += ways[end];
        }
    }
    return ways[0];
}

static void split(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    int next[MAX_WORD_LENGTH + 1];
    long long ways = segment(word, next);
    if (ways == 0) {
        printf("SPLIT %s ways=0 -> NONE\n", word);
        return;
    }
    printf("SPLIT %s ways=%lld ->", word, ways);
    int length = (int)strlen(word);
    for (int start = 0; start < length; start = next[start])
        printf(" %.*s", next[start] - start, word + start);
    putchar('\n');
}

static void prefix(char **arguments)
{
    Word word;
    int count;
    if (!word_argument(arguments[0], word) ||
        !number_argument(arguments[1], 1, MAX_LISTED, &count))
        return;
    Entry order[MAX_ENTRIES];
    int total = frequency_order(order);
    size_t length = strlen(word);
    int matches = 0;
    for (int i = 0; i < total; i++) {
        if (strncmp(order[i].word, word, length) == 0)
            order[matches++] = order[i];
    }
    printf("PREFIX %s count=%d", word, matches);
    print_entries(order, matches, count);
}

static void complete(char **arguments)
{
    Word word;
    int count;
    if (!word_argument(arguments[0], word) ||
        !number_argument(arguments[1], 1, MAX_LISTED, &count))
        return;
    int threshold = current_limit() / 2;
    Candidate matches[MAX_ENTRIES];
    int total = 0;
    for (int i = 0; i < lexicon.entry_count; i++) {
        const Entry *entry = &lexicon.entries[i];
        int distance = prefix_distance(word, entry->word);
        if (distance <= threshold)
            matches[total++] = (Candidate){entry->word, distance, entry->frequency};
    }
    qsort(matches, total, sizeof *matches, compare_candidates);
    printf("COMPLETE %s count=%d", word, total);
    for (int i = 0; i < total && i < count; i++)
        printf(" %s:%d", matches[i].word, matches[i].distance);
    putchar('\n');
}

static void list_words(char **arguments)
{
    Word word;
    int count;
    if (!word_argument(arguments[0], word) ||
        !number_argument(arguments[1], 1, MAX_LISTED, &count))
        return;
    Entry matches[MAX_ENTRIES];
    int total = 0;
    for (int i = 0; i < lexicon.entry_count; i++) {
        if (strcmp(lexicon.entries[i].word, word) >= 0)
            matches[total++] = lexicon.entries[i];
    }
    qsort(matches, total, sizeof *matches, compare_words);
    printf("LIST %s count=%d", word, total);
    print_entries(matches, total, count);
}

static void word_info(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    int index = require_entry(word);
    if (index < 0)
        return;
    Entry order[MAX_ENTRIES];
    frequency_order(order);
    int rank = 1;
    while (strcmp(order[rank - 1].word, word) != 0)
        rank++;
    char code[5];
    soundex(word, code);
    Candidate found[MAX_ENTRIES];
    printf("WORD %s freq=%d rank=%d soundex=%s neighbors=%d\n", word,
           lexicon.entries[index].frequency, rank, code, find_candidates(word, found));
}

static void add(char **arguments)
{
    Word word;
    int frequency;
    if (!word_argument(arguments[0], word) ||
        !number_argument(arguments[1], 1, MAX_FREQUENCY, &frequency))
        return;
    if (find_entry(word) >= 0) {
        printf("ERROR DUPLICATE %s\n", word);
        return;
    }
    record_undo("ADD");
    add_entry(word, frequency);
    discard_ignored(word);
    printf("ADD %s %d\n", word, frequency);
}

static void remove_word(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    int index = require_entry(word);
    if (index < 0)
        return;
    int frequency = lexicon.entries[index].frequency;
    record_undo("REMOVE");
    lexicon.entries[index] = lexicon.entries[--lexicon.entry_count];
    printf("REMOVE %s %d\n", word, frequency);
}

static void ignore(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    if (find_entry(word) >= 0) {
        printf("ERROR IN DICTIONARY %s\n", word);
        return;
    }
    if (find_ignored(word) >= 0) {
        printf("ERROR ALREADY IGNORED %s\n", word);
        return;
    }
    record_undo("IGNORE");
    strcpy(lexicon.ignored[lexicon.ignored_count++], word);
    printf("IGNORE %s\n", word);
}

static void unignore(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    if (find_ignored(word) < 0) {
        printf("ERROR NOT IGNORED %s\n", word);
        return;
    }
    record_undo("UNIGNORE");
    discard_ignored(word);
    printf("UNIGNORE %s\n", word);
}

static void rule(char **arguments)
{
    Word source;
    Word target;
    if (!word_argument(arguments[0], source) || !word_argument(arguments[1], target))
        return;
    if (find_entry(source) >= 0) {
        printf("ERROR IN DICTIONARY %s\n", source);
        return;
    }
    if (find_entry(target) < 0) {
        printf("ERROR NOT FOUND %s\n", target);
        return;
    }
    record_undo("RULE");
    int index = find_rule(source);
    if (index < 0) {
        Rule *added = &lexicon.rules[lexicon.rule_count++];
        strcpy(added->source, source);
        strcpy(added->target, target);
        printf("RULE %s %s\n", source, target);
    } else {
        printf("RULE %s %s REPLACED %s\n", source, target, lexicon.rules[index].target);
        strcpy(lexicon.rules[index].target, target);
    }
}

static void unrule(char **arguments)
{
    Word word;
    if (!word_argument(arguments[0], word))
        return;
    int index = find_rule(word);
    if (index < 0) {
        printf("ERROR NO RULE %s\n", word);
        return;
    }
    record_undo("UNRULE");
    printf("UNRULE %s %s\n", word, lexicon.rules[index].target);
    lexicon.rules[index] = lexicon.rules[--lexicon.rule_count];
}

static void show_rules(char **arguments)
{
    (void)arguments;
    Rule sorted[MAX_ENTRIES];
    memcpy(sorted, lexicon.rules, lexicon.rule_count * sizeof *sorted);
    qsort(sorted, lexicon.rule_count, sizeof *sorted, compare_rules);
    printf("RULES count=%d", lexicon.rule_count);
    for (int i = 0; i < lexicon.rule_count; i++)
        printf(" %s>%s", sorted[i].source, sorted[i].target);
    putchar('\n');
}

static void keyboard_mode(char **arguments)
{
    const char *mode = arguments[0];
    if (strcmp(mode, "ON") != 0 && strcmp(mode, "OFF") != 0) {
        printf("ERROR BAD MODE %s\n", mode);
        return;
    }
    keyboard = strcmp(mode, "ON") == 0;
    printf("KEYBOARD %s\n", mode);
}

static void set_option(char **arguments)
{
    const char *option = arguments[0];
    bool is_limit = strcmp(option, "LIMIT") == 0;
    if (!is_limit && strcmp(option, "SUGGESTIONS") != 0) {
        printf("ERROR BAD OPTION %s\n", option);
        return;
    }
    int value;
    if (!number_argument(arguments[1], 1, is_limit ? MAX_LIMIT : MAX_SUGGESTIONS, &value))
        return;
    if (is_limit)
        base_limit = value;
    else
        suggestion_count = value;
    printf("SET %s %d\n", option, value);
}

static void undo(char **arguments)
{
    (void)arguments;
    if (undo_count == 0) {
        puts("ERROR NOTHING TO UNDO");
        return;
    }
    UndoRecord record = undo_history[--undo_count];
    lexicon = *record.lexicon;
    free(record.lexicon);
    printf("UNDO %s\n", record.name);
}

static void report(char **arguments)
{
    (void)arguments;
    qsort(unknown_log.items, unknown_log.count, sizeof *unknown_log.items, compare_log_entries);
    printf("REPORT distinct=%d", unknown_log.count);
    for (int i = 0; i < unknown_log.count && i < REPORT_SIZE; i++)
        printf(" %s:%d", unknown_log.items[i].word, unknown_log.items[i].count);
    putchar('\n');
}

static void history(char **arguments)
{
    (void)arguments;
    qsort(correction_log.items, correction_log.count, sizeof *correction_log.items,
          compare_log_entries);
    printf("HISTORY distinct=%d", correction_log.count);
    for (int i = 0; i < correction_log.count && i < REPORT_SIZE; i++) {
        const LogEntry *item = &correction_log.items[i];
        printf(" %s>%s:%d", item->word, item->correction, item->count);
    }
    putchar('\n');
}

static void stats(char **arguments)
{
    (void)arguments;
    Entry order[MAX_ENTRIES];
    int count = frequency_order(order);
    int total = 0;
    int characters = 0;
    for (int i = 0; i < count; i++) {
        total += order[i].frequency;
        characters += (int)strlen(order[i].word);
    }
    char average[16];
    decimal_text(characters, count, 2, average);
    printf("STATS words=%d total=%d avglen=%s top=%s:%d ignored=%d rules=%d keyboard=%s "
           "limit=%d suggestions=%d undo=%d\n",
           count, total, average, order[0].word, order[0].frequency, lexicon.ignored_count,
           lexicon.rule_count, keyboard ? "ON" : "OFF", current_limit(), suggestion_count,
           undo_count);
    printf("SESSION");
    for (int i = 0; i < COUNTER_COUNT; i++)
        printf(" %s=%d", COUNTER_NAMES[i], counters[i]);
    putchar('\n');
}

static const Command COMMANDS[] = {
    {"CHECK", TEXT_ARGUMENTS, check},
    {"CORRECT", TEXT_ARGUMENTS, correct},
    {"FIX", TEXT_ARGUMENTS, fix},
    {"PROFILE", TEXT_ARGUMENTS, profile},
    {"LEARN", TEXT_ARGUMENTS, learn},
    {"SUGGEST", 1, suggest},
    {"DIST", 2, dist},
    {"SOUNDEX", 1, soundex_code},
    {"SOUNDS", 1, sounds},
    {"SPLIT", 1, split},
    {"PREFIX", 2, prefix},
    {"COMPLETE", 2, complete},
    {"LIST", 2, list_words},
    {"WORD", 1, word_info},
    {"ADD", 2, add},
    {"REMOVE", 1, remove_word},
    {"IGNORE", 1, ignore},
    {"UNIGNORE", 1, unignore},
    {"RULE", 2, rule},
    {"UNRULE", 1, unrule},
    {"RULES", 0, show_rules},
    {"KEYBOARD", 1, keyboard_mode},
    {"SET", 2, set_option},
    {"UNDO", 0, undo},
    {"REPORT", 0, report},
    {"HISTORY", 0, history},
    {"STATS", 0, stats},
};

static void execute(char *line)
{
    char *rest = strchr(line, ' ');
    if (rest != NULL)
        *rest++ = '\0';
    const Command *command = NULL;
    for (size_t i = 0; i < sizeof COMMANDS / sizeof COMMANDS[0]; i++) {
        if (strcmp(COMMANDS[i].name, line) == 0)
            command = &COMMANDS[i];
    }
    if (command == NULL) {
        printf("ERROR UNKNOWN COMMAND %s\n", line);
        return;
    }
    char *arguments[MAX_LINE];
    int count = 0;
    if (rest != NULL) {
        arguments[count++] = rest;
        if (command->arity != TEXT_ARGUMENTS) {
            for (char *space = strchr(rest, ' '); space != NULL; space = strchr(space + 1, ' ')) {
                *space = '\0';
                arguments[count++] = space + 1;
            }
        }
    }
    int expected = command->arity == TEXT_ARGUMENTS ? 1 : command->arity;
    if (count != expected) {
        printf("ERROR BAD ARGUMENTS %s\n", command->name);
        return;
    }
    command->run(arguments);
}

static void read_line(char *line)
{
    if (fgets(line, MAX_LINE, stdin) == NULL)
        line[0] = '\0';
    line[strcspn(line, "\n")] = '\0';
}

int main(void)
{
    char line[MAX_LINE];
    read_line(line);
    int word_count = atoi(line);
    for (int i = 0; i < word_count; i++) {
        read_line(line);
        Entry *entry = &lexicon.entries[lexicon.entry_count++];
        sscanf(line, "%30s %d", entry->word, &entry->frequency);
    }
    read_line(line);
    int command_count = atoi(line);
    for (int i = 0; i < command_count; i++) {
        read_line(line);
        execute(line);
    }
    return 0;
}
