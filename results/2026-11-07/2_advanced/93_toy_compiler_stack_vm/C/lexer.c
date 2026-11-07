#include "compiler.h"
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
bool earlier(Position a, Position b) {
    return a.line < b.line || (a.line == b.line && a.column < b.column);
}
char *position_text(Position p) { return ml_format("%d:%d", p.line, p.column); }
void compile_fail(CompileContext *context, const char *kind, Position position,
                  const char *message) {
    context->kind = kind;
    context->position = position;
    context->message = (char *)message;
    longjmp(context->jump, 1);
}
static bool letter(char c) { return c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
static void advance(const char *source, size_t *at, Position *pos) {
    if (source[(*at)++] == '\n') {
        ++pos->line;
        pos->column = 1;
    } else
        ++pos->column;
}
TokenList tokenize(StringList lines, int first_line, CompileContext *context) {
    Text joined = {0};
    for (int i = 0; i < lines.count; ++i) {
        text_add(&joined, lines.items[i]);
        text_char(&joined, '\n');
    }
    const char *source = text_value(&joined);
    size_t length = strlen(source), at = 0;
    Position pos = {first_line, 1};
    TokenList result = {0};
    while (at < length) {
        if (source[at] == ' ' || source[at] == '\n') {
            advance(source, &at, &pos);
            continue;
        }
        size_t start = at;
        Token token = {0};
        token.position = pos;
        if (strncmp(source + at, "//", 2) == 0) {
            while (at < length && source[at] != '\n')
                advance(source, &at, &pos);
            continue;
        }
        if (strncmp(source + at, "/*", 2) == 0) {
            const char *end = strstr(source + at + 2, "*/");
            if (!end)
                compile_fail(context, "lexical", pos, "unterminated comment");
            size_t stop = (size_t)(end - source) + 2;
            while (at < stop)
                advance(source, &at, &pos);
            continue;
        }
        if (letter(source[at])) {
            while (at < length && (letter(source[at]) || digit(source[at])))
                advance(source, &at, &pos);
            token.spelling = ml_text(source + start, at - start);
            token.kind =
                word_in(
                    "int bool void true false if else while for break continue return print read",
                    token.spelling)
                    ? token.spelling
                    : "identifier";
        } else if (digit(source[at])) {
            while (at < length && digit(source[at]))
                advance(source, &at, &pos);
            token.spelling = ml_text(source + start, at - start);
            const char *number = token.spelling;
            while (number[0] == '0' && number[1])
                ++number;
            if (strlen(number) > 10 || (strlen(number) == 10 && strcmp(number, "2147483647") > 0))
                compile_fail(context, "lexical", token.position, "integer literal too large");
            token.kind = "integer";
            token.integer = strtoll(number, NULL, 10);
        } else if (at + 1 < length) {
            char pair[3] = {source[at], source[at + 1], 0};
            if (word_in("<= >= == != && ||", pair)) {
                token.kind = token.spelling = ml_text(pair, 2);
                advance(source, &at, &pos);
                advance(source, &at, &pos);
            }
        }
        if (!token.kind) {
            if (strchr("+-*/%<>=!(){}[],;", source[at])) {
                token.kind = token.spelling = ml_text(source + at, 1);
                advance(source, &at, &pos);
            } else
                compile_fail(context, "lexical", pos,
                             ml_format("unexpected character '%c'", source[at]));
        }
        PUSH(result, token);
    }
    Token end = {0};
    end.kind = "END";
    end.position =
        (Position){first_line + lines.count - 1, (int)strlen(lines.items[lines.count - 1]) + 1};
    PUSH(result, end);
    return result;
}
