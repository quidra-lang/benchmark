#include "preprocessor.hpp"
bool word_in(const std::string &words, const std::string &word) {
    std::istringstream input(words);
    std::string current;
    while (input >> current)
        if (current == word)
            return true;
    return false;
}
static bool identifier_start(char c) {
    return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}
static bool digit(char c) { return c >= '0' && c <= '9'; }
ReadToken read_token(const std::string &source, size_t index, bool header) {
    char c = source[index];
    size_t n = source.size();
    if (header && c == '<') {
        size_t end = source.find('>', index + 1), newline = source.find('\n', index + 1);
        if (end != std::string::npos && (newline == std::string::npos || end < newline))
            return {"header", source.substr(index, end + 1 - index), end + 1};
    }
    if (identifier_start(c)) {
        size_t end = index + 1;
        while (end < n && (identifier_start(source[end]) || digit(source[end])))
            ++end;
        return {"identifier", source.substr(index, end - index), end};
    }
    if (digit(c) || (c == '.' && index + 1 < n && digit(source[index + 1]))) {
        size_t end = index + 1;
        while (end < n) {
            if (std::string("eEpP").find(source[end]) != std::string::npos && end + 1 < n &&
                (source[end + 1] == '+' || source[end + 1] == '-'))
                end += 2;
            else if (identifier_start(source[end]) || digit(source[end]) || source[end] == '.')
                ++end;
            else
                break;
        }
        return {"number", source.substr(index, end - index), end};
    }
    if (c == '\'' || c == '"') {
        size_t end = index + 1;
        while (end < n && source[end] != '\n') {
            if (source[end] == c)
                return {c == '\'' ? "character" : "string", source.substr(index, end + 1 - index),
                        end + 1};
            if (source[end] == '\\' && end + 1 < n && source[end + 1] != '\n')
                end += 2;
            else
                ++end;
        }
    }
    static const std::vector<std::string> punctuators = {
        "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=",
        "&&",  "||",  "*=",  "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##", "[",
        "]",   "(",   ")",   "{",  "}",  ".",  "&",  "*",  "+",  "-",  "~",  "!",
        "/",   "%",   "<",   ">",  "^",  "|",  "?",  ":",  ";",  "=",  ",",  "#"};
    for (const std::string &punctuator : punctuators)
        if (source.compare(index, punctuator.size(), punctuator) == 0)
            return {"punctuator", punctuator, index + punctuator.size()};
    return {"other", source.substr(index, 1), index + 1};
}
static std::vector<LogicalLine> scan(const std::string &source, const std::vector<int> &positions,
                                     int start) {
    std::vector<LogicalLine> lines;
    Tokens tokens;
    bool spaced = true;
    size_t index = 0;
    while (index < source.size()) {
        if (source[index] == ' ') {
            spaced = true;
            ++index;
        } else if (source[index] == '\n') {
            int end = positions[index++];
            lines.push_back({tokens, start, end});
            tokens.clear();
            start = end + 1;
            spaced = true;
        } else if (source.compare(index, 2, "/*") == 0) {
            size_t end = source.find("*/", index + 2);
            index = end == std::string::npos ? source.size() : end + 2;
            spaced = true;
        } else if (source.compare(index, 2, "//") == 0) {
            size_t end = source.find('\n', index);
            index = end == std::string::npos ? source.size() : end;
            spaced = true;
        } else {
            bool header =
                tokens.size() == 2 && tokens[0].spelling == "#" && tokens[1].spelling == "include";
            ReadToken token = read_token(source, index, header);
            tokens.push_back({token.kind, token.spelling, positions[index], spaced, {}});
            index = token.end;
            spaced = false;
        }
    }
    if (!tokens.empty())
        lines.push_back({tokens, start, positions.back()});
    return lines;
}
std::vector<LogicalLine> lex_source(const std::string &source) {
    std::string characters;
    std::vector<int> positions;
    int line = 1;
    for (size_t i = 0; i < source.size();) {
        if (i + 1 < source.size() && source[i] == '\\' && source[i + 1] == '\n') {
            i += 2;
            ++line;
            continue;
        }
        char c = source[i++];
        characters += c;
        positions.push_back(line);
        if (c == '\n')
            ++line;
    }
    return scan(characters, positions, 1);
}
Tokens lex_definition(const std::string &text, int line) {
    std::string source = text + "\n";
    std::vector<int> positions(source.size(), line);
    Tokens result;
    for (const LogicalLine &logical : scan(source, positions, line))
        result.insert(result.end(), logical.tokens.begin(), logical.tokens.end());
    return result;
}
std::string render(const Tokens &tokens) {
    std::string result;
    for (size_t i = 0; i < tokens.size(); ++i) {
        if (i && tokens[i].space)
            result += " ";
        result += tokens[i].spelling;
    }
    return result;
}
std::optional<std::string> single_token(const std::string &source) {
    if (source.empty() || source.compare(0, 2, "//") == 0 || source.compare(0, 2, "/*") == 0)
        return std::nullopt;
    ReadToken token = read_token(source, 0);
    if (token.end != source.size())
        return std::nullopt;
    return token.kind;
}
