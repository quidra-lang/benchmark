#include "formula.h"
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
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = value;
}
void int_free(IntList *list) {
    free(list->data);
    *list = (IntList){0};
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

char *repeated(char character, int count) {
    char *out = allocate((size_t)count + 1);
    memset(out, character, (size_t)count);
    out[count] = 0;
    return out;
}
char *trim_right(char *text) {
    size_t length = strlen(text);
    while (length && text[length - 1] == ' ')
        --length;
    text[length] = 0;
    return text;
}
bool contains_word(const char *words, const char *value) {
    size_t length = strlen(value);
    const char *at = words;
    while (*at) {
        while (*at == ' ')
            ++at;
        const char *start = at;
        while (*at && *at != ' ')
            ++at;
        if ((size_t)(at - start) == length && !memcmp(start, value, length))
            return true;
    }
    return false;
}
bool greek_name(const char *name) {
    return contains_word(
        "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega",
        name);
}
bool command_name(const char *name) {
    if (strlen(name) < 2)
        return false;
    char *command = format_text("\\%s", name);
    bool found = symbol_info(command) != NULL;
    free(command);
    return found;
}
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static char *substring(const char *text, int first, int end) {
    char *out = allocate((size_t)(end - first) + 1);
    memcpy(out, text + first, (size_t)(end - first));
    out[end - first] = 0;
    return out;
}
static void token_push(TokenList *tokens, Kind kind, char *value, int column) {
    if (tokens->count == tokens->capacity) {
        tokens->capacity = tokens->capacity ? tokens->capacity * 2 : 32;
        tokens->data = resize(tokens->data, (size_t)tokens->capacity * sizeof *tokens->data);
    }
    tokens->data[tokens->count++] = (Token){kind, value, column};
}
TokenList tokenize(const char *line, Issue *error) {
    TokenList out = {0};
    int length = (int)strlen(line);
    for (int at = 0; at < length;) {
        char c = line[at];
        int column = at + 1;
        if (c == ' ') {
            ++at;
            continue;
        }
        if (letter(c) || digit(c)) {
            bool identifier = letter(c);
            int end = at + 1;
            while (end < length && (identifier ? letter(line[end]) : digit(line[end])))
                ++end;
            if (!identifier && end + 1 < length && line[end] == '.' && digit(line[end + 1])) {
                end += 2;
                while (end < length && digit(line[end]))
                    ++end;
            }
            token_push(&out, identifier ? K_IDENTIFIER : K_NUMBER, substring(line, at, end),
                       column);
            at = end;
            continue;
        }
        if (strchr("+-*/=<>:()[],;.!|'", c)) {
            token_push(&out, K_SYMBOL, substring(line, at, at + 1), column);
            ++at;
            continue;
        }
        if (strchr("{}^_&", c)) {
            Kind kind = c == '{'   ? K_OPEN_BRACE
                        : c == '}' ? K_CLOSE_BRACE
                        : c == '^' ? K_SUP
                        : c == '_' ? K_SUB
                                   : K_AMP;
            token_push(&out, kind, substring(line, at, at + 1), column);
            ++at;
            continue;
        }
        if (c != '\\') {
            *error = (Issue){column, format_text("invalid character %c", c)};
            return out;
        }
        if (at + 1 < length && line[at + 1] == '\\') {
            token_push(&out, K_NEWLINE, copy_text(""), column);
            at += 2;
            continue;
        }
        if (at + 1 < length && strchr("{},", line[at + 1])) {
            token_push(&out, K_COMMAND, substring(line, at, at + 2), column);
            at += 2;
            continue;
        }
        int end = at + 1;
        while (end < length && letter(line[end]))
            ++end;
        if (end == at + 1) {
            *error = (Issue){column, copy_text("invalid command")};
            return out;
        }
        char *name = substring(line, at + 1, end);
        at = end;
        if (contains_word("text begin end tag label eqref", name)) {
            while (at < length && line[at] == ' ')
                ++at;
            if (at == length || line[at] != '{') {
                *error = (Issue){at + 1, copy_text("expected {")};
                free(name);
                return out;
            }
            const char *closing = strchr(line + at + 1, '}');
            if (!closing) {
                *error = (Issue){column, copy_text("unterminated argument")};
                free(name);
                return out;
            }
            end = (int)(closing - line);
            char *value = substring(line, at + 1, end);
            at = end + 1;
            if ((!strcmp(name, "begin") || !strcmp(name, "end")) &&
                !contains_word("matrix pmatrix bmatrix vmatrix cases", value)) {
                *error = (Issue){column, format_text("unknown environment \"%s\"", value)};
                free(name);
                free(value);
                return out;
            }
            Kind kind = !strcmp(name, "text")    ? K_TEXT
                        : !strcmp(name, "begin") ? K_BEGIN
                        : !strcmp(name, "end")   ? K_END
                        : !strcmp(name, "tag")   ? K_TAG
                        : !strcmp(name, "label") ? K_LABEL
                                                 : K_EQREF;
            token_push(&out, kind, value, column);
            free(name);
            continue;
        }
        char *command = format_text("\\%s", name);
        if (symbol_info(command)) {
            token_push(&out, K_COMMAND, command, column);
            free(name);
            continue;
        }
        free(command);
        if (contains_word("overline hat vec dot tilde overbrace underbrace", name)) {
            token_push(&out, K_ACCENT, name, column);
            continue;
        }
        if (!contains_word("frac binom overset underset sqrt left right", name)) {
            *error = (Issue){column, format_text("unknown command \\%s", name)};
            free(name);
            return out;
        }
        Kind kind = !strcmp(name, "frac")       ? K_FRAC
                    : !strcmp(name, "binom")    ? K_BINOM
                    : !strcmp(name, "overset")  ? K_OVERSET
                    : !strcmp(name, "underset") ? K_UNDERSET
                    : !strcmp(name, "sqrt")     ? K_SQRT
                    : !strcmp(name, "left")     ? K_LEFT
                                                : K_RIGHT;
        token_push(&out, kind, copy_text(""), column);
        free(name);
    }
    return out;
}
void tokens_free(TokenList *tokens) {
    for (int i = 0; i < tokens->count; ++i)
        free(tokens->data[i].value);
    free(tokens->data);
}
