#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE_CAPACITY 256
#define MAX_WORDS 16
#define MAX_DATA_LINES 60
#define MAX_FILES 300
#define NAME_CAPACITY 16
#define RANGE_CAPACITY 24
#define GRAPH_WIDTH 20
#define SEPARATOR "======="

enum { ICASE = 1, IWHITE = 2, ISPACE = 4 };

static const int OFFSETS[] = {0, 1, -1, 2, -2, 3, -3};
#define OFFSET_COUNT ((int)(sizeof OFFSETS / sizeof OFFSETS[0]))

typedef struct {
    char **items;
    int count;
} Span;

typedef struct {
    char **items;
    int count;
    int capacity;
} Lines;

typedef struct {
    int first;
    int second;
} Pair;

typedef struct {
    int p, q, x, y;
} ChangeBlock;

typedef struct {
    ChangeBlock *items;
    int count;
} Blocks;

typedef struct {
    int old_index;
    int new_index;
    const ChangeBlock *block;
} Step;

typedef struct {
    const ChangeBlock *blocks;
    int block_count;
    int old_start, old_count;
    int new_start, new_count;
} Hunk;

typedef struct {
    Span old;
    Span new;
    Blocks blocks;
} LineDiff;

typedef struct {
    int deleted;
    int inserted;
    int common;
} TokenTotals;

typedef struct {
    char kind;
    char *text;
} BodyLine;

typedef struct {
    int line_number;
    int old_start, old_count;
    int new_start, new_count;
    BodyLine body[MAX_DATA_LINES];
    int body_count;
} PatchHunk;

typedef struct {
    int fuzz;
    int delta;
    int position;
    Lines lines;
} HunkMatch;

typedef enum { KIND_STABLE, KIND_A, KIND_B, KIND_BOTH, KIND_CONFLICT, KIND_COUNT } ChunkKind;

static const char *const KIND_NAMES[] = {"stable", "a", "b", "both", "conflict"};

typedef struct {
    ChunkKind kind;
    int base_start, ours_start, theirs_start;
    Span base, ours, theirs;
} Chunk;

typedef enum { NOT_MARKER, START_MARKER, BASE_MARKER, SEPARATOR_MARKER, END_MARKER } Marker;

typedef struct {
    int start, end;
    Span ours, base, theirs;
    bool has_base;
} ConflictRegion;

typedef struct {
    bool exists;
    Lines content;
} State;

typedef struct {
    char name[NAME_CAPACITY];
    bool exists;
    Lines content;
    State *history;
    int history_count;
    int history_capacity;
} File;

typedef void (*Handler)(char **arguments, int argument_count, Span data);

typedef struct {
    const char *name;
    bool has_data;
    Handler handler;
} Command;

static File files[MAX_FILES];
static int file_count;

static int min_int(int a, int b)
{
    return a < b ? a : b;
}

static int max_int(int a, int b)
{
    return a > b ? a : b;
}

static char *copy_range(const char *text, size_t length)
{
    char *copy = malloc(length + 1);
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
    char *text = malloc((size_t)length + 1);
    va_start(arguments, format);
    vsnprintf(text, (size_t)length + 1, format, arguments);
    va_end(arguments);
    return text;
}

static void free_strings(char **strings, int count)
{
    for (int i = 0; i < count; i++) {
        free(strings[i]);
    }
    free(strings);
}

static int split_words(char *text, char **words, int capacity)
{
    int count = 0;
    while (count < capacity) {
        words[count++] = text;
        char *space = strchr(text, ' ');
        if (space == NULL) {
            break;
        }
        *space = '\0';
        text = space + 1;
    }
    return count;
}

static Span span_of(const Lines *lines)
{
    return (Span){lines->items, lines->count};
}

static Span slice(Span span, int start, int end)
{
    return (Span){span.items + start, end - start};
}

static bool spans_equal(Span first, Span second)
{
    if (first.count != second.count) {
        return false;
    }
    for (int i = 0; i < first.count; i++) {
        if (strcmp(first.items[i], second.items[i]) != 0) {
            return false;
        }
    }
    return true;
}

static void lines_push(Lines *lines, char *line)
{
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity > 0 ? lines->capacity * 2 : 8;
        lines->items = realloc(lines->items, (size_t)lines->capacity * sizeof *lines->items);
    }
    lines->items[lines->count++] = line;
}

static void lines_append(Lines *lines, Span span)
{
    for (int i = 0; i < span.count; i++) {
        lines_push(lines, span.items[i]);
    }
}

static Lines lines_from(Span span)
{
    Lines lines = {0};
    lines_append(&lines, span);
    return lines;
}

static Lines lines_replaced(Span lines, int start, int remove_count, Span insertion)
{
    Lines result = {0};
    lines_append(&result, slice(lines, 0, start));
    lines_append(&result, insertion);
    lines_append(&result, slice(lines, start + remove_count, lines.count));
    return result;
}

static void lines_free(Lines *lines)
{
    free(lines->items);
    *lines = (Lines){0};
}

static void print_lines(const char *prefix, Span lines)
{
    for (int i = 0; i < lines.count; i++) {
        printf("%s%s\n", prefix, lines.items[i]);
    }
}

static char *range_r(char *buffer, int start, int count)
{
    if (count >= 2) {
        snprintf(buffer, RANGE_CAPACITY, "%d,%d", start + 1, start + count);
    } else {
        snprintf(buffer, RANGE_CAPACITY, "%d", count == 1 ? start + 1 : start);
    }
    return buffer;
}

static char *range_u(char *buffer, int start, int count)
{
    if (count >= 2) {
        snprintf(buffer, RANGE_CAPACITY, "%d,%d", start + 1, count);
    } else if (count == 1) {
        snprintf(buffer, RANGE_CAPACITY, "%d", start + 1);
    } else {
        snprintf(buffer, RANGE_CAPACITY, "%d,0", start);
    }
    return buffer;
}

static char *comparison_key(const char *line, unsigned options)
{
    char *key = malloc(strlen(line) + 1);
    size_t length = 0;
    for (const char *c = line; *c != '\0'; c++) {
        char character = (options & ICASE) ? (char)tolower((unsigned char)*c) : *c;
        if (character == ' ') {
            if ((options & IWHITE) || ((options & ISPACE) && length > 0 && key[length - 1] == ' ')) {
                continue;
            }
        }
        key[length++] = character;
    }
    key[length] = '\0';
    return key;
}

static char **comparison_keys(Span lines, unsigned options)
{
    char **keys = malloc((size_t)lines.count * sizeof *keys);
    for (int i = 0; i < lines.count; i++) {
        keys[i] = comparison_key(lines.items[i], options);
    }
    return keys;
}

static Pair *matched_pairs(Span first, Span second, int *pair_count)
{
    int rows = first.count, columns = second.count, width = columns + 1;
    int *table = calloc((size_t)(rows + 1) * (size_t)width, sizeof *table);
    for (int i = 1; i <= rows; i++) {
        for (int j = 1; j <= columns; j++) {
            if (strcmp(first.items[i - 1], second.items[j - 1]) == 0) {
                table[i * width + j] = table[(i - 1) * width + j - 1] + 1;
            } else {
                table[i * width + j] = max_int(table[(i - 1) * width + j], table[i * width + j - 1]);
            }
        }
    }
    Pair *pairs = malloc((size_t)(min_int(rows, columns) + 2) * sizeof *pairs);
    int count = 0;
    pairs[count++] = (Pair){rows + 1, columns + 1};
    int i = rows, j = columns;
    while (i >= 1 && j >= 1) {
        if (strcmp(first.items[i - 1], second.items[j - 1]) == 0) {
            pairs[count++] = (Pair){i, j};
            i--;
            j--;
        } else if (table[(i - 1) * width + j] >= table[i * width + j - 1]) {
            i--;
        } else {
            j--;
        }
    }
    pairs[count++] = (Pair){0, 0};
    for (int k = 0; k < count / 2; k++) {
        Pair swap = pairs[k];
        pairs[k] = pairs[count - 1 - k];
        pairs[count - 1 - k] = swap;
    }
    free(table);
    *pair_count = count;
    return pairs;
}

static Blocks change_blocks(Span first, Span second)
{
    int pair_count;
    Pair *pairs = matched_pairs(first, second, &pair_count);
    Blocks blocks = {malloc((size_t)pair_count * sizeof(ChangeBlock)), 0};
    for (int k = 0; k + 1 < pair_count; k++) {
        Pair current = pairs[k], next = pairs[k + 1];
        if (next.first - current.first > 1 || next.second - current.second > 1) {
            blocks.items[blocks.count++] = (ChangeBlock){
                current.first,
                current.second,
                next.first - current.first - 1,
                next.second - current.second - 1,
            };
        }
    }
    free(pairs);
    return blocks;
}

static char block_letter(const ChangeBlock *block)
{
    if (block->x >= 1 && block->y >= 1) {
        return 'c';
    }
    return block->y == 0 ? 'd' : 'a';
}

static Step *walk(const ChangeBlock *blocks, int block_count, int old_start, int new_start,
                  int old_end, int *step_count)
{
    Step *steps = malloc((size_t)(old_end - old_start + block_count + 1) * sizeof *steps);
    int count = 0, old_index = old_start, new_index = new_start;
    for (int k = 0; k < block_count; k++) {
        const ChangeBlock *block = &blocks[k];
        while (old_index < block->p) {
            steps[count++] = (Step){old_index, new_index, NULL};
            old_index++;
            new_index++;
        }
        steps[count++] = (Step){old_index, new_index, block};
        old_index = block->p + block->x;
        new_index = block->q + block->y;
    }
    while (old_index < old_end) {
        steps[count++] = (Step){old_index, new_index, NULL};
        old_index++;
        new_index++;
    }
    *step_count = count;
    return steps;
}

static LineDiff line_diff(Span old, Span new, unsigned options)
{
    char **old_keys = comparison_keys(old, options);
    char **new_keys = comparison_keys(new, options);
    LineDiff diff = {old, new, change_blocks((Span){old_keys, old.count}, (Span){new_keys, new.count})};
    free_strings(old_keys, old.count);
    free_strings(new_keys, new.count);
    return diff;
}

static Span deleted_lines(const LineDiff *diff, const ChangeBlock *block)
{
    return slice(diff->old, block->p, block->p + block->x);
}

static Span inserted_lines(const LineDiff *diff, const ChangeBlock *block)
{
    return slice(diff->new, block->q, block->q + block->y);
}

static int build_hunks(const LineDiff *diff, int context, Hunk *hunks)
{
    int count = 0;
    for (int k = 0; k < diff->blocks.count; k++) {
        const ChangeBlock *block = &diff->blocks.items[k];
        if (count > 0) {
            Hunk *hunk = &hunks[count - 1];
            const ChangeBlock *previous = &hunk->blocks[hunk->block_count - 1];
            if (block->p - (previous->p + previous->x) <= 2 * context) {
                hunk->block_count++;
                continue;
            }
        }
        hunks[count++] = (Hunk){.blocks = block, .block_count = 1};
    }
    for (int h = 0; h < count; h++) {
        Hunk *hunk = &hunks[h];
        const ChangeBlock *first = &hunk->blocks[0];
        const ChangeBlock *last = &hunk->blocks[hunk->block_count - 1];
        int before = min_int(context, first->p);
        int after = min_int(context, diff->old.count - last->p - last->x);
        hunk->old_start = first->p - before;
        hunk->old_count = last->p + last->x + after - hunk->old_start;
        hunk->new_start = first->q - before;
        hunk->new_count = last->q + last->y + after - hunk->new_start;
    }
    return count;
}

static Step *hunk_steps(const Hunk *hunk, int *step_count)
{
    return walk(hunk->blocks, hunk->block_count, hunk->old_start, hunk->new_start,
                hunk->old_start + hunk->old_count, step_count);
}

static void print_normal(const LineDiff *diff)
{
    for (int k = 0; k < diff->blocks.count; k++) {
        const ChangeBlock *block = &diff->blocks.items[k];
        char letter = block_letter(block);
        char old_range[RANGE_CAPACITY], new_range[RANGE_CAPACITY];
        printf("%s%c%s\n", range_r(old_range, block->p, block->x), letter,
               range_r(new_range, block->q, block->y));
        print_lines("< ", deleted_lines(diff, block));
        if (letter == 'c') {
            puts("---");
        }
        print_lines("> ", inserted_lines(diff, block));
    }
}

static void print_ed(const LineDiff *diff)
{
    for (int k = diff->blocks.count - 1; k >= 0; k--) {
        const ChangeBlock *block = &diff->blocks.items[k];
        char letter = block_letter(block);
        char range[RANGE_CAPACITY];
        printf("%s%c\n", range_r(range, block->p, block->x), letter);
        if (letter != 'd') {
            print_lines("", inserted_lines(diff, block));
            puts(".");
        }
    }
}

static void print_rcs(const LineDiff *diff)
{
    for (int k = 0; k < diff->blocks.count; k++) {
        const ChangeBlock *block = &diff->blocks.items[k];
        if (block->x >= 1) {
            printf("d%d %d\n", block->p + 1, block->x);
        }
        if (block->y >= 1) {
            printf("a%d %d\n", block->p + block->x, block->y);
            print_lines("", inserted_lines(diff, block));
        }
    }
}

static void print_ifdef(const LineDiff *diff, const char *macro)
{
    int step_count;
    Step *steps = walk(diff->blocks.items, diff->blocks.count, 0, 0, diff->old.count, &step_count);
    for (int s = 0; s < step_count; s++) {
        const ChangeBlock *block = steps[s].block;
        if (block == NULL) {
            puts(diff->old.items[steps[s].old_index]);
        } else if (block->x >= 1 && block->y >= 1) {
            printf("#ifndef %s\n", macro);
            print_lines("", deleted_lines(diff, block));
            printf("#else /* %s */\n", macro);
            print_lines("", inserted_lines(diff, block));
            printf("#endif /* %s */\n", macro);
        } else if (block->y == 0) {
            printf("#ifndef %s\n", macro);
            print_lines("", deleted_lines(diff, block));
            printf("#endif /* ! %s */\n", macro);
        } else {
            printf("#ifdef %s\n", macro);
            print_lines("", inserted_lines(diff, block));
            printf("#endif /* %s */\n", macro);
        }
    }
    free(steps);
}

static void print_unified(const LineDiff *diff, int context, const char *old_name,
                          const char *new_name)
{
    printf("--- %s\n+++ %s\n", old_name, new_name);
    Hunk *hunks = malloc((size_t)diff->blocks.count * sizeof *hunks);
    int hunk_count = build_hunks(diff, context, hunks);
    for (int h = 0; h < hunk_count; h++) {
        const Hunk *hunk = &hunks[h];
        char old_range[RANGE_CAPACITY], new_range[RANGE_CAPACITY];
        printf("@@ -%s +%s @@\n", range_u(old_range, hunk->old_start, hunk->old_count),
               range_u(new_range, hunk->new_start, hunk->new_count));
        int step_count;
        Step *steps = hunk_steps(hunk, &step_count);
        for (int s = 0; s < step_count; s++) {
            const ChangeBlock *block = steps[s].block;
            if (block == NULL) {
                printf(" %s\n", diff->old.items[steps[s].old_index]);
            } else {
                print_lines("-", deleted_lines(diff, block));
                print_lines("+", inserted_lines(diff, block));
            }
        }
        free(steps);
    }
    free(hunks);
}

static bool hunk_has_deletions(const Hunk *hunk)
{
    for (int k = 0; k < hunk->block_count; k++) {
        if (hunk->blocks[k].x >= 1) {
            return true;
        }
    }
    return false;
}

static bool hunk_has_insertions(const Hunk *hunk)
{
    for (int k = 0; k < hunk->block_count; k++) {
        if (hunk->blocks[k].y >= 1) {
            return true;
        }
    }
    return false;
}

static void print_context(const LineDiff *diff, int context, const char *old_name,
                          const char *new_name)
{
    printf("*** %s\n--- %s\n", old_name, new_name);
    Hunk *hunks = malloc((size_t)diff->blocks.count * sizeof *hunks);
    int hunk_count = build_hunks(diff, context, hunks);
    for (int h = 0; h < hunk_count; h++) {
        const Hunk *hunk = &hunks[h];
        int step_count;
        Step *steps = hunk_steps(hunk, &step_count);
        char range[RANGE_CAPACITY];
        puts("***************");
        printf("*** %s ****\n", range_r(range, hunk->old_start, hunk->old_count));
        if (hunk_has_deletions(hunk)) {
            for (int s = 0; s < step_count; s++) {
                const ChangeBlock *block = steps[s].block;
                if (block == NULL) {
                    printf("  %s\n", diff->old.items[steps[s].old_index]);
                } else {
                    print_lines(block->y >= 1 ? "! " : "- ", deleted_lines(diff, block));
                }
            }
        }
        printf("--- %s ----\n", range_r(range, hunk->new_start, hunk->new_count));
        if (hunk_has_insertions(hunk)) {
            for (int s = 0; s < step_count; s++) {
                const ChangeBlock *block = steps[s].block;
                if (block == NULL) {
                    printf("  %s\n", diff->new.items[steps[s].new_index]);
                } else {
                    print_lines(block->x >= 1 ? "! " : "+ ", inserted_lines(diff, block));
                }
            }
        }
        free(steps);
    }
    free(hunks);
}

static void print_side_row(const char *left, char symbol, const char *right, int width)
{
    char row[LINE_CAPACITY];
    int length = snprintf(row, sizeof row, "%-*.*s %c %.*s", width, width, left, symbol, width,
                          right);
    while (length > 0 && row[length - 1] == ' ') {
        length--;
    }
    printf("%.*s\n", length, row);
}

static void print_side_by_side(const LineDiff *diff, int width)
{
    int step_count;
    Step *steps = walk(diff->blocks.items, diff->blocks.count, 0, 0, diff->old.count, &step_count);
    for (int s = 0; s < step_count; s++) {
        const ChangeBlock *block = steps[s].block;
        if (block == NULL) {
            print_side_row(diff->old.items[steps[s].old_index], ' ',
                           diff->new.items[steps[s].new_index], width);
            continue;
        }
        for (int row = 0; row < max_int(block->x, block->y); row++) {
            if (row < block->x && row < block->y) {
                print_side_row(diff->old.items[block->p + row], '|', diff->new.items[block->q + row],
                               width);
            } else if (row < block->x) {
                print_side_row(diff->old.items[block->p + row], '<', "", width);
            } else {
                print_side_row("", '>', diff->new.items[block->q + row], width);
            }
        }
    }
    free(steps);
}

static Lines split_tokens(const char *line, bool by_word)
{
    Lines tokens = {0};
    const char *c = line;
    while (*c != '\0') {
        if (!by_word) {
            lines_push(&tokens, copy_range(c, 1));
            c++;
        } else if (*c == ' ') {
            c++;
        } else {
            size_t length = strcspn(c, " ");
            lines_push(&tokens, copy_range(c, length));
            c += length;
        }
    }
    return tokens;
}

static void print_joined(Span tokens, const char *separator)
{
    for (int i = 0; i < tokens.count; i++) {
        if (i > 0) {
            fputs(separator, stdout);
        }
        fputs(tokens.items[i], stdout);
    }
}

static void print_deletion(Span tokens, const char *separator)
{
    fputs("[-", stdout);
    print_joined(tokens, separator);
    fputs("-]", stdout);
}

static void print_insertion(Span tokens, const char *separator)
{
    fputs("{+", stdout);
    print_joined(tokens, separator);
    fputs("+}", stdout);
}

static void print_token_comparison(Span old_tokens, Span new_tokens, const char *separator,
                                   TokenTotals *totals)
{
    Blocks blocks = change_blocks(old_tokens, new_tokens);
    int step_count;
    Step *steps = walk(blocks.items, blocks.count, 0, 0, old_tokens.count, &step_count);
    for (int s = 0; s < step_count; s++) {
        const ChangeBlock *block = steps[s].block;
        if (s > 0) {
            fputs(separator, stdout);
        }
        if (block == NULL) {
            fputs(old_tokens.items[steps[s].old_index], stdout);
            totals->common++;
            continue;
        }
        if (block->x >= 1) {
            print_deletion(slice(old_tokens, block->p, block->p + block->x), separator);
        }
        if (block->x >= 1 && block->y >= 1) {
            fputs(separator, stdout);
        }
        if (block->y >= 1) {
            print_insertion(slice(new_tokens, block->q, block->q + block->y), separator);
        }
        totals->deleted += block->x;
        totals->inserted += block->y;
    }
    free(steps);
    free(blocks.items);
}

static bool parse_number(const char *text, size_t length, int *value)
{
    if (length < 1 || length > 4) {
        return false;
    }
    int result = 0;
    for (size_t i = 0; i < length; i++) {
        if (!isdigit((unsigned char)text[i])) {
            return false;
        }
        result = result * 10 + (text[i] - '0');
    }
    *value = result;
    return true;
}

static bool parse_number_pair(const char *text, size_t length, int *first, int *second,
                              bool *has_second)
{
    const char *comma = memchr(text, ',', length);
    *has_second = comma != NULL;
    if (comma == NULL) {
        return parse_number(text, length, first);
    }
    size_t first_length = (size_t)(comma - text);
    return parse_number(text, first_length, first) &&
           parse_number(comma + 1, length - first_length - 1, second);
}

static bool parse_range(const char *text, char sign, int *start, int *count)
{
    bool has_count;
    if (text[0] != sign || !parse_number_pair(text + 1, strlen(text + 1), start, count, &has_count)) {
        return false;
    }
    if (!has_count) {
        *count = 1;
    }
    return *start != 0 || *count == 0;
}

static bool parse_hunk_header(const char *line, int line_number, PatchHunk *hunk)
{
    char buffer[LINE_CAPACITY];
    char *parts[5];
    snprintf(buffer, sizeof buffer, "%s", line);
    int count = split_words(buffer, parts, 5);
    if (count != 4 || strcmp(parts[0], "@@") != 0 || strcmp(parts[3], "@@") != 0) {
        return false;
    }
    hunk->line_number = line_number;
    hunk->body_count = 0;
    return parse_range(parts[1], '-', &hunk->old_start, &hunk->old_count) &&
           parse_range(parts[2], '+', &hunk->new_start, &hunk->new_count);
}

static bool hunk_has_changes(const PatchHunk *hunk)
{
    for (int i = 0; i < hunk->body_count; i++) {
        if (hunk->body[i].kind != ' ') {
            return true;
        }
    }
    return false;
}

static const char *parse_patch(Span patch, PatchHunk *hunks, int *hunk_count, int *error_line)
{
    int index = 0;
    while (index < patch.count && strncmp(patch.items[index], "@@", 2) != 0) {
        index++;
    }
    *error_line = 0;
    if (index == patch.count) {
        return "no hunks";
    }
    *hunk_count = 0;
    while (index < patch.count) {
        PatchHunk *hunk = &hunks[(*hunk_count)++];
        if (!parse_hunk_header(patch.items[index], index + 1, hunk)) {
            *error_line = index + 1;
            return "bad hunk header";
        }
        index++;
        int old_seen = 0, new_seen = 0;
        while (old_seen < hunk->old_count || new_seen < hunk->new_count) {
            if (index == patch.count) {
                *error_line = hunk->line_number;
                return "truncated hunk";
            }
            char *line = patch.items[index];
            char kind = line[0];
            bool in_old = kind == ' ' || kind == '-';
            bool in_new = kind == ' ' || kind == '+';
            if (strlen(line) < 2 || !(in_old || in_new) || (in_old && old_seen == hunk->old_count) ||
                (in_new && new_seen == hunk->new_count)) {
                *error_line = index + 1;
                return "bad hunk line";
            }
            hunk->body[hunk->body_count++] = (BodyLine){kind, line + 1};
            if (in_old) {
                old_seen++;
            }
            if (in_new) {
                new_seen++;
            }
            index++;
        }
        if (!hunk_has_changes(hunk)) {
            *error_line = hunk->line_number;
            return "no changes";
        }
    }
    return NULL;
}

static int hunk_texts(const PatchHunk *hunk, char change_kind, char **texts)
{
    int count = 0;
    for (int i = 0; i < hunk->body_count; i++) {
        if (hunk->body[i].kind == ' ' || hunk->body[i].kind == change_kind) {
            texts[count++] = hunk->body[i].text;
        }
    }
    return count;
}

static int old_sequence(const PatchHunk *hunk, bool reverse, char **texts)
{
    return hunk_texts(hunk, reverse ? '+' : '-', texts);
}

static int new_sequence(const PatchHunk *hunk, bool reverse, char **texts)
{
    return hunk_texts(hunk, reverse ? '-' : '+', texts);
}

static int hunk_start(const PatchHunk *hunk, bool reverse)
{
    return reverse ? hunk->new_start : hunk->old_start;
}

static int leading_context(const PatchHunk *hunk)
{
    int count = 0;
    while (count < hunk->body_count && hunk->body[count].kind == ' ') {
        count++;
    }
    return count;
}

static int trailing_context(const PatchHunk *hunk)
{
    int count = 0;
    while (count < hunk->body_count && hunk->body[hunk->body_count - 1 - count].kind == ' ') {
        count++;
    }
    return count;
}

static bool search_hunk(const PatchHunk *hunk, Span lines, int adjustment, bool reverse,
                        int max_fuzz, HunkMatch *match)
{
    char *old[MAX_DATA_LINES], *new[MAX_DATA_LINES];
    int old_count = old_sequence(hunk, reverse, old);
    int new_count = new_sequence(hunk, reverse, new);
    int start = hunk_start(hunk, reverse);
    int expected = old_count > 0 ? start - 1 + adjustment : start + adjustment;
    int leading = leading_context(hunk), trailing = trailing_context(hunk);
    for (int fuzz = 0; fuzz <= max_fuzz; fuzz++) {
        int head = min_int(fuzz, leading), tail = min_int(fuzz, trailing);
        Span old_part = {old + head, old_count - head - tail};
        Span new_part = {new + head, new_count - head - tail};
        for (int k = 0; k < OFFSET_COUNT; k++) {
            int position = expected + head + OFFSETS[k];
            int end = position + old_part.count;
            if (position < 0 || end > lines.count ||
                !spans_equal(slice(lines, position, end), old_part)) {
                continue;
            }
            Lines result = lines_replaced(lines, position, old_part.count, new_part);
            *match = (HunkMatch){fuzz, OFFSETS[k], position, result};
            return true;
        }
    }
    return false;
}

static bool hunk_applies(const PatchHunk *hunk, Span lines, bool reverse, int max_fuzz)
{
    HunkMatch match;
    if (!search_hunk(hunk, lines, 0, reverse, max_fuzz, &match)) {
        return false;
    }
    lines_free(&match.lines);
    return true;
}

static void print_hunk_report(const HunkMatch *match, int number)
{
    printf("Hunk #%d succeeded at %d", number, match->position + 1);
    if (match->fuzz >= 1) {
        printf(" with fuzz %d", match->fuzz);
    }
    if (match->delta == 1 || match->delta == -1) {
        printf(" (offset %d line)", match->delta);
    } else if (match->delta != 0) {
        printf(" (offset %d lines)", match->delta);
    }
    putchar('\n');
}

static bool parse_edit_command(const char *line, char *instruction, int *first, int *last)
{
    size_t length = strlen(line);
    bool has_last;
    *instruction = line[length - 1];
    if (strchr("acd", *instruction) == NULL ||
        !parse_number_pair(line, length - 1, first, last, &has_last)) {
        return false;
    }
    if (*instruction == 'a' && has_last) {
        return false;
    }
    if (!has_last) {
        *last = *first;
    }
    return true;
}

static const char *run_edit_script(Span original, Span script, Lines *result, int *executed,
                                   int *error_line)
{
    Lines lines = lines_from(original);
    const char *error = NULL;
    int index = 0;
    *executed = 0;
    while (index < script.count) {
        *error_line = index + 1;
        char instruction;
        int first, last;
        if (!parse_edit_command(script.items[index], &instruction, &first, &last)) {
            error = "bad command";
            break;
        }
        bool valid = instruction == 'a' ? first <= lines.count
                                        : 1 <= first && first <= last && last <= lines.count;
        if (!valid) {
            error = "bad range";
            break;
        }
        index++;
        Span text = {script.items + index, 0};
        if (instruction != 'd') {
            int end = index;
            while (end < script.count && strcmp(script.items[end], ".") != 0) {
                end++;
            }
            if (end == script.count) {
                error = "missing terminator";
                break;
            }
            text = slice(script, index, end);
            index = end + 1;
        }
        Lines next = instruction == 'a'
                         ? lines_replaced(span_of(&lines), first, 0, text)
                         : lines_replaced(span_of(&lines), first - 1, last - first + 1, text);
        lines_free(&lines);
        lines = next;
        (*executed)++;
    }
    if (error != NULL) {
        lines_free(&lines);
        return error;
    }
    *result = lines;
    return NULL;
}

static ChunkKind chunk_kind(Span base, Span ours, Span theirs)
{
    if (spans_equal(ours, base)) {
        return KIND_B;
    }
    if (spans_equal(theirs, base)) {
        return KIND_A;
    }
    return spans_equal(ours, theirs) ? KIND_BOTH : KIND_CONFLICT;
}

static int *match_table(Span first, Span second)
{
    int *matches = calloc((size_t)first.count + 2, sizeof *matches);
    int pair_count;
    Pair *pairs = matched_pairs(first, second, &pair_count);
    for (int k = 1; k + 1 < pair_count; k++) {
        matches[pairs[k].first] = pairs[k].second;
    }
    free(pairs);
    return matches;
}

static Chunk *three_way_chunks(Span base, Span ours, Span theirs, int *chunk_count)
{
    int *ours_match = match_table(base, ours);
    int *theirs_match = match_table(base, theirs);
    Chunk *chunks = malloc((size_t)(base.count + ours.count + theirs.count + 1) * sizeof *chunks);
    int count = 0, x = 0, y = 0, z = 0;
    while (x < base.count || y < ours.count || z < theirs.count) {
        if (x < base.count && ours_match[x + 1] == y + 1 && theirs_match[x + 1] == z + 1) {
            chunks[count++] = (Chunk){KIND_STABLE, x, y, z, slice(base, x, x + 1),
                                      slice(ours, y, y + 1), slice(theirs, z, z + 1)};
            x++;
            y++;
            z++;
            continue;
        }
        int anchor = x + 1;
        while (anchor <= base.count && (ours_match[anchor] == 0 || theirs_match[anchor] == 0)) {
            anchor++;
        }
        int next_x = base.count, next_y = ours.count, next_z = theirs.count;
        if (anchor <= base.count) {
            next_x = anchor - 1;
            next_y = ours_match[anchor] - 1;
            next_z = theirs_match[anchor] - 1;
        }
        Span base_part = slice(base, x, next_x);
        Span ours_part = slice(ours, y, next_y);
        Span theirs_part = slice(theirs, z, next_z);
        ChunkKind kind = chunk_kind(base_part, ours_part, theirs_part);
        chunks[count++] = (Chunk){kind, x, y, z, base_part, ours_part, theirs_part};
        x = next_x;
        y = next_y;
        z = next_z;
    }
    free(ours_match);
    free(theirs_match);
    *chunk_count = count;
    return chunks;
}

static void format_kind_counts(char *buffer, size_t size, const Chunk *chunks, int count)
{
    int tally[KIND_COUNT] = {0};
    for (int i = 0; i < count; i++) {
        tally[chunks[i].kind]++;
    }
    snprintf(buffer, size, "a=%d b=%d both=%d conflicts=%d", tally[KIND_A], tally[KIND_B],
             tally[KIND_BOTH], tally[KIND_CONFLICT]);
}

static void format_location(char *buffer, size_t size, const Chunk *chunk)
{
    snprintf(buffer, size, "base %d,%d a %d,%d b %d,%d", chunk->base_start + 1, chunk->base.count,
             chunk->ours_start + 1, chunk->ours.count, chunk->theirs_start + 1,
             chunk->theirs.count);
}

static int common_prefix_length(Span first, Span second)
{
    int length = 0;
    while (length < first.count && length < second.count &&
           strcmp(first.items[length], second.items[length]) == 0) {
        length++;
    }
    return length;
}

static int common_suffix_length(Span first, Span second, int limit)
{
    int length = 0;
    while (length < limit && strcmp(first.items[first.count - 1 - length],
                                    second.items[second.count - 1 - length]) == 0) {
        length++;
    }
    return length;
}

static void append_conflict(Lines *result, const Chunk *chunk, const char *mode,
                            const char *base_name, const char *ours_name, const char *theirs_name)
{
    Span ours = chunk->ours, theirs = chunk->theirs;
    if (strcmp(mode, "OURS") == 0) {
        lines_append(result, ours);
        return;
    }
    if (strcmp(mode, "THEIRS") == 0) {
        lines_append(result, theirs);
        return;
    }
    if (strcmp(mode, "DIFF3") == 0) {
        lines_push(result, format_string("<<<<<<< %s", ours_name));
        lines_append(result, ours);
        lines_push(result, format_string("||||||| %s", base_name));
        lines_append(result, chunk->base);
        lines_push(result, SEPARATOR);
        lines_append(result, theirs);
        lines_push(result, format_string(">>>>>>> %s", theirs_name));
        return;
    }
    int head = common_prefix_length(ours, theirs);
    int tail = common_suffix_length(ours, theirs, min_int(ours.count, theirs.count) - head);
    Span ours_middle = slice(ours, head, ours.count - tail);
    Span theirs_middle = slice(theirs, head, theirs.count - tail);
    lines_append(result, slice(ours, 0, head));
    if (strcmp(mode, "UNION") == 0) {
        lines_append(result, ours_middle);
        lines_append(result, theirs_middle);
    } else {
        lines_push(result, format_string("<<<<<<< %s", ours_name));
        lines_append(result, ours_middle);
        lines_push(result, SEPARATOR);
        lines_append(result, theirs_middle);
        lines_push(result, format_string(">>>>>>> %s", theirs_name));
    }
    lines_append(result, slice(ours, ours.count - tail, ours.count));
}

static Marker marker_kind(const char *line)
{
    if (strcmp(line, SEPARATOR) == 0) {
        return SEPARATOR_MARKER;
    }
    if (strlen(line) < 7 || (line[7] != '\0' && line[7] != ' ')) {
        return NOT_MARKER;
    }
    if (strncmp(line, "<<<<<<<", 7) == 0) {
        return START_MARKER;
    }
    if (strncmp(line, "|||||||", 7) == 0) {
        return BASE_MARKER;
    }
    if (strncmp(line, ">>>>>>>", 7) == 0) {
        return END_MARKER;
    }
    return NOT_MARKER;
}

static Marker marker_at(Span lines, int index)
{
    return index < lines.count ? marker_kind(lines.items[index]) : NOT_MARKER;
}

static int next_marker(Span lines, int index)
{
    index++;
    while (index < lines.count && marker_kind(lines.items[index]) == NOT_MARKER) {
        index++;
    }
    return index;
}

static bool region_at(Span lines, int start, ConflictRegion *region)
{
    if (marker_at(lines, start) != START_MARKER) {
        return false;
    }
    int middle = next_marker(lines, start);
    int base_marker = -1;
    if (marker_at(lines, middle) == BASE_MARKER) {
        base_marker = middle;
        middle = next_marker(lines, middle);
    }
    if (marker_at(lines, middle) != SEPARATOR_MARKER) {
        return false;
    }
    int end = next_marker(lines, middle);
    if (marker_at(lines, end) != END_MARKER) {
        return false;
    }
    bool has_base = base_marker >= 0;
    *region = (ConflictRegion){
        .start = start + 1,
        .end = end + 1,
        .ours = slice(lines, start + 1, has_base ? base_marker : middle),
        .base = has_base ? slice(lines, base_marker + 1, middle) : (Span){NULL, 0},
        .theirs = slice(lines, middle + 1, end),
        .has_base = has_base,
    };
    return true;
}

static ConflictRegion *conflict_regions(Span lines, int *region_count)
{
    ConflictRegion *regions = malloc((size_t)(lines.count / 3 + 1) * sizeof *regions);
    int count = 0, index = 0;
    while (index < lines.count) {
        if (region_at(lines, index, &regions[count])) {
            index = regions[count].end;
            count++;
        } else {
            index++;
        }
    }
    *region_count = count;
    return regions;
}

static Lines region_part(const ConflictRegion *region, const char *side)
{
    Lines part = {0};
    if (strcmp(side, "OURS") == 0) {
        lines_append(&part, region->ours);
    } else if (strcmp(side, "THEIRS") == 0) {
        lines_append(&part, region->theirs);
    } else if (strcmp(side, "BASE") == 0) {
        lines_append(&part, region->base);
    } else {
        lines_append(&part, region->ours);
        lines_append(&part, region->theirs);
    }
    return part;
}

static File *find_file(const char *name)
{
    for (int i = 0; i < file_count; i++) {
        if (strcmp(files[i].name, name) == 0) {
            return &files[i];
        }
    }
    return NULL;
}

static File *require(const char *name)
{
    File *file = find_file(name);
    if (file == NULL || !file->exists) {
        printf("ERROR no such file %s\n", name);
        return NULL;
    }
    return file;
}

static void save(const char *name, Lines content)
{
    File *file = find_file(name);
    if (file == NULL) {
        file = &files[file_count++];
        snprintf(file->name, sizeof file->name, "%s", name);
    }
    if (file->history_count == file->history_capacity) {
        file->history_capacity = file->history_capacity > 0 ? file->history_capacity * 2 : 4;
        file->history =
            realloc(file->history, (size_t)file->history_capacity * sizeof *file->history);
    }
    file->history[file->history_count++] = (State){file->exists, file->content};
    file->exists = true;
    file->content = content;
}

static unsigned parse_compare_options(char **words, int count)
{
    unsigned options = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(words[i], "ICASE") == 0) {
            options |= ICASE;
        } else if (strcmp(words[i], "IWHITE") == 0) {
            options |= IWHITE;
        } else if (strcmp(words[i], "ISPACE") == 0) {
            options |= ISPACE;
        }
    }
    return options;
}

static bool format_has_argument(const char *form)
{
    return strcmp(form, "IFDEF") == 0 || strcmp(form, "UNIFIED") == 0 ||
           strcmp(form, "CONTEXT") == 0 || strcmp(form, "SIDE") == 0;
}

static void command_file(char **arguments, int argument_count, Span data)
{
    save(arguments[0], lines_from(data));
    printf("FILE %s lines=%d\n", arguments[0], data.count);
}

static void command_copy(char **arguments, int argument_count, Span data)
{
    const char *source = arguments[0], *target = arguments[1];
    File *file = require(source);
    if (file == NULL) {
        return;
    }
    Lines content = lines_from(span_of(&file->content));
    save(target, content);
    printf("COPY %s %s lines=%d\n", source, target, content.count);
}

static void command_print(char **arguments, int argument_count, Span data)
{
    File *file = require(arguments[0]);
    if (file == NULL) {
        return;
    }
    printf("PRINT %s lines=%d\n", arguments[0], file->content.count);
    for (int i = 0; i < file->content.count; i++) {
        printf("%3d| %s\n", i + 1, file->content.items[i]);
    }
}

static int compare_file_names(const void *first, const void *second)
{
    const File *const *a = first;
    const File *const *b = second;
    return strcmp((*a)->name, (*b)->name);
}

static void command_files(char **arguments, int argument_count, Span data)
{
    const File *existing[MAX_FILES];
    int count = 0;
    for (int i = 0; i < file_count; i++) {
        if (files[i].exists) {
            existing[count++] = &files[i];
        }
    }
    qsort(existing, (size_t)count, sizeof *existing, compare_file_names);
    printf("FILES count=%d\n", count);
    for (int i = 0; i < count; i++) {
        printf("%s lines=%d undo=%d\n", existing[i]->name, existing[i]->content.count,
               existing[i]->history_count);
    }
}

static void command_undo(char **arguments, int argument_count, Span data)
{
    const char *name = arguments[0];
    File *file = find_file(name);
    if (file == NULL || file->history_count == 0) {
        printf("ERROR nothing to undo %s\n", name);
        return;
    }
    State state = file->history[--file->history_count];
    lines_free(&file->content);
    file->exists = state.exists;
    file->content = state.content;
    if (state.exists) {
        printf("UNDO %s lines=%d\n", name, state.content.count);
    } else {
        printf("UNDO %s removed\n", name);
    }
}

static void command_diff(char **arguments, int argument_count, Span data)
{
    const char *old_name = arguments[0], *new_name = arguments[1], *form = arguments[2];
    File *old_file, *new_file;
    if ((old_file = require(old_name)) == NULL || (new_file = require(new_name)) == NULL) {
        return;
    }
    bool has_parameter = format_has_argument(form);
    const char *parameter = has_parameter ? arguments[3] : NULL;
    int option_start = has_parameter ? 4 : 3;
    unsigned options = parse_compare_options(arguments + option_start, argument_count - option_start);
    LineDiff diff = line_diff(span_of(&old_file->content), span_of(&new_file->content), options);
    if (diff.blocks.count == 0) {
        printf("Files %s and %s are identical\n", old_name, new_name);
    } else if (strcmp(form, "BRIEF") == 0) {
        printf("Files %s and %s differ\n", old_name, new_name);
    } else if (strcmp(form, "NORMAL") == 0) {
        print_normal(&diff);
    } else if (strcmp(form, "ED") == 0) {
        print_ed(&diff);
    } else if (strcmp(form, "RCS") == 0) {
        print_rcs(&diff);
    } else if (strcmp(form, "IFDEF") == 0) {
        print_ifdef(&diff, parameter);
    } else if (strcmp(form, "UNIFIED") == 0) {
        print_unified(&diff, atoi(parameter), old_name, new_name);
    } else if (strcmp(form, "CONTEXT") == 0) {
        print_context(&diff, atoi(parameter), old_name, new_name);
    } else {
        print_side_by_side(&diff, atoi(parameter));
    }
    free(diff.blocks.items);
}

static void token_diff(char **arguments, bool by_word)
{
    const char *old_name = arguments[0], *new_name = arguments[1];
    File *old_file, *new_file;
    if ((old_file = require(old_name)) == NULL || (new_file = require(new_name)) == NULL) {
        return;
    }
    Span old = span_of(&old_file->content), new = span_of(&new_file->content);
    LineDiff diff = line_diff(old, new, 0);
    if (diff.blocks.count == 0) {
        printf("Files %s and %s are identical\n", old_name, new_name);
        free(diff.blocks.items);
        return;
    }
    const char *separator = by_word ? " " : "";
    TokenTotals totals = {0};
    for (int k = 0; k < diff.blocks.count; k++) {
        const ChangeBlock *block = &diff.blocks.items[k];
        for (int row = 0; row < max_int(block->x, block->y); row++) {
            int old_number = block->p + row + 1, new_number = block->q + row + 1;
            if (row < block->x && row < block->y) {
                Lines old_tokens = split_tokens(old.items[old_number - 1], by_word);
                Lines new_tokens = split_tokens(new.items[new_number - 1], by_word);
                printf("a%d b%d: ", old_number, new_number);
                print_token_comparison(span_of(&old_tokens), span_of(&new_tokens), separator,
                                       &totals);
                free_strings(old_tokens.items, old_tokens.count);
                free_strings(new_tokens.items, new_tokens.count);
            } else if (row < block->x) {
                Lines old_tokens = split_tokens(old.items[old_number - 1], by_word);
                totals.deleted += old_tokens.count;
                printf("a%d: ", old_number);
                print_deletion(span_of(&old_tokens), separator);
                free_strings(old_tokens.items, old_tokens.count);
            } else {
                Lines new_tokens = split_tokens(new.items[new_number - 1], by_word);
                totals.inserted += new_tokens.count;
                printf("b%d: ", new_number);
                print_insertion(span_of(&new_tokens), separator);
                free_strings(new_tokens.items, new_tokens.count);
            }
            putchar('\n');
        }
    }
    printf("%s deleted=%d inserted=%d common=%d\n", by_word ? "WORDS" : "CHARS", totals.deleted,
           totals.inserted, totals.common);
    free(diff.blocks.items);
}

static void command_worddiff(char **arguments, int argument_count, Span data)
{
    token_diff(arguments, true);
}

static void command_chardiff(char **arguments, int argument_count, Span data)
{
    token_diff(arguments, false);
}

static void print_stat_graph(int inserted, int deleted)
{
    int total = inserted + deleted, plus = inserted, minus = deleted;
    if (total > GRAPH_WIDTH) {
        plus = GRAPH_WIDTH * inserted / total;
        minus = GRAPH_WIDTH * deleted / total;
        if (inserted >= 1 && plus == 0) {
            plus = 1;
        }
        if (deleted >= 1 && minus == 0) {
            minus = 1;
        }
    }
    for (int i = 0; i < plus; i++) {
        putchar('+');
    }
    for (int i = 0; i < minus; i++) {
        putchar('-');
    }
}

static void command_stat(char **arguments, int argument_count, Span data)
{
    const char *old_name = arguments[0], *new_name = arguments[1];
    File *old_file, *new_file;
    if ((old_file = require(old_name)) == NULL || (new_file = require(new_name)) == NULL) {
        return;
    }
    Span old = span_of(&old_file->content), new = span_of(&new_file->content);
    LineDiff diff = line_diff(old, new, parse_compare_options(arguments + 2, argument_count - 2));
    int deleted = 0, inserted = 0;
    for (int k = 0; k < diff.blocks.count; k++) {
        deleted += diff.blocks.items[k].x;
        inserted += diff.blocks.items[k].y;
    }
    int total = deleted + inserted;
    int unchanged = old.count - deleted;
    printf("%s -> %s | %d", old_name, new_name, total);
    if (total > 0) {
        putchar(' ');
        print_stat_graph(inserted, deleted);
    }
    putchar('\n');
    int line_total = old.count + new.count;
    int similarity = line_total > 0 ? 200 * unchanged / line_total : 100;
    printf("changes=%d insertions=%d deletions=%d unchanged=%d similarity=%d%%\n",
           diff.blocks.count, inserted, deleted, unchanged, similarity);
    free(diff.blocks.items);
}

static void command_patch(char **arguments, int argument_count, Span data)
{
    const char *name = arguments[0];
    File *file = require(name);
    if (file == NULL) {
        return;
    }
    bool reverse = false, dry_run = false;
    int max_fuzz = 0;
    for (int i = 2; i < argument_count; i++) {
        if (strcmp(arguments[i], "REVERSE") == 0) {
            reverse = true;
        } else if (strcmp(arguments[i], "DRYRUN") == 0) {
            dry_run = true;
        } else if (strcmp(arguments[i], "FUZZ") == 0) {
            max_fuzz = atoi(arguments[++i]);
        }
    }
    PatchHunk hunks[MAX_DATA_LINES];
    int hunk_count, error_line;
    const char *error = parse_patch(data, hunks, &hunk_count, &error_line);
    if (error != NULL) {
        if (error_line == 0) {
            printf("PATCH ERROR %s\n", error);
        } else {
            printf("PATCH ERROR line %d: %s\n", error_line, error);
        }
        return;
    }
    printf("%s file %s\n", dry_run ? "checking" : "patching", name);
    Span original = span_of(&file->content);
    if (!hunk_applies(&hunks[0], original, reverse, max_fuzz) &&
        hunk_applies(&hunks[0], original, !reverse, max_fuzz)) {
        puts("Reversed (or previously applied) patch detected! Skipping patch.");
        printf("RESULT applied=0 failed=0 ignored=%d lines=%d\n", hunk_count, original.count);
        return;
    }
    Lines lines = lines_from(original);
    int adjustment = 0, applied = 0, failed = 0;
    for (int i = 0; i < hunk_count; i++) {
        const PatchHunk *hunk = &hunks[i];
        HunkMatch match;
        if (!search_hunk(hunk, span_of(&lines), adjustment, reverse, max_fuzz, &match)) {
            failed++;
            printf("Hunk #%d FAILED at %d\n", i + 1, hunk_start(hunk, reverse));
            continue;
        }
        char *old[MAX_DATA_LINES], *new[MAX_DATA_LINES];
        lines_free(&lines);
        lines = match.lines;
        adjustment +=
            match.delta + new_sequence(hunk, reverse, new) - old_sequence(hunk, reverse, old);
        applied++;
        print_hunk_report(&match, i + 1);
    }
    printf("RESULT applied=%d failed=%d ignored=0 lines=%d\n", applied, failed, lines.count);
    if (!dry_run && applied >= 1) {
        save(name, lines);
    } else {
        lines_free(&lines);
    }
}

static void command_edit(char **arguments, int argument_count, Span data)
{
    const char *name = arguments[0];
    File *file = require(name);
    if (file == NULL) {
        return;
    }
    Lines lines;
    int executed, error_line;
    const char *error = run_edit_script(span_of(&file->content), data, &lines, &executed,
                                        &error_line);
    if (error != NULL) {
        printf("EDIT ERROR line %d: %s\n", error_line, error);
        return;
    }
    printf("EDIT %s commands=%d lines=%d\n", name, executed, lines.count);
    save(name, lines);
}

static Chunk *three_way(char **arguments, int *chunk_count)
{
    File *base, *ours, *theirs;
    if ((base = require(arguments[0])) == NULL || (ours = require(arguments[1])) == NULL ||
        (theirs = require(arguments[2])) == NULL) {
        return NULL;
    }
    return three_way_chunks(span_of(&base->content), span_of(&ours->content),
                            span_of(&theirs->content), chunk_count);
}

static void command_diff3(char **arguments, int argument_count, Span data)
{
    int chunk_count;
    Chunk *chunks = three_way(arguments, &chunk_count);
    if (chunks == NULL) {
        return;
    }
    int changes = 0;
    for (int i = 0; i < chunk_count; i++) {
        const Chunk *chunk = &chunks[i];
        if (chunk->kind == KIND_STABLE) {
            continue;
        }
        char location[LINE_CAPACITY];
        format_location(location, sizeof location, chunk);
        printf("==== %s %s\n", KIND_NAMES[chunk->kind], location);
        print_lines("O ", chunk->base);
        if (chunk->kind != KIND_B) {
            print_lines("A ", chunk->ours);
        }
        if (chunk->kind == KIND_B || chunk->kind == KIND_CONFLICT) {
            print_lines("B ", chunk->theirs);
        }
        changes++;
    }
    char counts[LINE_CAPACITY];
    format_kind_counts(counts, sizeof counts, chunks, chunk_count);
    printf("DIFF3 chunks=%d %s\n", changes, counts);
    free(chunks);
}

static void command_merge(char **arguments, int argument_count, Span data)
{
    const char *base_name = arguments[0], *ours_name = arguments[1], *theirs_name = arguments[2];
    const char *target = arguments[3];
    const char *mode = argument_count == 5 ? arguments[4] : "MARKERS";
    int chunk_count;
    Chunk *chunks = three_way(arguments, &chunk_count);
    if (chunks == NULL) {
        return;
    }
    Lines result = {0};
    for (int i = 0; i < chunk_count; i++) {
        const Chunk *chunk = &chunks[i];
        if (chunk->kind == KIND_B) {
            lines_append(&result, chunk->theirs);
        } else if (chunk->kind == KIND_CONFLICT) {
            append_conflict(&result, chunk, mode, base_name, ours_name, theirs_name);
        } else {
            lines_append(&result, chunk->ours);
        }
    }
    char counts[LINE_CAPACITY];
    format_kind_counts(counts, sizeof counts, chunks, chunk_count);
    printf("MERGE %s lines=%d %s\n", target, result.count, counts);
    int conflict_number = 0;
    for (int i = 0; i < chunk_count; i++) {
        if (chunks[i].kind == KIND_CONFLICT) {
            char location[LINE_CAPACITY];
            format_location(location, sizeof location, &chunks[i]);
            printf("CONFLICT %d %s\n", ++conflict_number, location);
        }
    }
    free(chunks);
    save(target, result);
}

static void command_conflicts(char **arguments, int argument_count, Span data)
{
    const char *name = arguments[0];
    File *file = require(name);
    if (file == NULL) {
        return;
    }
    int region_count;
    ConflictRegion *regions = conflict_regions(span_of(&file->content), &region_count);
    printf("CONFLICTS %s count=%d\n", name, region_count);
    for (int i = 0; i < region_count; i++) {
        const ConflictRegion *region = &regions[i];
        char base[RANGE_CAPACITY] = "none";
        if (region->has_base) {
            snprintf(base, sizeof base, "%d", region->base.count);
        }
        printf("%d: lines %d-%d ours=%d base=%s theirs=%d\n", i + 1, region->start, region->end,
               region->ours.count, base, region->theirs.count);
    }
    free(regions);
}

static void command_resolve(char **arguments, int argument_count, Span data)
{
    const char *name = arguments[0], *side = arguments[2];
    File *file = require(name);
    if (file == NULL) {
        return;
    }
    int number = atoi(arguments[1]);
    Span lines = span_of(&file->content);
    int region_count;
    ConflictRegion *regions = conflict_regions(lines, &region_count);
    if (region_count < number) {
        printf("ERROR no conflict %d in %s\n", number, name);
        free(regions);
        return;
    }
    const ConflictRegion *region = &regions[number - 1];
    if (strcmp(side, "BASE") == 0 && !region->has_base) {
        printf("ERROR no base section in conflict %d\n", number);
        free(regions);
        return;
    }
    Lines part = region_part(region, side);
    Lines content =
        lines_replaced(lines, region->start - 1, region->end - region->start + 1, span_of(&part));
    lines_free(&part);
    free(regions);
    int remaining;
    free(conflict_regions(span_of(&content), &remaining));
    printf("RESOLVE %s %d %s lines=%d remaining=%d\n", name, number, side, content.count,
           remaining);
    save(name, content);
}

static const Command COMMANDS[] = {
    {"FILE", true, command_file},
    {"COPY", false, command_copy},
    {"PRINT", false, command_print},
    {"FILES", false, command_files},
    {"DIFF", false, command_diff},
    {"WORDDIFF", false, command_worddiff},
    {"CHARDIFF", false, command_chardiff},
    {"STAT", false, command_stat},
    {"PATCH", true, command_patch},
    {"EDIT", true, command_edit},
    {"DIFF3", false, command_diff3},
    {"MERGE", false, command_merge},
    {"CONFLICTS", false, command_conflicts},
    {"RESOLVE", false, command_resolve},
    {"UNDO", false, command_undo},
};

static const Command *find_command(const char *name)
{
    for (size_t i = 0; i < sizeof COMMANDS / sizeof COMMANDS[0]; i++) {
        if (strcmp(COMMANDS[i].name, name) == 0) {
            return &COMMANDS[i];
        }
    }
    return NULL;
}

static Lines read_input(void)
{
    Lines input = {0};
    char buffer[LINE_CAPACITY];
    while (fgets(buffer, sizeof buffer, stdin) != NULL) {
        buffer[strcspn(buffer, "\r\n")] = '\0';
        lines_push(&input, copy_range(buffer, strlen(buffer)));
    }
    return input;
}

int main(void)
{
    Lines input = read_input();
    int command_count = atoi(input.items[0]);
    int position = 1;
    for (int n = 0; n < command_count; n++) {
        char *words[MAX_WORDS];
        int word_count = split_words(input.items[position++], words, MAX_WORDS);
        const Command *command = find_command(words[0]);
        Span data = {NULL, 0};
        if (command->has_data) {
            data = slice(span_of(&input), position, position + atoi(words[2]));
            position += data.count;
        }
        command->handler(words + 1, word_count - 1, data);
    }
    return 0;
}
