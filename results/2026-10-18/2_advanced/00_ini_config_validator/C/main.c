#include "main.h"
#include "ini_parser.h"
#include "schema.h"
#include "interpolate.h"
#include "emitter.h"
#include <stdarg.h>
#include <inttypes.h>

void *checked_realloc(void *pointer, size_t size) {
    /* Parsed data and immutable definitions remain live for this command's lifetime. */
    void *result = realloc(pointer, size ? size : 1);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

char *slice(const char *text, size_t start, size_t length) {
    char *result = checked_realloc(NULL, length + 1);
    memcpy(result, text + start, length);
    result[length] = '\0';
    return result;
}

char *copy_text(const char *text) { return slice(text, 0, strlen(text)); }

char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern);
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = checked_realloc(NULL, (size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}

void buffer_char(Buffer *buffer, char ch) {
    if (buffer->len + 1 >= buffer->cap) {
        buffer->cap = buffer->cap ? buffer->cap * 2 : 32;
        buffer->data = checked_realloc(buffer->data, buffer->cap);
    }
    buffer->data[buffer->len++] = ch;
    buffer->data[buffer->len] = '\0';
}

void buffer_text(Buffer *buffer, const char *text) {
    for (; *text; ++text) buffer_char(buffer, *text);
}

char *buffer_result(Buffer *buffer) { return buffer->data ? buffer->data : copy_text(""); }

char *read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    Buffer buffer = {0};
    char block[4096];
    size_t count;
    while ((count = fread(block, 1, sizeof block, file)))
        for (size_t i = 0; i < count; ++i) buffer_char(&buffer, block[i]);
    if (ferror(file)) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
    return buffer_result(&buffer);
}

Strings split(const char *text, char separator) {
    Strings parts = {0};
    size_t start = 0;
    for (size_t i = 0;; ++i) {
        if (text[i] == separator || !text[i]) {
            PUSH(parts, slice(text, start, i - start));
            start = i + 1;
        }
        if (!text[i]) break;
    }
    return parts;
}

Strings file_lines(const char *text) {
    Strings lines = split(text, '\n');
    if (lines.len && !*lines.data[lines.len - 1]) --lines.len;
    return lines;
}

char *trim_spaces(const char *text) {
    while (*text == ' ') ++text;
    size_t length = strlen(text);
    while (length && text[length - 1] == ' ') --length;
    return slice(text, 0, length);
}

char *lowercase(const char *text) {
    char *result = copy_text(text);
    for (char *p = result; *p; ++p)
        if (*p >= 'A' && *p <= 'Z') *p = (char)(*p - 'A' + 'a');
    return result;
}

char *section_of(const char *key) { return slice(key, 0, (size_t)(strrchr(key, '.') - key)); }
const char *name_of(const char *key) { return strrchr(key, '.') + 1; }

int compare_keys(const char *first, const char *second) {
    size_t a = (size_t)(strrchr(first, '.') - first), b = (size_t)(strrchr(second, '.') - second);
    int comparison = memcmp(first, second, a < b ? a : b);
    if (comparison) return comparison;
    if (a != b) return a < b ? -1 : 1;
    return strcmp(first + a + 1, second + b + 1);
}

int key_comparator(const void *first, const void *second) {
    return compare_keys(*(const char *const *)first, *(const char *const *)second);
}

bool strings_contain(Strings strings, const char *text) {
    for (size_t i = 0; i < strings.len; ++i)
        if (!strcmp(strings.data[i], text)) return true;
    return false;
}

char *join_strings(Strings strings, const char *separator) {
    Buffer result = {0};
    for (size_t i = 0; i < strings.len; ++i) {
        if (i) buffer_text(&result, separator);
        buffer_text(&result, strings.data[i]);
    }
    return buffer_result(&result);
}

bool same_origin(Origin first, Origin second) {
    return first.line == second.line && !strcmp(first.document, second.document);
}

char *origin_text(Origin origin) { return format("%s:%d", origin.document, origin.line); }

void report(Diagnostics *diagnostics, Origin origin, const char *code, char *message) {
    for (size_t i = 0; i < diagnostics->len; ++i) {
        Diagnostic previous = diagnostics->data[i];
        if (same_origin(previous.origin, origin) && !strcmp(previous.code, code) && !strcmp(previous.message, message))
            return;
    }
    Diagnostic diagnostic = {origin, copy_text(code), message};
    PUSH(*diagnostics, diagnostic);
}

int configuration_index(Configuration configuration, const char *key) {
    for (size_t i = 0; i < configuration.len; ++i)
        if (!strcmp(configuration.data[i].key, key)) return (int)i;
    return -1;
}

int output_index(Outputs outputs, const char *key) {
    for (size_t i = 0; i < outputs.len; ++i)
        if (!strcmp(outputs.data[i].key, key)) return (int)i;
    return -1;
}

Strings configuration_keys(Configuration configuration) {
    Strings result = {0};
    for (size_t i = 0; i < configuration.len; ++i) PUSH(result, configuration.data[i].key);
    if (result.len > 1) qsort(result.data, result.len, sizeof *result.data, key_comparator);
    return result;
}

Strings output_keys(Outputs outputs) {
    Strings result = {0};
    for (size_t i = 0; i < outputs.len; ++i) PUSH(result, outputs.data[i].key);
    if (result.len > 1) qsort(result.data, result.len, sizeof *result.data, key_comparator);
    return result;
}

static int diagnostic_comparator(const void *first, const void *second) {
    const Diagnostic *a = first, *b = second;
    int comparison = strcmp(a->origin.document, b->origin.document);
    if (comparison) return comparison;
    if (a->origin.line != b->origin.line) return a->origin.line < b->origin.line ? -1 : 1;
    comparison = strcmp(a->code, b->code);
    return comparison ? comparison : strcmp(a->message, b->message);
}

void sort_diagnostics(Profile *profile) {
    if (profile->diagnostics.len > 1)
        qsort(profile->diagnostics.data, profile->diagnostics.len, sizeof *profile->diagnostics.data,
              diagnostic_comparator);
    for (size_t i = 0; i < profile->diagnostics.len; ++i) {
        if (profile->diagnostics.data[i].code[0] == 'E') ++profile->errors;
        else ++profile->warnings;
    }
}

static bool digit(char ch) { return ch >= '0' && ch <= '9'; }
static bool letter(char ch) { return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'); }

static bool decimal(const char *text, size_t minimum, size_t maximum, int64_t *number) {
    size_t length = strlen(text);
    if (length < minimum || length > maximum) return false;
    *number = 0;
    for (size_t i = 0; i < length; ++i) {
        if (!digit(text[i])) return false;
        *number = *number * 10 + text[i] - '0';
    }
    return true;
}

static bool parse_integer(const char *text, int64_t *number) {
    int sign = 1;
    if (*text == '+' || *text == '-') {
        if (*text == '-') sign = -1;
        ++text;
    }
    *number = 0;
    if (text[0] == '0' && (text[1] == 'x' || text[1] == 'X')) {
        text += 2;
        size_t length = strlen(text);
        if (length < 1 || length > 10) return false;
        for (; *text; ++text) {
            char ch = *text;
            int value = digit(ch) ? ch - '0' :
                        ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 :
                        ch >= 'A' && ch <= 'F' ? ch - 'A' + 10 : -1;
            if (value < 0) return false;
            *number = *number * 16 + value;
        }
    } else {
        size_t digits = 0;
        bool previous_digit = false;
        for (size_t i = 0; text[i]; ++i) {
            if (digit(text[i])) {
                if (++digits > 12) return false;
                *number = *number * 10 + text[i] - '0';
                previous_digit = true;
            } else if (text[i] == '_' && previous_digit && digit(text[i + 1])) {
                previous_digit = false;
            } else return false;
        }
        if (!digits || !previous_digit) return false;
    }
    *number *= sign;
    return true;
}

static bool parse_size(const char *text, int64_t *number) {
    size_t position = 0;
    while (digit(text[position])) ++position;
    int64_t whole;
    if (!decimal(slice(text, 0, position), 1, 6, &whole)) return false;
    int64_t fraction = 0, divisor = 1;
    if (text[position] == '.') {
        size_t start = ++position;
        while (digit(text[position])) ++position;
        if (!decimal(slice(text, start, position - start), 1, 3, &fraction)) return false;
        for (size_t i = start; i < position; ++i) divisor *= 10;
    }
    char *unit = lowercase(text + position);
    int64_t factor;
    if (!*unit || !strcmp(unit, "b")) factor = 1;
    else if (!strcmp(unit, "kb")) factor = 1024;
    else if (!strcmp(unit, "mb")) factor = 1048576;
    else if (!strcmp(unit, "gb")) factor = 1073741824;
    else return false;
    if (fraction * factor % divisor) return false;
    *number = whole * factor + fraction * factor / divisor;
    return true;
}

static bool parse_duration(const char *text, int64_t *number) {
    if (decimal(text, 1, 6, number)) return true;
    *number = 0;
    int previous = -1;
    size_t position = 0;
    while (text[position]) {
        size_t start = position;
        while (digit(text[position])) ++position;
        int64_t part;
        if (!decimal(slice(text, start, position - start), 1, 6, &part)) return false;
        char unit = text[position];
        int rank = unit == 'h' ? 0 : unit == 'm' ? 1 : unit == 's' ? 2 : -1;
        if (rank <= previous) return false;
        previous = rank;
        *number += part * (rank == 0 ? 3600 : rank == 1 ? 60 : 1);
        ++position;
    }
    return previous >= 0;
}

static char *parse_host(const char *text) {
    bool ipv4 = true;
    for (const char *p = text; *p; ++p)
        if (!digit(*p) && *p != '.') ipv4 = false;
    Strings labels = split(text, '.');
    if (ipv4) {
        if (labels.len != 4) return NULL;
        for (size_t i = 0; i < labels.len; ++i) {
            char *part = labels.data[i];
            int64_t number;
            if (!decimal(part, 1, 3, &number) || (part[0] == '0' && part[1]) || number > 255) return NULL;
        }
        return copy_text(text);
    }
    if (strlen(text) > 253) return NULL;
    for (size_t i = 0; i < labels.len; ++i) {
        char *label = labels.data[i];
        size_t length = strlen(label);
        if (!length || length > 63 || *label == '-' || label[length - 1] == '-') return NULL;
        for (size_t j = 0; j < length; ++j)
            if (!letter(label[j]) && !digit(label[j]) && label[j] != '-') return NULL;
    }
    return lowercase(text);
}

static char *parse_path(const char *text) {
    if (!*text || strpbrk(text, " \n\t")) return NULL;
    bool absolute = *text == '/';
    Strings parts = split(text, '/'), normalized = {0};
    for (size_t i = 0; i < parts.len; ++i) {
        char *part = parts.data[i];
        if (!*part || !strcmp(part, ".")) continue;
        if (strcmp(part, "..")) PUSH(normalized, part);
        else if (normalized.len && strcmp(normalized.data[normalized.len - 1], "..")) --normalized.len;
        else if (absolute) return NULL;
        else PUSH(normalized, part);
    }
    char *joined = join_strings(normalized, "/");
    return absolute ? format("/%s", joined) : normalized.len ? joined : ".";
}

static char *parse_url(const char *text) {
    const char *separator = strstr(text, "://");
    if (!separator) return NULL;
    char *scheme = slice(text, 0, (size_t)(separator - text));
    if (!letter(*scheme)) return NULL;
    for (const char *p = scheme; *p; ++p)
        if (!letter(*p) && !digit(*p) && *p != '+' && *p != '-' && *p != '.') return NULL;
    const char *rest = separator + 3;
    if (strpbrk(rest, "?#")) return NULL;
    const char *slash = strchr(rest, '/');
    char *authority = slash ? slice(rest, 0, (size_t)(slash - rest)) : copy_text(rest);
    char *colon = strchr(authority, ':'), *port = colon ? colon + 1 : NULL;
    if (colon) *colon = '\0';
    char *host = parse_host(authority), *path = parse_path(slash ? slash : "/");
    if (!host || !path) return NULL;
    scheme = lowercase(scheme);
    bool keep_port = false;
    if (port) {
        int64_t number;
        if (!decimal(port, 1, 5, &number) || *port == '0' || number > 65535) return NULL;
        keep_port = !((!strcmp(scheme, "http") && number == 80) ||
                      (!strcmp(scheme, "https") && number == 443));
    }
    return format("%s://%s%s%s%s", scheme, host, keep_port ? ":" : "", keep_port ? port : "", path);
}

static char *parse_date(const char *text) {
    if (strlen(text) != 10 || text[4] != '-' || text[7] != '-') return NULL;
    int64_t year, month, day;
    if (!decimal(slice(text, 0, 4), 4, 4, &year) || !decimal(slice(text, 5, 2), 2, 2, &month) ||
        !decimal(text + 8, 2, 2, &day) || year < 1 || month < 1 || month > 12) return NULL;
    static const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int limit = days[month - 1];
    if (month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)) ++limit;
    return day >= 1 && day <= limit ? copy_text(text) : NULL;
}

static bool parse_scalar(Kind kind, const char *text, Strings choices, Value *value) {
    *value = (Value){.kind = kind};
    switch (kind) {
        case TYPE_STRING: value->text = copy_text(text); return true;
        case TYPE_INT: return parse_integer(text, &value->number);
        case TYPE_SIZE: return parse_size(text, &value->number);
        case TYPE_DURATION: return parse_duration(text, &value->number);
        case TYPE_BOOL: {
            char *lower = lowercase(text);
            if (!strcmp(lower, "true") || !strcmp(lower, "yes") || !strcmp(lower, "on") || !strcmp(lower, "1"))
                value->number = 1;
            else if (strcmp(lower, "false") && strcmp(lower, "no") && strcmp(lower, "off") && strcmp(lower, "0"))
                return false;
            return true;
        }
        case TYPE_ENUM: {
            char *lower = lowercase(text);
            for (size_t i = 0; i < choices.len; ++i)
                if (!strcmp(lower, lowercase(choices.data[i]))) {
                    value->text = choices.data[i];
                    return true;
                }
            return false;
        }
        case TYPE_HOST: value->text = parse_host(text); break;
        case TYPE_PATH: value->text = parse_path(text); break;
        case TYPE_URL: value->text = parse_url(text); break;
        case TYPE_DATE: value->text = parse_date(text); break;
        case TYPE_LIST: return false;
    }
    return value->text != NULL;
}

static void invalid_value(Profile *profile, char *key, Spec *spec, Kind kind,
                          const char *text, bool item, Origin origin) {
    char *display = spec->secret ? "********" : string_notation(text);
    if (item) display = format("item %s", display);
    if (kind == TYPE_ENUM)
        report(&profile->diagnostics, origin, "E_ENUM",
               format("%s: %s is not one of %s", key, display, join_strings(spec->values, ",")));
    else
        report(&profile->diagnostics, origin, "E_TYPE",
               format("%s: %s is not a valid %s", key, display, kind_name(kind)));
}

static bool check_range(Profile *profile, char *key, Spec *spec, Value value, Origin origin) {
    if (!spec->lower) return true;
    char *bounds[2] = {spec->lower, spec->upper};
    char *notations[2] = {"", ""};
    bool invalid = false;
    int64_t measure = spec->kind == TYPE_STRING ? (int64_t)strlen(value.text) :
                      spec->kind == TYPE_LIST ? (int64_t)value.count : value.number;
    for (int i = 0; i < 2; ++i) {
        if (!*bounds[i]) continue;
        int comparison;
        if (spec->kind == TYPE_DATE) {
            notations[i] = bounds[i];
            comparison = strcmp(value.text, bounds[i]);
        } else {
            Value bound;
            if (spec->kind == TYPE_STRING || spec->kind == TYPE_LIST) {
                bound = (Value){.kind = TYPE_INT, .number = strtoll(bounds[i], NULL, 10)};
            } else {
                if (!parse_scalar(spec->kind, bounds[i], (Strings){0}, &bound)) exit(EXIT_FAILURE);
            }
            notations[i] = value_notation(bound);
            comparison = measure < bound.number ? -1 : measure > bound.number ? 1 : 0;
        }
        if ((i == 0 && comparison < 0) || (i == 1 && comparison > 0)) invalid = true;
    }
    if (!invalid) return true;
    char *display;
    if (spec->kind == TYPE_STRING) display = format("length %" PRId64, measure);
    else if (spec->kind == TYPE_LIST) display = format("count %" PRId64, measure);
    else display = spec->secret ? "********" : value_notation(value);
    report(&profile->diagnostics, origin, "E_RANGE",
           format("%s: %s is out of range %s..%s", key, display, notations[0], notations[1]));
    return false;
}

static bool normalize(Profile *profile, char *key, Spec *spec, const char *text,
                      Origin origin, Value *value) {
    if (spec->kind != TYPE_LIST) {
        if (!parse_scalar(spec->kind, text, spec->values, value)) {
            invalid_value(profile, key, spec, spec->kind, text, false, origin);
            return false;
        }
    } else {
        *value = (Value){.kind = TYPE_LIST};
        if (*trim_spaces(text)) {
            Strings items = split(text, ',');
            bool empty = false, duplicate = false;
            for (size_t i = 0; i < items.len; ++i) {
                items.data[i] = trim_spaces(items.data[i]);
                if (!*items.data[i]) empty = true;
            }
            if (empty) report(&profile->diagnostics, origin, "W_EMPTY_ITEM",
                              format("%s: empty list item ignored", key));
            value->items = checked_realloc(NULL, items.len * sizeof *value->items);
            for (size_t i = 0; i < items.len; ++i) {
                if (!*items.data[i]) continue;
                Value item;
                if (!parse_scalar(spec->item, items.data[i], spec->values, &item)) {
                    invalid_value(profile, key, spec, spec->item, items.data[i], true, origin);
                    return false;
                }
                value->items[value->count++] = item;
            }
            if (spec->unique) {
                size_t count = 0;
                Strings seen = {0};
                for (size_t i = 0; i < value->count; ++i) {
                    char *notation = value_notation(value->items[i]);
                    if (strings_contain(seen, notation)) duplicate = true;
                    else {
                        PUSH(seen, notation);
                        value->items[count++] = value->items[i];
                    }
                }
                value->count = count;
            }
            if (duplicate) report(&profile->diagnostics, origin, "W_DUPLICATE_ITEM",
                                  format("%s: duplicate items removed", key));
        }
    }
    return check_range(profile, key, spec, *value, origin);
}

typedef struct { char *name; Document *document; } CachedDocument;
VECTOR(CachedDocument, DocumentCache);
typedef struct { DocumentCache documents; } Library;

static Document *find_document(Library *library, char *name) {
    for (size_t i = 0; i < library->documents.len; ++i)
        if (!strcmp(library->documents.data[i].name, name)) return library->documents.data[i].document;
    char *text = read_file(format("input/conf/%s.ini", name));
    CachedDocument cached = {name, text ? parse_document(name, text) : NULL};
    PUSH(library->documents, cached);
    return cached.document;
}

static void set_definition(Profile *profile, char *key, Definition definition) {
    int index = configuration_index(profile->configuration, key);
    if (index >= 0) profile->configuration.data[index].definition = definition;
    else {
        Entry entry = {key, definition};
        PUSH(profile->configuration, entry);
    }
}

static void define(Profile *profile, char *key, char *raw, Origin origin) {
    int index = configuration_index(profile->configuration, key);
    Origins history = {0};
    if (index >= 0) {
        Origins old = profile->configuration.data[index].definition.history;
        for (size_t i = 0; i < old.len; ++i) PUSH(history, old.data[i]);
    }
    if (!history.len || !same_origin(history.data[history.len - 1], origin)) PUSH(history, origin);
    Definition definition = {raw, origin, ++profile->definition_count, history};
    set_definition(profile, key, definition);
}

static void remove_definition(Profile *profile, const char *key) {
    int index = configuration_index(profile->configuration, key);
    if (index < 0) return;
    memmove(profile->configuration.data + index, profile->configuration.data + index + 1,
            (profile->configuration.len - (size_t)index - 1) * sizeof *profile->configuration.data);
    --profile->configuration.len;
}

static void remove_output(Profile *profile, const char *key) {
    int index = output_index(profile->outputs, key);
    if (index < 0) return;
    memmove(profile->outputs.data + index, profile->outputs.data + index + 1,
            (profile->outputs.len - (size_t)index - 1) * sizeof *profile->outputs.data);
    --profile->outputs.len;
}

static int parent_index(Parents parents, const char *section) {
    for (size_t i = 0; i < parents.len; ++i)
        if (!strcmp(parents.data[i].section, section)) return (int)i;
    return -1;
}

static void apply_document(Profile *profile, Library *library, char *name, Strings chain) {
    Document *document = find_document(library, name);
    if (!document) exit(EXIT_FAILURE);
    TreeLine branch = {(int)chain.len - 1, name};
    PUSH(profile->tree, branch);
    for (size_t i = 0; i < document->diagnostics.len; ++i) {
        Diagnostic diagnostic = document->diagnostics.data[i];
        report(&profile->diagnostics, diagnostic.origin, diagnostic.code, diagnostic.message);
    }
    for (size_t i = 0; i < document->statements.len; ++i) {
        Statement statement = document->statements.data[i];
        Origin origin = {name, statement.line};
        int index = configuration_index(profile->configuration, statement.target);
        switch (statement.kind) {
            case ASSIGN: define(profile, statement.target, statement.value, origin); break;
            case APPEND: {
                char *raw = statement.value;
                if (index >= 0 && *profile->configuration.data[index].definition.raw)
                    raw = format("%s,%s", profile->configuration.data[index].definition.raw, raw);
                define(profile, statement.target, raw, origin);
                break;
            }
            case UNSET:
                if (index >= 0) remove_definition(profile, statement.target);
                else report(&profile->diagnostics, origin, "W_UNSET", format("%s is not set", statement.target));
                break;
            case INHERIT: {
                Parent parent = {statement.target, statement.value, origin};
                int previous = parent_index(profile->parents, statement.target);
                if (previous >= 0) profile->parents.data[previous] = parent;
                else PUSH(profile->parents, parent);
                break;
            }
            case INCLUDE: {
                if (strings_contain(chain, statement.target)) {
                    Strings path = {0};
                    size_t start = 0;
                    while (strcmp(chain.data[start], statement.target)) ++start;
                    for (size_t j = start; j < chain.len; ++j) PUSH(path, chain.data[j]);
                    PUSH(path, statement.target);
                    report(&profile->diagnostics, origin, "E_INCLUDE_CYCLE",
                           format("include cycle %s", join_strings(path, " -> ")));
                    TreeLine cycle = {(int)chain.len, format("%s (cycle)", statement.target)};
                    PUSH(profile->tree, cycle);
                } else if (!find_document(library, statement.target)) {
                    report(&profile->diagnostics, origin, "E_INCLUDE_MISSING",
                           format("missing document %s", statement.target));
                    TreeLine missing = {(int)chain.len, format("%s (missing)", statement.target)};
                    PUSH(profile->tree, missing);
                } else {
                    Strings next = {0};
                    for (size_t j = 0; j < chain.len; ++j) PUSH(next, chain.data[j]);
                    PUSH(next, statement.target);
                    apply_document(profile, library, statement.target, next);
                }
                break;
            }
        }
    }
}

static void inherit_sections(Profile *profile) {
    Configuration own = {0};
    for (size_t i = 0; i < profile->configuration.len; ++i) PUSH(own, profile->configuration.data[i]);
    for (size_t i = 0; i < profile->parents.len; ++i) {
        Parent declaration = profile->parents.data[i];
        Strings chain = {0};
        PUSH(chain, declaration.section);
        int parent;
        while ((parent = parent_index(profile->parents, chain.data[chain.len - 1])) >= 0) {
            char *next = profile->parents.data[parent].parent;
            if (strings_contain(chain, next)) break;
            PUSH(chain, next);
        }
        if (parent >= 0) {
            PUSH(chain, profile->parents.data[parent].parent);
            report(&profile->diagnostics, declaration.origin, "E_INHERIT_CYCLE",
                   format("inheritance cycle %s", join_strings(chain, " -> ")));
            continue;
        }
        bool has_own = false;
        for (size_t j = 0; j < own.len; ++j)
            if (!strcmp(section_of(own.data[j].key), declaration.parent)) has_own = true;
        if (parent_index(profile->parents, declaration.parent) < 0 && !has_own)
            report(&profile->diagnostics, declaration.origin, "W_PARENT_EMPTY",
                   format("section %s inherits from empty section %s", declaration.section, declaration.parent));
        for (size_t j = 1; j < chain.len; ++j) {
            for (size_t k = 0; k < own.len; ++k) {
                Entry entry = own.data[k];
                if (strcmp(section_of(entry.key), chain.data[j])) continue;
                char *target = format("%s.%s", declaration.section, name_of(entry.key));
                if (configuration_index(profile->configuration, target) < 0)
                    set_definition(profile, target, entry.definition);
            }
        }
    }
}

static void resolve_aliases(Profile *profile, const Schema *schema) {
    for (size_t i = 0; i < schema->specs.len; ++i) {
        Spec *spec = schema->specs.data[i];
        Strings candidates = {0}, aliases = {0};
        if (configuration_index(profile->configuration, spec->pattern) >= 0) PUSH(candidates, spec->pattern);
        for (size_t j = 0; j < spec->aliases.len; ++j) {
            char *alias = spec->aliases.data[j];
            if (configuration_index(profile->configuration, alias) >= 0) {
                PUSH(candidates, alias);
                PUSH(aliases, alias);
            }
        }
        if (!aliases.len) continue;
        char *winner = candidates.data[0];
        Definition chosen = profile->configuration.data[configuration_index(profile->configuration, winner)].definition;
        for (size_t j = 1; j < candidates.len; ++j) {
            Definition candidate = profile->configuration.data[configuration_index(profile->configuration, candidates.data[j])].definition;
            if (candidate.number > chosen.number) {
                winner = candidates.data[j];
                chosen = candidate;
            }
        }
        for (size_t j = 0; j < candidates.len; ++j) {
            char *candidate = candidates.data[j];
            Origin origin = profile->configuration.data[configuration_index(profile->configuration, candidate)].definition.origin;
            if (strcmp(candidate, spec->pattern))
                report(&profile->diagnostics, origin, "W_DEPRECATED",
                       format("%s is deprecated, use %s", candidate, spec->pattern));
            if (strcmp(candidate, winner))
                report(&profile->diagnostics, origin, "W_SHADOWED",
                       format("%s is superseded by %s at %s", candidate, winner, origin_text(chosen.origin)));
        }
        set_definition(profile, spec->pattern, chosen);
        for (size_t j = 0; j < aliases.len; ++j) remove_definition(profile, aliases.data[j]);
    }
}

static Strings fill_defaults(Profile *profile, const Schema *schema) {
    Strings sections = {0};
    for (size_t i = 0; i < profile->configuration.len; ++i) {
        char *section = section_of(profile->configuration.data[i].key);
        if (!strings_contain(sections, section)) PUSH(sections, section);
    }
    for (size_t i = 0; i < schema->specs.len; ++i) {
        Spec *spec = schema->specs.data[i];
        if (!spec->default_value) continue;
        Strings targets = target_keys(schema, spec, sections);
        for (size_t j = 0; j < targets.len; ++j)
            if (configuration_index(profile->configuration, targets.data[j]) < 0)
                define(profile, targets.data[j], spec->default_value, (Origin){"schema", spec->line});
    }
    profile->configured_count = profile->configuration.len;
    return sections;
}

static void check_types(Profile *profile, const Schema *schema) {
    char **expanded = expand_configuration(profile->configuration, &profile->diagnostics);
    Strings keys = configuration_keys(profile->configuration);
    for (size_t i = 0; i < keys.len; ++i) {
        int index = configuration_index(profile->configuration, keys.data[i]);
        if (!expanded[index]) continue;
        Entry entry = profile->configuration.data[index];
        Spec *spec = spec_for(schema, entry.key);
        Value value;
        if (!spec) {
            report(&profile->diagnostics, entry.definition.origin, "W_UNKNOWN", format("%s is not in the schema", entry.key));
            value = (Value){.kind = TYPE_STRING, .text = expanded[index]};
        } else if (!normalize(profile, entry.key, spec, expanded[index], entry.definition.origin, &value)) continue;
        OutputKey output = {entry.key, entry.definition, spec, value, value_notation(value)};
        PUSH(profile->outputs, output);
    }
}

static void check_order(Profile *profile) {
    Strings removed = {0};
    for (size_t i = 0; i < profile->outputs.len; ++i) {
        OutputKey *output = &profile->outputs.data[i];
        if (!output->spec || !output->spec->le) continue;
        char *limit_key = format("%s.%s", section_of(output->key), output->spec->le);
        int index = output_index(profile->outputs, limit_key);
        if (index < 0) continue;
        OutputKey *limit = &profile->outputs.data[index];
        if (limit->value.kind != TYPE_INT && limit->value.kind != TYPE_SIZE &&
            limit->value.kind != TYPE_DURATION) continue;
        if (output->value.number > limit->value.number) {
            report(&profile->diagnostics, output->definition.origin, "E_ORDER",
                   format("%s: %s is greater than %s (%s)", output->key, shown(output), limit_key, shown(limit)));
            PUSH(removed, output->key);
        }
    }
    for (size_t i = 0; i < removed.len; ++i) remove_output(profile, removed.data[i]);
}

static void check_required(Profile *profile, const Schema *schema, Strings sections) {
    for (size_t i = 0; i < schema->specs.len; ++i) {
        Spec *spec = schema->specs.data[i];
        if (!spec->required) continue;
        Strings targets = target_keys(schema, spec, sections);
        for (size_t j = 0; j < targets.len; ++j) {
            char *key = targets.data[j];
            if (configuration_index(profile->configuration, key) >= 0) continue;
            char *message = format("%s is required", key);
            if (spec->when) {
                char *condition = format("%s.%s", section_of(key), spec->when);
                int index = output_index(profile->outputs, condition);
                if (index < 0 || profile->outputs.data[index].value.kind != TYPE_BOOL ||
                    !profile->outputs.data[index].value.number) continue;
                message = format("%s is required when %s is true", key, condition);
            }
            report(&profile->diagnostics, (Origin){profile->root, 0}, "E_REQUIRED", message);
        }
    }
}

static void check_fixed(Profile *profile, Profiles earlier) {
    Strings keys = output_keys(profile->outputs);
    for (size_t i = 0; i < keys.len; ++i) {
        OutputKey output = profile->outputs.data[output_index(profile->outputs, keys.data[i])];
        if (!output.spec || !output.spec->fixed) continue;
        for (size_t j = 0; j < earlier.len; ++j) {
            Profile *reference = earlier.data[j];
            int index = output_index(reference->outputs, output.key);
            if (index < 0) continue;
            if (strcmp(output.notation, reference->outputs.data[index].notation)) {
                report(&profile->diagnostics, output.definition.origin, "E_FIXED",
                       format("%s: value differs from profile %s", output.key, reference->name));
                remove_output(profile, output.key);
            }
            break;
        }
    }
}

static void process(Profile *profile, const Schema *schema, Library *library, Profiles earlier) {
    Strings chain = {0};
    PUSH(chain, profile->root);
    apply_document(profile, library, profile->root, chain);
    for (size_t i = 0; i < profile->overrides.len; ++i) {
        char *override = profile->overrides.data[i], *equal = strchr(override, '=');
        define(profile, slice(override, 0, (size_t)(equal - override)), equal + 1, (Origin){"manifest", profile->line});
    }
    inherit_sections(profile);
    resolve_aliases(profile, schema);
    Strings sections = fill_defaults(profile, schema);
    check_types(profile, schema);
    check_order(profile);
    check_required(profile, schema, sections);
    check_fixed(profile, earlier);
    sort_diagnostics(profile);
    for (size_t i = 0; i < profile->outputs.len; ++i) {
        char *document = profile->outputs.data[i].definition.origin.document;
        if (!strcmp(document, "manifest")) ++profile->manifest_keys;
        else if (!strcmp(document, "schema")) ++profile->default_keys;
        else ++profile->document_keys;
    }
    profile->dropped = profile->configured_count - profile->outputs.len;
}

static ProfileDiff difference(Profile *first, Profile *second) {
    ProfileDiff diff = {.first = first->name, .second = second->name};
    Strings keys = output_keys(first->outputs);
    for (size_t i = 0; i < second->outputs.len; ++i)
        if (!strings_contain(keys, second->outputs.data[i].key)) PUSH(keys, second->outputs.data[i].key);
    if (keys.len > 1) qsort(keys.data, keys.len, sizeof *keys.data, key_comparator);
    for (size_t i = 0; i < keys.len; ++i) {
        int before_index = output_index(first->outputs, keys.data[i]);
        int after_index = output_index(second->outputs, keys.data[i]);
        OutputKey *before = before_index < 0 ? NULL : &first->outputs.data[before_index];
        OutputKey *after = after_index < 0 ? NULL : &second->outputs.data[after_index];
        char mark;
        if (!before) { mark = '+'; ++diff.added; }
        else if (!after) { mark = '-'; ++diff.removed; }
        else if (strcmp(before->notation, after->notation)) { mark = '~'; ++diff.changed; }
        else continue;
        DiffEntry entry = {mark, keys.data[i], before, after};
        PUSH(diff.entries, entry);
    }
    return diff;
}

int main(void) {
    Schema schema = load_schema("input/schema.txt");
    char *manifest = read_file("input/manifest.txt");
    if (!manifest) return EXIT_FAILURE;
    Strings lines = file_lines(manifest);
    Profiles profiles = {0};
    Library library = {0};
    for (size_t i = 0; i < lines.len; ++i) {
        Strings words = split(lines.data[i], ' ');
        Profile *profile = checked_realloc(NULL, sizeof *profile);
        *profile = (Profile){.name = words.data[0], .root = words.data[1], .line = (int)i + 1};
        for (size_t j = 2; j < words.len; ++j) PUSH(profile->overrides, words.data[j]);
        process(profile, &schema, &library, profiles);
        PUSH(profiles, profile);
    }
    Diffs diffs = {0};
    for (size_t i = 1; i < profiles.len; ++i) PUSH(diffs, difference(profiles.data[i - 1], profiles.data[i]));
    write_outputs(profiles, diffs);
    return EXIT_SUCCESS;
}
