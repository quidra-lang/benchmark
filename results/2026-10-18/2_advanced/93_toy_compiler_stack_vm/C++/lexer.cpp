#include "compiler.hpp"
bool earlier(Position a, Position b) {
    return std::tie(a.line, a.column) < std::tie(b.line, b.column);
}
std::string position_text(Position p) {
    return std::to_string(p.line) + ":" + std::to_string(p.column);
}
bool word_in(const std::string &words, const std::string &value) {
    std::istringstream input(words);
    std::string word;
    while (input >> word)
        if (word == value)
            return true;
    return false;
}
std::vector<Token> tokenize(const std::vector<std::string> &lines, int first_line) {
    std::string source;
    for (const std::string &line : lines)
        source += line + "\n";
    size_t at = 0;
    Position position{first_line, 1};
    std::vector<Token> tokens;
    auto advance = [&]() {
        if (source[at++] == '\n') {
            ++position.line;
            position.column = 1;
        } else
            ++position.column;
    };
    auto letter = [](char c) {
        return c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
    };
    auto digit = [](char c) { return c >= '0' && c <= '9'; };
    while (at < source.size()) {
        if (source[at] == ' ' || source[at] == '\n') {
            advance();
            continue;
        }
        size_t start = at;
        Token token;
        token.position = position;
        if (source.compare(at, 2, "//") == 0) {
            while (at < source.size() && source[at] != '\n')
                advance();
            continue;
        }
        if (source.compare(at, 2, "/*") == 0) {
            size_t end = source.find("*/", at + 2);
            if (end == std::string::npos)
                throw CompileError{"lexical", "unterminated comment", position};
            while (at < end + 2)
                advance();
            continue;
        }
        if (letter(source[at])) {
            while (at < source.size() && (letter(source[at]) || digit(source[at])))
                advance();
            token.spelling = source.substr(start, at - start);
            token.kind =
                word_in(
                    "int bool void true false if else while for break continue return print read",
                    token.spelling)
                    ? token.spelling
                    : "identifier";
        } else if (digit(source[at])) {
            while (at < source.size() && digit(source[at]))
                advance();
            token.spelling = source.substr(start, at - start);
            size_t first = token.spelling.find_first_not_of('0');
            std::string number = first == std::string::npos ? "0" : token.spelling.substr(first);
            if (number.size() > 10 || (number.size() == 10 && number > "2147483647"))
                throw CompileError{"lexical", "integer literal too large", token.position};
            token.kind = "integer";
            token.integer = std::stoll(number);
        } else if (at + 1 < source.size() && word_in("<= >= == != && ||", source.substr(at, 2))) {
            token.kind = token.spelling = source.substr(at, 2);
            advance();
            advance();
        } else if (std::string("+-*/%<>=!(){}[],;").find(source[at]) != std::string::npos) {
            token.kind = token.spelling = source.substr(at, 1);
            advance();
        } else
            throw CompileError{"lexical", "unexpected character '" + source.substr(at, 1) + "'",
                               position};
        tokens.push_back(std::move(token));
    }
    Token end;
    end.kind = "END";
    end.position = {first_line + static_cast<int>(lines.size()) - 1,
                    static_cast<int>(lines.back().size()) + 1};
    tokens.push_back(end);
    return tokens;
}
