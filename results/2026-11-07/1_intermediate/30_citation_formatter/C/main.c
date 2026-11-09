#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef struct Allocation { struct Allocation *next; max_align_t data[]; } Allocation;
typedef struct { Allocation *head; } Arena;
static Arena database_arena, command_arena;
static Arena *arena = &database_arena;
static void *allocate(size_t bytes) {
    Allocation *block = calloc(1, offsetof(Allocation, data) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = arena->head; arena->head = block;
    return block->data;
}
static void clear_arena(Arena *value) {
    while (value->head) { Allocation *next = value->head->next; free(value->head); value->head = next; }
}
static void *grow(void *data, size_t *capacity, size_t size) {
    size_t next = *capacity ? 2 * *capacity : 8;
    void *result = allocate(next * size);
    if (*capacity) memcpy(result, data, *capacity * size);
    *capacity = next;
    return result;
}
#define PUSH(vector, value) do { \
    if ((vector)->count == (vector)->capacity) \
        (vector)->data = grow((vector)->data, &(vector)->capacity, sizeof *(vector)->data); \
    (vector)->data[(vector)->count++] = (value); \
} while (0)

typedef struct { char *data; size_t count, capacity; } Text;
typedef struct { char **data; size_t count, capacity; } Strings;
static void append_n(Text *text, const char *value, size_t length) {
    while (text->count + length + 1 > text->capacity) text->data = grow(text->data, &text->capacity, 1);
    memcpy(text->data + text->count, value, length);
    text->count += length; text->data[text->count] = '\0';
}
static void append(Text *text, const char *value) { append_n(text, value, strlen(value)); }
static void append_char(Text *text, char value) { append_n(text, &value, 1); }
static char *finish(Text *text) { if (!text->data) append(text, ""); return text->data; }
static char *slice(const char *text, size_t begin, size_t end) {
    char *result = allocate(end - begin + 1);
    memcpy(result, text + begin, end - begin);
    return result;
}
static char *copy_string(const char *text) { return slice(text, 0, strlen(text)); }
static char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern); va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}
static bool lower(char c) { return c >= 'a' && c <= 'z'; }
static bool upper(char c) { return c >= 'A' && c <= 'Z'; }
static bool letter(char c) { return lower(c) || upper(c); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static char lowercase(char c) { return upper(c) ? (char)(c + 'a' - 'A') : c; }
static char uppercase(char c) { return lower(c) ? (char)(c + 'A' - 'a') : c; }
static char *lower_string(const char *text) {
    char *result = copy_string(text);
    for (size_t i = 0; result[i]; ++i) result[i] = lowercase(result[i]);
    return result;
}
static char *plain(const char *text) {
    Text result = {0};
    for (; *text; ++text) if (*text != '{' && *text != '}') append_char(&result, *text);
    return finish(&result);
}
static char *trim(const char *text) {
    size_t first = 0, last = strlen(text);
    while (first < last && text[first] == ' ') ++first;
    while (last > first && text[last - 1] == ' ') --last;
    return slice(text, first, last);
}
static Strings split(const char *text, const char *delimiter, bool at_depth_zero, bool skip_empty) {
    Strings result = {0};
    size_t start = 0, i = 0, length = strlen(text), width = strlen(delimiter);
    int depth = 0;
    while (i < length) {
        if ((!at_depth_zero || depth == 0) && strncmp(text + i, delimiter, width) == 0) {
            if (i > start || !skip_empty) PUSH(&result, slice(text, start, i));
            i += width; start = i; continue;
        }
        if (text[i] == '{') ++depth;
        if (text[i] == '}') --depth;
        ++i;
    }
    if (i > start || !skip_empty) PUSH(&result, slice(text, start, i));
    return result;
}
static char *join_range(Strings values, size_t start, size_t end, const char *separator) {
    Text result = {0};
    for (size_t i = start; i < end; ++i) { if (i > start) append(&result, separator); append(&result, values.data[i]); }
    return finish(&result);
}
static char *join(Strings values, const char *separator) { return join_range(values, 0, values.count, separator); }
static bool all_digits(const char *value) {
    if (!*value) return false;
    for (; *value; ++value) if (!digit(*value)) return false;
    return true;
}
static char *letters_only(const char *value) {
    Text text = {0};
    for (; *value; ++value) if (letter(*value)) append_char(&text, lowercase(*value));
    return finish(&text);
}
static int string_compare(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }
static bool contains_string(Strings values, const char *text) {
    for (size_t i = 0; i < values.count; ++i) if (!strcmp(values.data[i], text)) return true;
    return false;
}
static void add_unique(Strings *values, char *text) { if (!contains_string(*values, text)) PUSH(values, text); }

static const char *const known_fields[] = {
    "author", "editor", "title", "journal", "booktitle", "edition", "volume", "number", "pages",
    "publisher", "institution", "school", "address", "howpublished", "month", "year", "doi", "note"
};
static const char *const type_names[] = {"article", "book", "inproceedings", "incollection", "techreport", "phdthesis", "misc"};
static const char *const required[][5] = {
    {"author", "title", "journal", "year", NULL}, {"author", "title", "publisher", "year", NULL},
    {"author", "title", "booktitle", "year", NULL}, {"author", "title", "booktitle", "publisher", "year"},
    {"author", "title", "institution", "year", NULL}, {"author", "title", "school", "year", NULL},
    {"author", "title", "year", NULL, NULL}
};
static const char *const months[] = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
static const char *const month_macros[] = {"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"};
static const char *const month_short[] = {"Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."};
static const char *const small_words[] = {"a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "nor", "of", "on", "or", "over", "per", "so", "the", "to", "up", "via", "with", "yet"};
static bool small_word(const char *text) {
    for (size_t i = 0; i < sizeof small_words / sizeof *small_words; ++i) if (!strcmp(text, small_words[i])) return true;
    return false;
}
static int known_index(const char *name) {
    for (int i = 0; i < 18; ++i) if (!strcmp(name, known_fields[i])) return i;
    return -1;
}
typedef struct { char *name, *value; } Field;
typedef struct { Field *data; size_t count, capacity; } Fields;
static char *field(Fields fields, const char *name) {
    for (size_t i = 0; i < fields.count; ++i) if (!strcmp(fields.data[i].name, name)) return fields.data[i].value;
    return NULL;
}
typedef struct { char *first, *von, *last, *jr; } Name;
typedef struct { Name *data; size_t count, capacity; bool et_al; } NameList;
static Name parse_name(const char *text) {
    Strings parts = split(text, ",", true, false);
    for (size_t i = 0; i < parts.count; ++i) parts.data[i] = trim(parts.data[i]);
    Strings words = split(parts.data[0], " ", true, true);
    size_t first_lower = words.count, last_lower = words.count;
    for (size_t i = 0; i + 1 < words.count; ++i) if (lower(words.data[i][0])) {
        if (first_lower == words.count) first_lower = i;
        last_lower = i;
    }
    Name name = {"", "", "", ""};
    if (parts.count == 1) {
        if (first_lower == words.count) {
            name.first = join_range(words, 0, words.count - 1, " ");
            name.last = words.data[words.count - 1];
        } else {
            name.first = join_range(words, 0, first_lower, " ");
            name.von = join_range(words, first_lower, last_lower + 1, " ");
            name.last = join_range(words, last_lower + 1, words.count, " ");
        }
    } else {
        if (last_lower == words.count) name.last = join(words, " ");
        else { name.von = join_range(words, 0, last_lower + 1, " "); name.last = join_range(words, last_lower + 1, words.count, " "); }
        name.first = parts.data[parts.count - 1];
        if (parts.count == 3) name.jr = parts.data[1];
    }
    return name;
}
static NameList parse_names(const char *text) {
    NameList result = {0};
    Strings people = split(text, " and ", true, false);
    for (size_t i = 0; i < people.count; ++i) {
        if (!strcmp(people.data[i], "others")) result.et_al = true;
        else PUSH(&result, parse_name(people.data[i]));
    }
    return result;
}
static bool same_names(const NameList *a, const NameList *b) {
    if (a->count != b->count || a->et_al != b->et_al) return false;
    for (size_t i = 0; i < a->count; ++i) {
        Name x = a->data[i], y = b->data[i];
        if (strcmp(x.first, y.first) || strcmp(x.von, y.von) || strcmp(x.last, y.last) || strcmp(x.jr, y.jr)) return false;
    }
    return true;
}
static char *surname(Name name) { return plain(*name.von ? format("%s %s", name.von, name.last) : name.last); }
static char *initials(Name name) {
    Strings words = split(plain(name.first), " ", false, true), result = {0};
    for (size_t i = 0; i < words.count; ++i) {
        Strings pieces = split(words.data[i], "-", false, false), parts = {0};
        for (size_t j = 0; j < pieces.count; ++j) {
            const char *piece = pieces.data[j];
            while (!letter(*piece)) ++piece;
            PUSH(&parts, format("%c.", uppercase(*piece)));
        }
        PUSH(&result, join(parts, "-"));
    }
    return join(result, " ");
}
static char *name_text(Name name, bool inverted, bool abbreviated) {
    char *family = surname(name), *given = abbreviated ? initials(name) : plain(name.first);
    Text result = {0};
    if (!inverted && *name.first) { append(&result, given); append_char(&result, ' '); }
    append(&result, family);
    if (inverted && *name.first) { append(&result, ", "); append(&result, given); }
    if (*name.jr) { append(&result, ", "); append(&result, plain(name.jr)); }
    return finish(&result);
}

typedef enum { APA, IEEE, CHICAGO, MLA } Style;
typedef struct {
    char *key;
    int type;
    Fields fields;
    bool has_author, has_editor;
    NameList authors, editors;
    char suffix;
    char *sort_last, *year, *sort_title, *plain_title, *lower_title, *base_key;
} Entry;
static Entry entries[400];
static int entry_count, citation_record[400], citation_count;
static Fields macros;
static int database_errors, defined_macros;
static NameList *primary(Entry *entry) { return entry->has_author ? &entry->authors : &entry->editors; }
static int find_entry(const char *key) {
    for (int i = 0; i < entry_count; ++i) if (!strcmp(entries[i].key, key)) return i;
    return -1;
}
static int bibliography_compare(const void *left, const void *right) {
    Entry *a = &entries[*(const int *)left], *b = &entries[*(const int *)right];
    int comparison = strcmp(a->sort_last, b->sort_last);
    if (!comparison) comparison = strcmp(a->year, b->year);
    if (!comparison) comparison = strcmp(a->sort_title, b->sort_title);
    return comparison ? comparison : strcmp(a->key, b->key);
}
static int title_compare(const void *left, const void *right) {
    Entry *a = &entries[*(const int *)left], *b = &entries[*(const int *)right];
    int comparison = strcmp(a->sort_title, b->sort_title);
    return comparison ? comparison : strcmp(a->key, b->key);
}
static int key_compare(const void *left, const void *right) { return strcmp(entries[*(const int *)left].key, entries[*(const int *)right].key); }
static char *title_case(const char *title, Style style) {
    char *result = copy_string(title);
    if (style == IEEE) return result;
    if (style == APA) {
        int depth = 0;
        for (size_t i = 0; result[i]; ++i) {
            if (result[i] == '{') ++depth;
            else if (result[i] == '}') --depth;
            else if (!depth && letter(result[i])) result[i] = i == 0 || (i >= 2 && title[i - 2] == ':' && title[i - 1] == ' ') ? uppercase(result[i]) : lowercase(result[i]);
        }
        return result;
    }
    Strings words = split(title, " ", true, true);
    for (size_t i = 0; i < words.count; ++i) {
        char *word = words.data[i];
        if (word[0] == '{') continue;
        bool make_lower = i > 0 && i + 1 < words.count && words.data[i - 1][strlen(words.data[i - 1]) - 1] != ':' && small_word(letters_only(word));
        int depth = 0;
        bool found_letter = false;
        for (size_t j = 0; word[j]; ++j) {
            if (word[j] == '{') ++depth;
            else if (word[j] == '}') --depth;
            else if (letter(word[j])) {
                if (!depth && make_lower) word[j] = lowercase(word[j]);
                else if (!depth && !found_letter) word[j] = uppercase(word[j]);
                found_letter = true;
            }
        }
    }
    return join(words, " ");
}

static char *evaluate(const char *expression, char **error) {
    int depth = 0;
    for (const char *p = expression; *p; ++p) {
        if (*p == '{') ++depth;
        if (*p == '}') --depth;
        if (depth < 0) { *error = "unbalanced braces"; return NULL; }
    }
    if (depth) { *error = "unbalanced braces"; return NULL; }
    Strings terms = split(expression, " # ", false, false);
    Text result = {0};
    for (size_t i = 0; i < terms.count; ++i) {
        char *term = terms.data[i];
        if (*term == '{' || *term == '"') append_n(&result, term + 1, strlen(term) - 2);
        else if (digit(*term)) append(&result, term);
        else {
            char *value = field(macros, term);
            if (!value) { *error = format("unknown macro '%s'", term); return NULL; }
            append(&result, value);
        }
    }
    return finish(&result);
}
static size_t accent(const char *text, size_t length, size_t at, char *result) {
    if (at >= length || text[at] != '\\' || at + 1 >= length) return 0;
    char command = text[at + 1];
    if (command == '&') { *result = '&'; return 2; }
    bool symbol = strchr("'\"`^~=.", command) != NULL;
    if (symbol && at + 2 < length && letter(text[at + 2])) { *result = text[at + 2]; return 3; }
    if ((symbol || strchr("cuvH", command)) && at + 4 < length && text[at + 2] == '{' && letter(text[at + 3]) && text[at + 4] == '}') {
        *result = text[at + 3]; return 5;
    }
    return 0;
}
static char *normalize(const char *value) {
    Text accents = {0}, result = {0};
    size_t length = strlen(value);
    for (size_t i = 0; i < length;) {
        char replacement;
        size_t width = value[i] == '{' ? accent(value, length, i + 1, &replacement) : 0;
        if (width && i + width + 1 < length && value[i + width + 1] == '}') {
            append_char(&accents, replacement); i += width + 2;
        } else if ((width = accent(value, length, i, &replacement))) {
            append_char(&accents, replacement); i += width;
        } else append_char(&accents, value[i++]);
    }
    bool space = false;
    for (const char *p = finish(&accents); *p; ++p) {
        if (*p == '~' || *p == ' ') space = result.count > 0;
        else {
            if (space) append_char(&result, ' ');
            append_char(&result, *p); space = false;
        }
    }
    return finish(&result);
}
static void database_error(int line, const char *name, const char *reason) {
    printf("ERROR line %d: %s: %s\n", line, name, reason);
    ++database_errors;
}
static bool read_line(char *line, size_t capacity) {
    if (!fgets(line, (int)capacity, stdin)) return false;
    line[strcspn(line, "\r\n")] = '\0';
    return true;
}
static void read_database(void) {
    for (int i = 0; i < 12; ++i) PUSH(&macros, ((Field){copy_string(month_macros[i]), copy_string(months[i])}));
    char line[604];
    int line_number = 0;
    Entry draft = {0};
    bool in_entry = false, invalid = false;
    while (read_line(line, sizeof line) && strcmp(line, "%%")) {
        ++line_number;
        if (in_entry) {
            if (!strcmp(line, "}")) {
                if (!invalid) {
                    for (int i = 0; i < 5 && required[draft.type][i]; ++i) {
                        const char *name = required[draft.type][i];
                        if (field(draft.fields, name) || (draft.type == 1 && !strcmp(name, "author") && field(draft.fields, "editor"))) continue;
                        database_error(line_number, draft.key, format("missing field '%s'", name)); invalid = true; break;
                    }
                    if (!invalid) entries[entry_count++] = draft;
                }
                in_entry = false;
            } else if (!invalid) {
                char *equals = strstr(line, " = "), *name = slice(line, 2, (size_t)(equals - line));
                size_t end = strlen(line);
                if (line[end - 1] == ',') --end;
                char *error = NULL, *value = evaluate(slice(line, (size_t)(equals - line) + 3, end), &error);
                if (!error && field(draft.fields, name)) error = format("duplicate field '%s'", name);
                if (error) { database_error(line_number, draft.key, error); invalid = true; }
                else PUSH(&draft.fields, ((Field){name, normalize(value)}));
            }
        } else if (!*line || *line == '%') continue;
        else if (!strncmp(line, "@string{", 8)) {
            char *equals = strstr(line, " = "), *name = slice(line, 8, (size_t)(equals - line));
            char *error = NULL, *value = evaluate(slice(line, (size_t)(equals - line) + 3, strlen(line) - 1), &error);
            if (!error && field(macros, name)) error = "duplicate macro";
            if (error) database_error(line_number, name, error);
            else { PUSH(&macros, ((Field){name, value})); ++defined_macros; }
        } else {
            char *brace = strchr(line, '{'), *type = slice(line, 1, (size_t)(brace - line));
            draft = (Entry){.key = slice(line, (size_t)(brace - line) + 1, strlen(line) - 1), .type = -1};
            for (int i = 0; i < 7; ++i) if (!strcmp(type, type_names[i])) draft.type = i;
            char *error = draft.type < 0 ? format("unknown type '%s'", type) : find_entry(draft.key) >= 0 ? "duplicate key" : NULL;
            invalid = error != NULL; in_entry = true;
            if (error) database_error(line_number, draft.key, error);
        }
    }
    printf("LOADED entries=%d macros=%d errors=%d\n", entry_count, defined_macros, database_errors);
}
static void prepare_entries(void) {
    for (int i = 0; i < entry_count; ++i) {
        Entry *entry = &entries[i];
        char *author = field(entry->fields, "author"), *editor = field(entry->fields, "editor");
        entry->has_author = author != NULL; entry->has_editor = editor != NULL;
        if (author) entry->authors = parse_names(author);
        if (editor) entry->editors = parse_names(editor);
        Name lead = primary(entry)->data[0];
        entry->sort_last = lower_string(plain(lead.last));
        entry->year = plain(field(entry->fields, "year"));
        entry->plain_title = plain(field(entry->fields, "title"));
        entry->lower_title = lower_string(entry->plain_title);
        entry->sort_title = entry->lower_title;
        if (!strncmp(entry->sort_title, "a ", 2)) entry->sort_title += 2;
        else if (!strncmp(entry->sort_title, "an ", 3)) entry->sort_title += 3;
        else if (!strncmp(entry->sort_title, "the ", 4)) entry->sort_title += 4;
        Text base = {0};
        append(&base, letters_only(plain(lead.last)));
        for (const char *p = field(entry->fields, "year"); *p; ++p) if (digit(*p)) append_char(&base, *p);
        Strings words = split(entry->plain_title, " ", false, true);
        for (size_t j = 0; j < words.count; ++j) {
            char *word = letters_only(words.data[j]);
            if (*word && !small_word(word)) { append(&base, word); break; }
        }
        entry->base_key = finish(&base);
    }
    bool assigned[400] = {0};
    for (int i = 0; i < entry_count; ++i) if (!assigned[i]) {
        int group[400], count = 0;
        for (int j = i; j < entry_count; ++j) if (same_names(primary(&entries[i]), primary(&entries[j])) && !strcmp(field(entries[i].fields, "year"), field(entries[j].fields, "year"))) {
            group[count++] = j; assigned[j] = true;
        }
        if (count > 1) {
            qsort(group, (size_t)count, sizeof *group, title_compare);
            for (int j = 0; j < count; ++j) entries[group[j]].suffix = (char)('a' + j);
        }
    }
}

static char *list_names(Strings names, const char *conjunction, bool list_b) {
    if (names.count == 1) return names.data[0];
    if (list_b && names.count == 2) return format("%s %s %s", names.data[0], conjunction, names.data[1]);
    return format("%s, %s %s", join_range(names, 0, names.count - 1, ", "), conjunction, names.data[names.count - 1]);
}
static char *render_names(NameList *names, Style style, bool editor) {
    Strings forms = {0};
    for (size_t i = 0; i < names->count; ++i) {
        bool inverted = !editor && (style == APA || (style != IEEE && i == 0));
        PUSH(&forms, name_text(names->data[i], inverted, style == APA || style == IEEE));
    }
    if (editor) return names->et_al ? format("%s et al.", forms.data[0]) : list_names(forms, style == APA ? "&" : "and", true);
    if (style == APA) {
        if (names->et_al) return format("%s, et al.", join(forms, ", "));
        if (names->count >= 21) return format("%s, . . . %s", join_range(forms, 0, 19, ", "), forms.data[forms.count - 1]);
        return list_names(forms, "&", false);
    }
    if (style == IEEE) return names->et_al || names->count >= 7 ? format("%s et al.", forms.data[0]) : list_names(forms, "and", true);
    if (style == CHICAGO) return names->et_al || names->count >= 11 ? format("%s, et al.", join_range(forms, 0, forms.count < 7 ? forms.count : 7, ", ")) : list_names(forms, "and", false);
    return names->et_al || names->count >= 3 ? format("%s, et al.", forms.data[0]) : list_names(forms, "and", false);
}
static char *year_label(Entry *entry, Style style) {
    return entry->suffix && (style == APA || style == CHICAGO) ? format("%s%c", entry->year, entry->suffix) : entry->year;
}
static char *page_text(const char *value) {
    char *text = plain(value);
    Text result = {0};
    for (size_t i = 0; text[i]; ++i) {
        append_char(&result, text[i]);
        if (text[i] == '-' && text[i + 1] == '-') ++i;
    }
    return finish(&result);
}
static char *edition_text(const char *value) {
    char *text = plain(value);
    if (!all_digits(text)) return format("%s ed.", text);
    int number = atoi(text), last = number % 10, last_two = number % 100;
    const char *suffix = last_two >= 11 && last_two <= 13 ? "th" : last == 1 ? "st" : last == 2 ? "nd" : last == 3 ? "rd" : "th";
    return format("%d%s ed.", number, suffix);
}
static const char *const templates[4][6] = {
    {
        "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
    }, {
        "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>"
    }, {
        "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
    }, {
        "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "{author}. {title}.< {edition},> {publisher}, {year}.",
        "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "{author}. {title}. {year}. {school}, PhD dissertation.",
        "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
    }
};
static int placeholder_index(const char *name) {
    int index = known_index(name);
    return index >= 0 ? index : !strcmp(name, "eds") ? 18 : !strcmp(name, "pp") ? 19 : 20;
}
static size_t optional_end(const char *pattern, size_t start) {
    int depth = 1;
    size_t end = start + 1;
    for (; depth; ++end) { if (pattern[end] == '<') ++depth; if (pattern[end] == '>') --depth; }
    return end - 1;
}
static bool optional_present(const char *pattern, size_t start, size_t end, char **values) {
    for (size_t i = start; i < end; ++i) {
        if (pattern[i] == '<') i = optional_end(pattern, i);
        else if (pattern[i] == '{') {
            size_t close = (size_t)(strchr(pattern + i, '}') - pattern);
            if (!*values[placeholder_index(slice(pattern, i + 1, close))]) return false;
            i = close;
        }
    }
    return true;
}
static void render_template(const char *pattern, size_t start, size_t end, char **values, Text *output) {
    for (size_t i = start; i < end; ++i) {
        if (pattern[i] == '<') {
            size_t close = optional_end(pattern, i);
            if (optional_present(pattern, i + 1, close, values)) render_template(pattern, i + 1, close, values, output);
            i = close;
        } else if (pattern[i] == '{') {
            size_t close = (size_t)(strchr(pattern + i, '}') - pattern);
            append(output, values[placeholder_index(slice(pattern, i + 1, close))]); i = close;
        } else if (pattern[i] != '.' || !output->count || !strchr(".?!", output->data[output->count - 1])) append_char(output, pattern[i]);
    }
}
static char *reference(Entry *entry, Style style, int number, bool repeated) {
    char *values[21];
    for (int i = 0; i < 21; ++i) values[i] = "";
    for (int i = 0; i < 18; ++i) {
        char *value = field(entry->fields, known_fields[i]);
        if (value) values[i] = plain(value);
    }
    NameList *names = primary(entry);
    values[0] = repeated ? "---" : render_names(names, style, false);
    if (!entry->has_author) {
        static const char *const annotations[4][2] = {{" (Ed.)", " (Eds.)"}, {", Ed.", ", Eds."}, {", ed.", ", eds."}, {", editor", ", editors"}};
        values[0] = format("%s%s", values[0], annotations[style][names->count != 1 || names->et_al]);
    }
    if (entry->has_editor) {
        values[1] = render_names(&entry->editors, style, true);
        values[18] = entry->editors.count == 1 && !entry->editors.et_al ? "Ed." : "Eds.";
    }
    values[2] = plain(title_case(field(entry->fields, "title"), style));
    values[15] = year_label(entry, style);
    char *pages = field(entry->fields, "pages"), *edition = field(entry->fields, "edition"), *month = field(entry->fields, "month");
    if (pages) { values[8] = page_text(pages); values[19] = format("%s %s", strchr(values[8], '-') ? "pp." : "p.", values[8]); }
    if (edition) values[5] = edition_text(edition);
    if (month) {
        values[20] = plain(month);
        for (int i = 0; i < 12; ++i) if (!strcmp(values[20], months[i])) { values[20] = (char *)month_short[i]; break; }
    }
    int type = entry->type == 3 ? 2 : entry->type > 3 ? entry->type - 1 : entry->type;
    const char *pattern = templates[style][type];
    Text result = {0};
    if (style == IEEE) append(&result, format("[%d] ", number));
    render_template(pattern, 0, strlen(pattern), values, &result);
    return finish(&result);
}

static void ieee_order(int *order, int *numbers) {
    bool cited[400] = {0};
    for (int i = 0; i < citation_count; ++i) { order[i] = citation_record[i]; cited[order[i]] = true; }
    int count = citation_count;
    for (int i = 0; i < entry_count; ++i) if (!cited[i]) order[count++] = i;
    qsort(order + citation_count, (size_t)(count - citation_count), sizeof *order, key_compare);
    for (int i = 0; i < count; ++i) numbers[order[i]] = i + 1;
}
static char *short_name(Entry *entry, Style style, bool parenthetical) {
    NameList *names = primary(entry);
    if (names->et_al || names->count >= (style == CHICAGO ? 4u : 3u)) return format("%s et al.", surname(names->data[0]));
    Strings forms = {0};
    for (size_t i = 0; i < names->count; ++i) PUSH(&forms, surname(names->data[i]));
    return list_names(forms, style == APA && parenthetical ? "&" : "and", true);
}
typedef struct { int *data; size_t count, capacity; } Indices;
typedef enum { PARENTHETICAL, NARRATIVE, AUTHOR, YEAR } CitationKind;
typedef struct { size_t start, end; CitationKind kind; Indices keys; } Citation;
typedef struct { Citation *data; size_t count, capacity; } Citations;
static int number_compare(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }
static char *citation_text(Citation citation, Style style, const int *numbers) {
    bool parenthetical = citation.kind == PARENTHETICAL;
    Strings parts = {0};
    if (citation.kind == AUTHOR || citation.kind == YEAR || style == MLA || (style == IEEE && !parenthetical)) {
        for (size_t i = 0; i < citation.keys.count; ++i) {
            int index = citation.keys.data[i];
            Entry *entry = &entries[index];
            char *value = citation.kind == YEAR ? year_label(entry, style) : short_name(entry, style, false);
            if (style == IEEE && citation.kind == NARRATIVE) value = format("%s [%d]", value, numbers[index]);
            PUSH(&parts, value);
        }
        char *text = join(parts, citation.kind == YEAR ? ", " : "; ");
        return style == MLA && parenthetical ? format("(%s)", text) : text;
    }
    if (style == IEEE) {
        int sorted[400];
        for (size_t i = 0; i < citation.keys.count; ++i) sorted[i] = numbers[citation.keys.data[i]];
        qsort(sorted, citation.keys.count, sizeof *sorted, number_compare);
        for (size_t i = 0; i < citation.keys.count;) {
            size_t end = i + 1;
            while (end < citation.keys.count && sorted[end] == sorted[end - 1] + 1) ++end;
            if (end - i >= 3) PUSH(&parts, format("[%d]-[%d]", sorted[i], sorted[end - 1]));
            else for (size_t j = i; j < end; ++j) PUSH(&parts, format("[%d]", sorted[j]));
            i = end;
        }
        return join(parts, ", ");
    }
    if (parenthetical) qsort(citation.keys.data, citation.keys.count, sizeof *citation.keys.data, bibliography_compare);
    for (size_t i = 0; i < citation.keys.count;) {
        char *name = short_name(&entries[citation.keys.data[i]], style, parenthetical);
        Strings years = {0};
        size_t end = i;
        do {
            PUSH(&years, year_label(&entries[citation.keys.data[end]], style)); ++end;
        } while (end < citation.keys.count && !strcmp(name, short_name(&entries[citation.keys.data[end]], style, parenthetical)));
        char *value = parenthetical ? format("%s%s%s", name, style == APA ? ", " : " ", join(years, ", ")) : format("%s (%s)", name, join(years, ", "));
        PUSH(&parts, value); i = end;
    }
    char *text = join(parts, "; ");
    return parenthetical ? format("(%s)", text) : text;
}
static void cite(Style style, const char *text) {
    Citations citations = {0};
    for (size_t i = 0; text[i]; ++i) if (text[i] == '\\') {
        size_t brace = (size_t)(strchr(text + i, '{') - text), end = (size_t)(strchr(text + brace, '}') - text);
        char *command = slice(text, i + 1, brace);
        Citation citation = {.start = i, .end = end + 1, .kind = !strcmp(command, "citet") ? NARRATIVE : !strcmp(command, "citeauthor") ? AUTHOR : !strcmp(command, "citeyear") ? YEAR : PARENTHETICAL};
        Strings keys = split(slice(text, brace + 1, end), ",", false, false);
        bool seen[400] = {0};
        for (size_t j = 0; j < keys.count; ++j) {
            int index = find_entry(keys.data[j]);
            if (index < 0) { printf("ERROR unknown key '%s'\n", keys.data[j]); return; }
            if (!seen[index]) { PUSH(&citation.keys, index); seen[index] = true; }
        }
        PUSH(&citations, citation); i = end;
    }
    bool recorded[400] = {0};
    for (int i = 0; i < citation_count; ++i) recorded[citation_record[i]] = true;
    for (size_t i = 0; i < citations.count; ++i) for (size_t j = 0; j < citations.data[i].keys.count; ++j) {
        int index = citations.data[i].keys.data[j];
        if (!recorded[index]) { citation_record[citation_count++] = index; recorded[index] = true; }
    }
    int order[400], numbers[400];
    ieee_order(order, numbers);
    Text result = {0};
    size_t position = 0;
    for (size_t i = 0; i < citations.count; ++i) {
        Citation citation = citations.data[i];
        append_n(&result, text + position, citation.start - position);
        append(&result, citation_text(citation, style, numbers)); position = citation.end;
    }
    append(&result, text + position); puts(finish(&result));
}
static Strings unknown_fields(Entry *entry) {
    Strings result = {0};
    for (size_t i = 0; i < entry->fields.count; ++i) if (known_index(entry->fields.data[i].name) < 0) PUSH(&result, entry->fields.data[i].name);
    if (result.count) qsort(result.data, result.count, sizeof *result.data, string_compare);
    return result;
}
static void keygen(void) {
    for (int i = 0; i < entry_count; ++i) {
        int count = 0, earlier = 0;
        for (int j = 0; j < entry_count; ++j) if (!strcmp(entries[i].base_key, entries[j].base_key)) { ++count; if (j < i) ++earlier; }
        printf("%s -> %s", entries[i].key, entries[i].base_key);
        if (count > 1) putchar('a' + earlier);
        putchar('\n');
    }
}
static void check(void) {
    size_t count = 0;
    for (int i = 0; i < entry_count; ++i) {
        Entry *entry = &entries[i];
        Strings warnings = {0};
        char *pages = field(entry->fields, "pages");
        if (pages) {
            pages = plain(pages);
            if (strchr(pages, '-') && !strstr(pages, "--")) PUSH(&warnings, "pages use a single hyphen");
            Strings parts = split(pages, "-", false, true);
            if (parts.count == 2 && all_digits(parts.data[0]) && all_digits(parts.data[1]) && strtol(parts.data[0], NULL, 10) > strtol(parts.data[1], NULL, 10)) PUSH(&warnings, "pages are reversed");
        }
        if (strlen(entry->year) != 4 || !all_digits(entry->year)) PUSH(&warnings, "year is not 4 digits");
        size_t lower_count = 0, upper_count = 0;
        for (const char *p = entry->plain_title; *p; ++p) { lower_count += lower(*p); upper_count += upper(*p); }
        if (!lower_count && upper_count >= 2) PUSH(&warnings, "title is all caps");
        if (entry->type == 0 && !field(entry->fields, "doi")) PUSH(&warnings, "article has no doi");
        for (int j = 0; j < i; ++j) if (!strcmp(entry->lower_title, entries[j].lower_title)) { PUSH(&warnings, format("same title as %s", entries[j].key)); break; }
        Strings unknown = unknown_fields(entry);
        for (size_t j = 0; j < unknown.count; ++j) PUSH(&warnings, format("unknown field '%s'", unknown.data[j]));
        for (size_t j = 0; j < warnings.count; ++j) printf("WARN %s: %s\n", entry->key, warnings.data[j]);
        count += warnings.count;
    }
    printf("CHECK warnings=%zu\n", count);
}
static void export_entry(Entry *entry) {
    Strings names = {0};
    for (int i = 0; i < 18; ++i) if (field(entry->fields, known_fields[i])) PUSH(&names, (char *)known_fields[i]);
    Strings unknown = unknown_fields(entry);
    for (size_t i = 0; i < unknown.count; ++i) PUSH(&names, unknown.data[i]);
    printf("@%s{%s,\n", type_names[entry->type], entry->key);
    for (size_t i = 0; i < names.count; ++i) printf("  %s = {%s}%s\n", names.data[i], field(entry->fields, names.data[i]), i + 1 == names.count ? "" : ",");
    puts("}");
}
typedef struct { char *a, *b; } Pair;
typedef struct { Pair *data; size_t count, capacity; } Pairs;
static int pair_compare(const void *left, const void *right) {
    const Pair *a = left, *b = right;
    int comparison = strcmp(a->a, b->a);
    return comparison ? comparison : strcmp(a->b, b->b);
}
static void stats(void) {
    printf("ENTRIES %d\n", entry_count);
    Strings types = {0}, years = {0}, authors = {0};
    Pairs pairs = {0};
    for (int i = 0; i < entry_count; ++i) {
        Entry *entry = &entries[i];
        add_unique(&types, (char *)type_names[entry->type]); add_unique(&years, entry->year);
        if (entry->has_author) {
            Strings names = {0};
            for (size_t j = 0; j < entry->authors.count; ++j) {
                char *name = name_text(entry->authors.data[j], false, false);
                add_unique(&names, name); add_unique(&authors, name);
            }
            qsort(names.data, names.count, sizeof *names.data, string_compare);
            for (size_t a = 0; a < names.count; ++a) for (size_t b = a + 1; b < names.count; ++b) PUSH(&pairs, ((Pair){names.data[a], names.data[b]}));
        }
    }
    if (types.count) qsort(types.data, types.count, sizeof *types.data, string_compare);
    if (years.count) qsort(years.data, years.count, sizeof *years.data, string_compare);
    for (size_t i = 0; i < types.count; ++i) {
        int count = 0;
        for (int j = 0; j < entry_count; ++j) count += !strcmp(types.data[i], type_names[entries[j].type]);
        printf("TYPE %s %d\n", types.data[i], count);
    }
    for (size_t i = 0; i < years.count; ++i) {
        int count = 0;
        for (int j = 0; j < entry_count; ++j) count += !strcmp(years.data[i], entries[j].year);
        printf("YEAR %s %d\n", years.data[i], count);
    }
    printf("AUTHORS %zu\n", authors.count);
    if (!pairs.count) { puts("PAIR none"); return; }
    qsort(pairs.data, pairs.count, sizeof *pairs.data, pair_compare);
    size_t best = 0, best_count = 0;
    for (size_t i = 0; i < pairs.count;) {
        size_t end = i + 1;
        while (end < pairs.count && !pair_compare(&pairs.data[i], &pairs.data[end])) ++end;
        if (end - i > best_count) { best = i; best_count = end - i; }
        i = end;
    }
    printf("PAIR %s & %s %zu\n", pairs.data[best].a, pairs.data[best].b, best_count);
}
static Strings command_words(const char *line) {
    size_t length = strlen(line), first = strcspn(line, " ");
    char *command = slice(line, 0, first);
    if (strcmp(command, "CITE") && strcmp(command, "SEARCH")) return split(line, " ", false, false);
    Strings words = {0}; PUSH(&words, command);
    if (first == length) return words;
    size_t second = first + 1 + strcspn(line + first + 1, " ");
    PUSH(&words, slice(line, first + 1, second));
    if (second < length) PUSH(&words, slice(line, second + 1, length));
    return words;
}
static void command(const char *line) {
    static const char *const commands[] = {"FORMAT", "BIBLIOGRAPHY", "CITE", "KEYGEN", "CHECK", "SEARCH", "EXPORT", "STATS"};
    static const int arities[] = {-1, 1, 2, 0, 0, 2, 1, 0};
    static const char *const styles[] = {"APA", "IEEE", "CHICAGO", "MLA"};
    Strings words = command_words(line);
    int kind = -1;
    for (int i = 0; i < 8; ++i) if (!strcmp(words.data[0], commands[i])) kind = i;
    if (kind < 0) { printf("ERROR unknown command '%s'\n", words.data[0]); return; }
    if (kind == 0 ? words.count < 3 : words.count != (size_t)arities[kind] + 1) { puts("ERROR wrong number of arguments"); return; }
    Style style = APA;
    if (kind <= 2) {
        int index = -1;
        for (int i = 0; i < 4; ++i) if (!strcmp(words.data[1], styles[i])) index = i;
        if (index < 0) { printf("ERROR unknown style '%s'\n", words.data[1]); return; }
        style = (Style)index;
    }
    if (kind == 0 || kind == 1) {
        int order[400], numbers[400]; ieee_order(order, numbers);
        if (kind == 0) {
            for (size_t i = 2; i < words.count; ++i) {
                int index = find_entry(words.data[i]);
                if (index < 0) printf("ERROR unknown key '%s'\n", words.data[i]);
                else puts(reference(&entries[index], style, numbers[index], false));
            }
        } else {
            puts(style == MLA ? "Works Cited" : "References");
            if (style != IEEE) qsort(order, (size_t)entry_count, sizeof *order, bibliography_compare);
            for (int i = 0; i < entry_count; ++i) {
                bool repeated = i > 0 && (style == CHICAGO || style == MLA) && same_names(primary(&entries[order[i]]), primary(&entries[order[i - 1]]));
                puts(reference(&entries[order[i]], style, numbers[order[i]], repeated));
            }
        }
    } else if (kind == 2) cite(style, words.data[2]);
    else if (kind == 3) keygen();
    else if (kind == 4) check();
    else if (kind == 5) {
        Strings matches = {0};
        char *needle = lower_string(words.data[2]);
        for (int i = 0; i < entry_count; ++i) {
            char *value = field(entries[i].fields, words.data[1]);
            if (value && strstr(lower_string(plain(value)), needle)) PUSH(&matches, entries[i].key);
        }
        if (matches.count) printf("MATCHES %zu: %s\n", matches.count, join(matches, " "));
        else puts("MATCHES 0");
    } else if (kind == 6) {
        int index = find_entry(words.data[1]);
        if (index < 0) printf("ERROR unknown key '%s'\n", words.data[1]);
        else export_entry(&entries[index]);
    } else stats();
}
int main(void) {
    read_database(); prepare_entries();
    char line[604];
    if (read_line(line, sizeof line)) {
        int count = atoi(line);
        arena = &command_arena;
        for (int i = 0; i < count && read_line(line, sizeof line); ++i) { command(line); clear_arena(&command_arena); }
    }
    clear_arena(&database_arena);
    return 0;
}
