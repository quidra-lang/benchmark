#include "ml.hpp"
bool word_in(const std::string &words, const std::string &word) {
    std::istringstream input(words);
    std::string candidate;
    while (input >> candidate)
        if (candidate == word)
            return true;
    return false;
}
std::vector<Token> lex(const std::string &file, const std::vector<std::string> &lines) {
    std::string source;
    for (const std::string &line : lines)
        source += line + "\n";
    std::vector<Token> result;
    size_t at = 0;
    int line = 1, column = 1;
    auto advance = [&]() {
        if (source[at++] == '\n') {
            ++line;
            column = 1;
        } else
            ++column;
    };
    auto letter = [](char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); };
    auto digit = [](char c) { return c >= '0' && c <= '9'; };
    const std::vector<std::string> symbols = {";;", "->", "::", "||", "&&", "<=", ">=", "<>",
                                              ":",  ";",  "=",  "<",  ">",  "+",  "-",  "*",
                                              "/",  "^",  "(",  ")",  "[",  "]",  ",",  "|"};
    while (at < source.size()) {
        if (source[at] == ' ' || source[at] == '\n') {
            advance();
            continue;
        }
        size_t start = at;
        Token token;
        token.position = {file, line, column};
        if (source.compare(at, 2, "(*") == 0) {
            size_t end = source.find("*)", at + 2);
            if (end == std::string::npos) {
                token.kind = "invalid";
                token.value = "unterminated comment";
                result.push_back(token);
                while (at < source.size())
                    advance();
                break;
            }
            while (at < end + 2)
                advance();
            continue;
        }
        if (digit(source[at])) {
            while (at < source.size() && digit(source[at]))
                advance();
            token.spelling = source.substr(start, at - start);
            size_t first = token.spelling.find_first_not_of('0');
            std::string canonical = first == std::string::npos ? "0" : token.spelling.substr(first);
            if (canonical.size() > 10 || (canonical.size() == 10 && canonical > "2147483647")) {
                token.kind = "invalid";
                token.value = "integer literal too large";
            } else {
                token.kind = "integer";
                token.integer = std::stoll(canonical);
            }
        } else if (letter(source[at]) || source[at] == '_') {
            while (at < source.size() && (letter(source[at]) || digit(source[at]) ||
                                          source[at] == '_' || source[at] == '\''))
                advance();
            token.spelling = source.substr(start, at - start);
            token.kind = word_in("let rec and in fun if then else match with true false mod val",
                                 token.spelling)
                             ? token.spelling
                             : "identifier";
        } else if (source[at] == '\'' && at + 1 < source.size() && source[at + 1] >= 'a' &&
                   source[at + 1] <= 'z') {
            advance();
            while (at < source.size() &&
                   (letter(source[at]) || digit(source[at]) || source[at] == '_'))
                advance();
            token.kind = "type_variable";
            token.spelling = source.substr(start, at - start);
        } else if (source[at] == '"') {
            advance();
            bool bad = false;
            while (at < source.size() && source[at] != '\n' && source[at] != '"') {
                char c = source[at];
                advance();
                if (c == '\\' && at < source.size() && source[at] != '\n') {
                    char next = source[at];
                    advance();
                    if (next == 'n')
                        c = '\n';
                    else if (next == 't')
                        c = '\t';
                    else if (next == '\\' || next == '"')
                        c = next;
                    else
                        bad = true;
                }
                token.value += c;
            }
            if (at == source.size() || source[at] == '\n') {
                token.kind = "invalid";
                token.value = "unterminated string";
            } else {
                advance();
                token.kind = bad ? "invalid" : "string";
                if (bad)
                    token.value = "invalid escape sequence";
            }
            token.spelling = source.substr(start, at - start);
        } else {
            for (const std::string &symbol : symbols)
                if (source.compare(at, symbol.size(), symbol) == 0) {
                    token.kind = symbol;
                    token.spelling = symbol;
                    for (size_t i = 0; i < symbol.size(); ++i)
                        advance();
                    break;
                }
            if (token.kind.empty()) {
                token.kind = "invalid";
                token.value = "illegal character '" + std::string(1, source[at]) + "'";
                advance();
            }
        }
        result.push_back(std::move(token));
    }
    Token eof;
    eof.kind = "EOF";
    eof.position = {file, static_cast<int>(lines.size()) + 1, 1};
    result.push_back(eof);
    return result;
}
