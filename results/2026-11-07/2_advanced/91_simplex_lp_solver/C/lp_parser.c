#include "solver.h"
void *allocate(size_t size) {
    void *data = calloc(1, size ? size : 1);
    if (!data)
        exit(EXIT_FAILURE);
    return data;
}
void *resize(void *data, size_t size) {
    void *next = realloc(data, size ? size : 1);
    if (!next)
        exit(EXIT_FAILURE);
    return next;
}
char *copy_text(const char *text) {
    size_t size = strlen(text) + 1;
    char *out = allocate(size);
    memcpy(out, text, size);
    return out;
}
char *format_text(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *out = allocate((size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, format, args);
    va_end(args);
    return out;
}
void lines_push(TextLines *lines, char *text) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof *lines->data);
    }
    lines->data[lines->count++] = text;
}
void lines_add(TextLines *lines, const char *text) { lines_push(lines, copy_text(text)); }
void lines_append(TextLines *lines, const TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_add(lines, from->data[i]);
}
void lines_free(TextLines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (TextLines){0};
}
TextLines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    if (!input)
        exit(EXIT_FAILURE);
    TextLines out = {0};
    char *line = NULL;
    size_t length = 0, capacity = 0;
    int c;
    while ((c = fgetc(input)) != EOF) {
        if (c == '\n') {
            if (!line)
                line = allocate(1);
            line[length] = 0;
            lines_push(&out, line);
            line = NULL;
            length = capacity = 0;
        } else {
            if (length + 1 >= capacity) {
                capacity = capacity ? capacity * 2 : 128;
                line = resize(line, capacity);
            }
            line[length++] = (char)c;
        }
    }
    if (ferror(input))
        exit(EXIT_FAILURE);
    if (length) {
        line[length] = 0;
        lines_push(&out, line);
    } else
        free(line);
    fclose(input);
    return out;
}
char *join_texts(const TextLines *texts, const char *separator) {
    size_t size = 1, separator_size = strlen(separator);
    for (int i = 0; i < texts->count; ++i)
        size += strlen(texts->data[i]) + (i ? separator_size : 0);
    char *out = allocate(size), *at = out;
    for (int i = 0; i < texts->count; ++i) {
        if (i) {
            memcpy(at, separator, separator_size);
            at += separator_size;
        }
        size_t length = strlen(texts->data[i]);
        memcpy(at, texts->data[i], length);
        at += length;
    }
    *at = 0;
    return out;
}

TextLines split_words(const char *text) {
    TextLines out = {0};
    const char *at = text;
    while (*at) {
        while (*at == ' ')
            ++at;
        if (!*at)
            break;
        const char *start = at;
        while (*at && *at != ' ')
            ++at;
        size_t length = (size_t)(at - start);
        char *word = allocate(length + 1);
        memcpy(word, start, length);
        word[length] = 0;
        lines_push(&out, word);
    }
    return out;
}
static bool word_in(const char *words, const char *word) {
    size_t length = strlen(word);
    const char *at = words;
    while (*at) {
        while (*at == ' ')
            ++at;
        const char *start = at;
        while (*at && *at != ' ')
            ++at;
        if ((size_t)(at - start) == length && !memcmp(start, word, length))
            return true;
    }
    return false;
}
static bool is_name(const char *word) {
    if (*word < 'a' || *word > 'z' || word_in("bounds integer binary free inf", word))
        return false;
    for (const char *at = word + 1; *at; ++at)
        if (!((*at >= 'a' && *at <= 'z') || (*at >= '0' && *at <= '9') || *at == '_'))
            return false;
    return true;
}
static void term_push(Terms *terms, Term term) {
    if (terms->count == terms->capacity) {
        terms->capacity = terms->capacity ? terms->capacity * 2 : 8;
        terms->data = resize(terms->data, (size_t)terms->capacity * sizeof *terms->data);
    }
    terms->data[terms->count++] = term;
}
static bool expression(const TextLines *items, int first, int end, Terms *terms) {
    Terms out = {0};
    int sign = 1;
    if (first < end && !strcmp(items->data[first], "-")) {
        ++first;
        sign = -1;
    }
    while (first < end) {
        Rational coefficient;
        const char *name;
        if (read_number(items->data[first], false, &coefficient)) {
            if (first + 1 >= end || !is_name(items->data[first + 1]))
                break;
            name = items->data[first + 1];
            first += 2;
        } else if (is_name(items->data[first])) {
            name = items->data[first++];
            coefficient = integer(1);
        } else
            break;
        Term term = {0};
        strcpy(term.name, name);
        term.coefficient = rat_mul(coefficient, integer(sign));
        term_push(&out, term);
        if (first == end) {
            *terms = out;
            return true;
        }
        if (strcmp(items->data[first], "+") && strcmp(items->data[first], "-"))
            break;
        sign = !strcmp(items->data[first++], "-") ? -1 : 1;
    }
    free(out.data);
    return false;
}
static bool named_expression(const TextLines *items, int end, char *name, Terms *terms) {
    if (end < 2)
        return false;
    const char *first = items->data[0];
    size_t length = strlen(first);
    if (!length || first[length - 1] != ':')
        return false;
    char *label = copy_text(first);
    label[length - 1] = 0;
    bool valid = is_name(label);
    if (valid)
        strcpy(name, label);
    free(label);
    return valid && expression(items, 1, end, terms);
}
static bool parse_constraint(const TextLines *items, int line, RawConstraint *out) {
    int count = items->count;
    if (count < 4 || !word_in("<= >= =", items->data[count - 2]) ||
        !read_number(items->data[count - 1], true, &out->rhs))
        return false;
    if (!named_expression(items, count - 2, out->name, &out->terms))
        return false;
    out->line = line;
    out->comparison = !strcmp(items->data[count - 2], "<=")   ? COMP_LE
                      : !strcmp(items->data[count - 2], ">=") ? COMP_GE
                                                              : COMP_EQ;
    return true;
}
static bool parse_bound(const TextLines *items, int line, BoundLine *out) {
    int count = items->count;
    *out = (BoundLine){0};
    out->line = line;
    if (count == 2 && is_name(items->data[0]) && !strcmp(items->data[1], "free")) {
        strcpy(out->name, items->data[0]);
        out->kind = BOUND_BOTH;
        return true;
    }
    if (count == 3 && is_name(items->data[0])) {
        Rational value = {0};
        bool valid = read_number(items->data[2], true, &value);
        strcpy(out->name, items->data[0]);
        Bound bound = {valid, value};
        if (!strcmp(items->data[1], ">=") && (valid || !strcmp(items->data[2], "-inf"))) {
            out->kind = BOUND_LOWER;
            out->lower = bound;
            return true;
        }
        if (!strcmp(items->data[1], "<=") && (valid || !strcmp(items->data[2], "inf"))) {
            out->kind = BOUND_UPPER;
            out->upper = bound;
            return true;
        }
        if (!strcmp(items->data[1], "=") && valid) {
            out->kind = BOUND_BOTH;
            out->lower = out->upper = bound;
            return true;
        }
    }
    if (count == 5 && !strcmp(items->data[1], "<=") && !strcmp(items->data[3], "<=") &&
        is_name(items->data[2])) {
        Rational lower = {0}, upper = {0};
        bool low = read_number(items->data[0], true, &lower),
             high = read_number(items->data[4], true, &upper);
        if ((low || !strcmp(items->data[0], "-inf")) && (high || !strcmp(items->data[4], "inf"))) {
            strcpy(out->name, items->data[2]);
            out->kind = BOUND_BOTH;
            out->lower = (Bound){low, lower};
            out->upper = (Bound){high, upper};
            return true;
        }
    }
    return false;
}
typedef struct {
    int line;
    const char *text;
} Record;
static void constraint_push(RawModel *model, RawConstraint row) {
    if (model->constraint_count == model->constraint_capacity) {
        model->constraint_capacity =
            model->constraint_capacity ? model->constraint_capacity * 2 : 8;
        model->constraints = resize(model->constraints, (size_t)model->constraint_capacity *
                                                            sizeof *model->constraints);
    }
    model->constraints[model->constraint_count++] = row;
}
static void bound_push(RawModel *model, BoundLine bound) {
    if (model->bound_count == model->bound_capacity) {
        model->bound_capacity = model->bound_capacity ? model->bound_capacity * 2 : 8;
        model->bounds =
            resize(model->bounds, (size_t)model->bound_capacity * sizeof *model->bounds);
    }
    model->bounds[model->bound_count++] = bound;
}
static void declaration_push(RawModel *model, Declaration declaration, bool binary) {
    Declaration **data = binary ? &model->binaries : &model->integers;
    int *count = binary ? &model->binary_count : &model->integer_count,
        *capacity = binary ? &model->binary_capacity : &model->integer_capacity;
    if (*count == *capacity) {
        *capacity = *capacity ? *capacity * 2 : 8;
        *data = resize(*data, (size_t)*capacity * sizeof **data);
    }
    (*data)[(*count)++] = declaration;
}
static RawModel parse_block(const char *name, const Record *records, int count, int end_line) {
    RawModel out = {0};
    strcpy(out.name, name);
    char state = 'A';
    for (int i = 0; i < count; ++i) {
        const Record *record = &records[i];
        TextLines items = split_words(record->text);
        bool accepted = false;
        if (state == 'A') {
            if (!strcmp(record->text, "maximize") || !strcmp(record->text, "minimize")) {
                out.maximize = !strcmp(record->text, "maximize");
                state = 'B';
                accepted = true;
            }
        } else if (state == 'B') {
            char label[17];
            if (named_expression(&items, items.count, label, &out.objective)) {
                state = 'C';
                accepted = true;
            }
        } else if (state == 'C') {
            if (!strcmp(record->text, "subject to")) {
                state = 'D';
                accepted = true;
            }
        } else if (state == 'D' || state == 'E') {
            if (state == 'E' && word_in("bounds integer binary", record->text)) {
                state = !strcmp(record->text, "bounds")    ? 'F'
                        : !strcmp(record->text, "integer") ? 'G'
                                                           : 'H';
                accepted = true;
            } else {
                RawConstraint row = {0};
                if (parse_constraint(&items, record->line, &row)) {
                    constraint_push(&out, row);
                    state = 'E';
                    accepted = true;
                }
            }
        } else if (state == 'F') {
            if (!strcmp(record->text, "integer") || !strcmp(record->text, "binary")) {
                state = !strcmp(record->text, "integer") ? 'G' : 'H';
                accepted = true;
            } else {
                BoundLine bound;
                if (parse_bound(&items, record->line, &bound)) {
                    bound_push(&out, bound);
                    accepted = true;
                }
            }
        } else {
            if (state == 'G' && !strcmp(record->text, "binary")) {
                state = 'H';
                accepted = true;
            } else {
                bool valid = true;
                for (int j = 0; j < items.count; ++j)
                    if (!is_name(items.data[j]))
                        valid = false;
                if (valid) {
                    declaration_push(&out, (Declaration){record->line, items}, state == 'H');
                    items = (TextLines){0};
                    accepted = true;
                }
            }
        }
        lines_free(&items);
        if (!accepted) {
            out.error = (ModelError){record->line, copy_text("syntax error")};
            return out;
        }
    }
    if (state <= 'D')
        out.error = (ModelError){end_line, copy_text("syntax error")};
    return out;
}
RawModel *read_models(int *count) {
    RawModel *out = allocate(30 * sizeof *out);
    *count = 0;
    TextLines lines = read_lines("input/models.lp");
    char name[17] = {0};
    Record *records = allocate((size_t)lines.count * sizeof *records);
    int record_count = 0;
    for (int i = 0; i < lines.count; ++i) {
        const char *line = lines.data[i];
        if (!*line || *line == '#')
            continue;
        if (!*name) {
            strcpy(name, line + 6);
            record_count = 0;
        } else if (!strcmp(line, "end")) {
            out[(*count)++] = parse_block(name, records, record_count, i + 1);
            *name = 0;
        } else
            records[record_count++] = (Record){i + 1, line};
    }
    free(records);
    lines_free(&lines);
    return out;
}
Settings read_settings(void) {
    Settings out = {0};
    TextLines lines = read_lines("input/params.txt");
    out.logs = allocate((size_t)lines.count * sizeof *out.logs);
    out.limits = allocate((size_t)lines.count * sizeof *out.limits);
    for (int i = 0; i < lines.count; ++i) {
        TextLines words = split_words(lines.data[i]);
        if (!i)
            out.level = atoi(words.data[1]);
        else if (i == 1)
            out.limit = atoi(words.data[1]);
        else {
            Override override = {0};
            strcpy(override.name, words.data[1]);
            override.value = atoi(words.data[2]);
            if (!strcmp(words.data[0], "log"))
                out.logs[out.log_count++] = override;
            else
                out.limits[out.limit_count++] = override;
        }
        lines_free(&words);
    }
    lines_free(&lines);
    return out;
}
void raw_model_free(RawModel *model) {
    free(model->objective.data);
    for (int i = 0; i < model->constraint_count; ++i)
        free(model->constraints[i].terms.data);
    free(model->constraints);
    free(model->bounds);
    for (int i = 0; i < model->integer_count; ++i)
        lines_free(&model->integers[i].names);
    for (int i = 0; i < model->binary_count; ++i)
        lines_free(&model->binaries[i].names);
    free(model->integers);
    free(model->binaries);
    free(model->error.message);
}
