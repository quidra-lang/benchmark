#include "ml.h"
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
bool token_name(Token token) {
    return equal(token.kind, "identifier") && !equal(token.spelling, "_");
}
static bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static void advance(const char *source, size_t *at, int *line, int *column) {
    if (source[(*at)++] == '\n') {
        ++*line;
        *column = 1;
    } else
        ++*column;
}
TokenList lex(const char *file, StringList lines) {
    Text joined = {0};
    for (int i = 0; i < lines.count; ++i) {
        text_add(&joined, lines.items[i]);
        text_char(&joined, '\n');
    }
    const char *source = text_value(&joined);
    size_t length = strlen(source), at = 0;
    int line = 1, column = 1;
    TokenList result = {0};
    const char *symbols[] = {";;", "->", "::", "||", "&&", "<=", ">=", "<>", ":", ";", "=", "<",
                             ">",  "+",  "-",  "*",  "/",  "^",  "(",  ")",  "[", "]", ",", "|"};
    while (at < length) {
        if (source[at] == ' ' || source[at] == '\n') {
            advance(source, &at, &line, &column);
            continue;
        }
        size_t start = at;
        Token token = {0};
        token.position = (Position){file, line, column};
        if (strncmp(source + at, "(*", 2) == 0) {
            const char *end = strstr(source + at + 2, "*)");
            if (!end) {
                token.kind = "invalid";
                token.value = "unterminated comment";
                PUSH(result, token);
                break;
            }
            size_t stop = (size_t)(end - source) + 2;
            while (at < stop)
                advance(source, &at, &line, &column);
            continue;
        }
        if (digit(source[at])) {
            while (at < length && digit(source[at]))
                advance(source, &at, &line, &column);
            token.spelling = ml_text(source + start, at - start);
            const char *canonical = token.spelling;
            while (canonical[0] == '0' && canonical[1])
                ++canonical;
            if (strlen(canonical) > 10 ||
                (strlen(canonical) == 10 && strcmp(canonical, "2147483647") > 0)) {
                token.kind = "invalid";
                token.value = "integer literal too large";
            } else {
                token.kind = "integer";
                token.integer = strtoll(canonical, NULL, 10);
            }
        } else if (letter(source[at]) || source[at] == '_') {
            while (at < length && (letter(source[at]) || digit(source[at]) || source[at] == '_' ||
                                   source[at] == '\''))
                advance(source, &at, &line, &column);
            token.spelling = ml_text(source + start, at - start);
            token.kind = word_in("let rec and in fun if then else match with true false mod val",
                                 token.spelling)
                             ? token.spelling
                             : "identifier";
        } else if (source[at] == '\'' && at + 1 < length && source[at + 1] >= 'a' &&
                   source[at + 1] <= 'z') {
            advance(source, &at, &line, &column);
            while (at < length && (letter(source[at]) || digit(source[at]) || source[at] == '_'))
                advance(source, &at, &line, &column);
            token.kind = "type_variable";
            token.spelling = ml_text(source + start, at - start);
        } else if (source[at] == '"') {
            advance(source, &at, &line, &column);
            bool bad = false;
            Text value = {0};
            while (at < length && source[at] != '\n' && source[at] != '"') {
                char c = source[at];
                advance(source, &at, &line, &column);
                if (c == '\\' && at < length && source[at] != '\n') {
                    char next = source[at];
                    advance(source, &at, &line, &column);
                    if (next == 'n')
                        c = '\n';
                    else if (next == 't')
                        c = '\t';
                    else if (next == '\\' || next == '"')
                        c = next;
                    else
                        bad = true;
                }
                text_char(&value, c);
            }
            if (at == length || source[at] == '\n') {
                token.kind = "invalid";
                token.value = "unterminated string";
            } else {
                advance(source, &at, &line, &column);
                token.kind = bad ? "invalid" : "string";
                token.value = bad ? "invalid escape sequence" : text_value(&value);
            }
            token.spelling = ml_text(source + start, at - start);
        } else {
            for (size_t i = 0; i < sizeof(symbols) / sizeof(*symbols); ++i)
                if (strncmp(source + at, symbols[i], strlen(symbols[i])) == 0) {
                    token.kind = symbols[i];
                    token.spelling = (char *)symbols[i];
                    for (size_t j = 0; j < strlen(symbols[i]); ++j)
                        advance(source, &at, &line, &column);
                    break;
                }
            if (!token.kind) {
                token.kind = "invalid";
                token.value = ml_format("illegal character '%c'", source[at]);
                advance(source, &at, &line, &column);
            }
        }
        PUSH(result, token);
    }
    Token eof = {0};
    eof.kind = "EOF";
    eof.position = (Position){file, lines.count + 1, 1};
    PUSH(result, eof);
    return result;
}
