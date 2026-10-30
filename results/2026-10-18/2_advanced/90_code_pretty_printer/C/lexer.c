#include "formatter.h"
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

bool word_in(const char *words, const char *word) {
    size_t size = strlen(word);
    const char *at = words;
    while (*at) {
        while (*at == ' ')
            ++at;
        const char *start = at;
        while (*at && *at != ' ')
            ++at;
        if ((size_t)(at - start) == size && !memcmp(start, word, size))
            return true;
    }
    return false;
}
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static char *substring(const char *text, int first, int end) {
    char *out = allocate((size_t)(end - first) + 1);
    memcpy(out, text + first, (size_t)(end - first));
    out[end - first] = 0;
    return out;
}
void comments_push(Comments *comments, Comment *comment) {
    if (comments->count == comments->capacity) {
        comments->capacity = comments->capacity ? comments->capacity * 2 : 8;
        comments->data =
            resize(comments->data, (size_t)comments->capacity * sizeof *comments->data);
    }
    comments->data[comments->count++] = comment;
}
void tokens_push(Tokens *tokens, Token *token) {
    if (tokens->count == tokens->capacity) {
        tokens->capacity = tokens->capacity ? tokens->capacity * 2 : 32;
        tokens->data = resize(tokens->data, (size_t)tokens->capacity * sizeof *tokens->data);
    }
    tokens->data[tokens->count++] = token;
}
static void item_push(Lexed *lexed, Lexeme item) {
    if (lexed->item_count == lexed->item_capacity) {
        lexed->item_capacity = lexed->item_capacity ? lexed->item_capacity * 2 : 64;
        lexed->items = resize(lexed->items, (size_t)lexed->item_capacity * sizeof *lexed->items);
    }
    lexed->items[lexed->item_count++] = item;
}
static void add_token(Lexed *lexed, char *value, TokenKind kind, Position position, int blank) {
    Token *token = allocate(sizeof *token);
    token->value = value;
    token->kind = kind;
    token->position = position;
    token->blank = blank;
    token->index = lexed->tokens.count;
    tokens_push(&lexed->tokens, token);
    item_push(lexed, (Lexeme){token, NULL});
}
static void add_comment(Lexed *lexed, char *value, bool line, Position position, int blank) {
    Comment *comment = allocate(sizeof *comment);
    comment->value = value;
    comment->line = line;
    comment->position = position;
    comment->blank = blank;
    comments_push(&lexed->comments, comment);
    item_push(lexed, (Lexeme){NULL, comment});
}
Lexed lex(const TextLines *source) {
    Lexed out = {0};
    int previous_line = 0;
    for (int row = 0; row < source->count; ++row) {
        const char *line = source->data[row];
        int length = (int)strlen(line);
        for (int at = 0; at < length;) {
            char c = line[at];
            if (c == ' ') {
                ++at;
                continue;
            }
            Position position = {row + 1, at + 1};
            int blank = row > previous_line ? row - previous_line : 0;
            if (at + 1 < length && line[at] == '/' && line[at + 1] == '/') {
                add_comment(&out, trim_right(copy_text(line + at)), true, position, blank);
                previous_line = row + 1;
                break;
            }
            if (at + 1 < length && line[at] == '/' && line[at + 1] == '*') {
                const char *closing = strstr(line + at + 2, "*/");
                if (!closing) {
                    out.error = (FileError){position, copy_text("unterminated comment")};
                    return out;
                }
                int end = (int)(closing - line) + 2;
                add_comment(&out, substring(line, at, end), false, position, blank);
                at = end;
                previous_line = row + 1;
                continue;
            }
            if (letter(c)) {
                int end = at + 1;
                while (end < length && (letter(line[end]) || digit(line[end])))
                    ++end;
                char *value = substring(line, at, end);
                TokenKind kind =
                    word_in(
                        "int float bool string void if else while for return break continue true false switch case default",
                        value)
                        ? TOKEN_KEYWORD
                        : TOKEN_IDENTIFIER;
                add_token(&out, value, kind, position, blank);
                at = end;
                previous_line = row + 1;
                continue;
            }
            if (digit(c)) {
                int end = at + 1;
                while (end < length && digit(line[end]))
                    ++end;
                if (end + 1 < length && line[end] == '.' && digit(line[end + 1])) {
                    end += 2;
                    while (end < length && digit(line[end]))
                        ++end;
                }
                add_token(&out, substring(line, at, end), TOKEN_NUMBER, position, blank);
                at = end;
                previous_line = row + 1;
                continue;
            }
            if (c == '"') {
                int end = at + 1;
                while (end < length && line[end] != '"')
                    end += line[end] == '\\' ? 2 : 1;
                if (end >= length) {
                    out.error = (FileError){position, copy_text("unterminated string")};
                    return out;
                }
                ++end;
                add_token(&out, substring(line, at, end), TOKEN_STRING, position, blank);
                at = end;
                previous_line = row + 1;
                continue;
            }
            if (at + 1 < length) {
                char pair[3] = {line[at], line[at + 1], 0};
                if (word_in("<= >= == != && || += -= *= /= %=", pair)) {
                    add_token(&out, copy_text(pair), TOKEN_SYMBOL, position, blank);
                    at += 2;
                    previous_line = row + 1;
                    continue;
                }
            }
            if (strchr("+-*/%<>=!()[]{},;.?:", c)) {
                add_token(&out, substring(line, at, at + 1), TOKEN_SYMBOL, position, blank);
                ++at;
                previous_line = row + 1;
                continue;
            }
            out.error = (FileError){position, format_text("unexpected character '%c'", c)};
            return out;
        }
    }
    Token *end = allocate(sizeof *end);
    end->value = copy_text("");
    end->kind = TOKEN_END;
    end->position = (Position){source->count + 1, 1};
    end->index = out.tokens.count;
    tokens_push(&out.tokens, end);
    return out;
}
void lex_free(Lexed *lexed) {
    for (int i = 0; i < lexed->tokens.count; ++i) {
        Token *token = lexed->tokens.data[i];
        free(token->value);
        free(token->leading.data);
        free(token->trailing.data);
        free(token);
    }
    for (int i = 0; i < lexed->comments.count; ++i) {
        free(lexed->comments.data[i]->value);
        free(lexed->comments.data[i]);
    }
    free(lexed->tokens.data);
    free(lexed->comments.data);
    free(lexed->items);
    free(lexed->error.message);
}
