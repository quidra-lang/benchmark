#include "preprocessor.h"
bool equal(const char *left, const char *right) {
    return left && right && strcmp(left, right) == 0;
}
bool word_in(const char *words, const char *word) {
    if (!word)
        return false;
    size_t n = strlen(word);
    for (const char *p = words; *p;) {
        const char *end = strchr(p, ' ');
        if (!end)
            end = p + strlen(p);
        if ((size_t)(end - p) == n && strncmp(p, word, n) == 0)
            return true;
        p = *end ? end + 1 : end;
    }
    return false;
}
bool string_member(StringList list, const char *name) {
    for (int i = 0; i < list.count; ++i)
        if (equal(list.items[i], name))
            return true;
    return false;
}
void string_insert(StringList *list, const char *name) {
    if (!string_member(*list, name))
        PUSH(*list, (char *)name);
}
StringList names_union(StringList left, StringList right) {
    StringList result = {0};
    for (int i = 0; i < left.count; ++i)
        string_insert(&result, left.items[i]);
    for (int i = 0; i < right.count; ++i)
        string_insert(&result, right.items[i]);
    return result;
}
StringList names_intersection(StringList left, StringList right) {
    StringList result = {0};
    for (int i = 0; i < left.count; ++i)
        if (string_member(right, left.items[i]))
            string_insert(&result, left.items[i]);
    return result;
}
static bool identifier_start(char c) {
    return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}
static bool digit(char c) { return c >= '0' && c <= '9'; }
static ReadToken read_token_length(const char *source, size_t n, size_t index, bool header) {
    char c = source[index];
    if (header && c == '<') {
        const char *end = strchr(source + index + 1, '>');
        const char *newline = strchr(source + index + 1, '\n');
        if (end && (!newline || end < newline))
            return (ReadToken){"header",
                               ml_text(source + index, (size_t)(end - source) + 1 - index),
                               (size_t)(end - source) + 1};
    }
    if (identifier_start(c)) {
        size_t end = index + 1;
        while (end < n && (identifier_start(source[end]) || digit(source[end])))
            ++end;
        return (ReadToken){"identifier", ml_text(source + index, end - index), end};
    }
    if (digit(c) || (c == '.' && index + 1 < n && digit(source[index + 1]))) {
        size_t end = index + 1;
        while (end < n) {
            if (strchr("eEpP", source[end]) && end + 1 < n &&
                (source[end + 1] == '+' || source[end + 1] == '-'))
                end += 2;
            else if (identifier_start(source[end]) || digit(source[end]) || source[end] == '.')
                ++end;
            else
                break;
        }
        return (ReadToken){"number", ml_text(source + index, end - index), end};
    }
    if (c == '\'' || c == '"') {
        size_t end = index + 1;
        while (end < n && source[end] != '\n') {
            if (source[end] == c)
                return (ReadToken){c == '\'' ? "character" : "string",
                                   ml_text(source + index, end + 1 - index), end + 1};
            if (source[end] == '\\' && end + 1 < n && source[end + 1] != '\n')
                end += 2;
            else
                ++end;
        }
    }
    const char *punctuators[] = {
        "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=",
        "&&",  "||",  "*=",  "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##", "[",
        "]",   "(",   ")",   "{",  "}",  ".",  "&",  "*",  "+",  "-",  "~",  "!",
        "/",   "%",   "<",   ">",  "^",  "|",  "?",  ":",  ";",  "=",  ",",  "#"};
    for (size_t i = 0; i < sizeof(punctuators) / sizeof(*punctuators); ++i)
        if (strncmp(source + index, punctuators[i], strlen(punctuators[i])) == 0)
            return (ReadToken){"punctuator", (char *)punctuators[i],
                               index + strlen(punctuators[i])};
    return (ReadToken){"other", ml_text(source + index, 1), index + 1};
}
ReadToken read_token(const char *source, size_t index, bool header) {
    return read_token_length(source, strlen(source), index, header);
}
static LogicalLines scan(const char *source, const int *positions, int start) {
    LogicalLines result = {0};
    Tokens tokens = {0};
    bool spaced = true;
    size_t index = 0, n = strlen(source);
    while (index < n) {
        if (source[index] == ' ') {
            spaced = true;
            ++index;
        } else if (source[index] == '\n') {
            int end = positions[index++];
            LogicalLine line = {tokens, start, end};
            PUSH(result, line);
            tokens = (Tokens){0};
            start = end + 1;
            spaced = true;
        } else if (strncmp(source + index, "/*", 2) == 0) {
            const char *end = strstr(source + index + 2, "*/");
            index = end ? (size_t)(end - source) + 2 : n;
            spaced = true;
        } else if (strncmp(source + index, "//", 2) == 0) {
            const char *end = strchr(source + index, '\n');
            index = end ? (size_t)(end - source) : n;
            spaced = true;
        } else {
            bool header = tokens.count == 2 && equal(tokens.items[0].spelling, "#") &&
                          equal(tokens.items[1].spelling, "include");
            ReadToken read = read_token_length(source, n, index, header);
            Token token = {read.kind, read.spelling, positions[index], spaced, {0}};
            PUSH(tokens, token);
            index = read.end;
            spaced = false;
        }
    }
    if (tokens.count) {
        LogicalLine line = {tokens, start, positions[n - 1]};
        PUSH(result, line);
    }
    return result;
}
LogicalLines lex_source(const char *source) {
    size_t n = strlen(source);
    Text characters = {0};
    int *positions = ml_alloc((n + 1) * sizeof(*positions));
    int line = 1, count = 0;
    for (size_t i = 0; i < n;) {
        if (i + 1 < n && source[i] == '\\' && source[i + 1] == '\n') {
            i += 2;
            ++line;
            continue;
        }
        char c = source[i++];
        text_char(&characters, c);
        positions[count++] = line;
        if (c == '\n')
            ++line;
    }
    return scan(text_value(&characters), positions, 1);
}
Tokens lex_definition(const char *text, int line) {
    char *source = ml_format("%s\n", text);
    size_t n = strlen(source);
    int *positions = ml_alloc(n * sizeof(*positions));
    for (size_t i = 0; i < n; ++i)
        positions[i] = line;
    LogicalLines lines = scan(source, positions, line);
    Tokens result = {0};
    for (int i = 0; i < lines.count; ++i)
        for (int j = 0; j < lines.items[i].tokens.count; ++j)
            PUSH(result, lines.items[i].tokens.items[j]);
    return result;
}
Tokens copy_tokens(Tokens tokens) {
    Tokens result = {0};
    for (int i = 0; i < tokens.count; ++i)
        PUSH(result, tokens.items[i]);
    return result;
}
char *render(Tokens tokens) {
    Text result = {0};
    for (int i = 0; i < tokens.count; ++i) {
        if (i && tokens.items[i].space)
            text_char(&result, ' ');
        text_add(&result, tokens.items[i].spelling);
    }
    return text_value(&result);
}
const char *single_token(const char *source) {
    if (!*source || strncmp(source, "//", 2) == 0 || strncmp(source, "/*", 2) == 0)
        return NULL;
    ReadToken token = read_token(source, 0, false);
    return token.end == strlen(source) ? token.kind : NULL;
}
