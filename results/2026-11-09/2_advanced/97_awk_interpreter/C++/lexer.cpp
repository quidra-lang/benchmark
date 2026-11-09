#include "awk.hpp"
namespace awk {
    bool letter(char c) {
        return(c >= 'a' && c <= 'z') ||(c >= 'A' && c <= 'Z') || c == '_';
    }
    bool digit(char c) {
        return c >= '0' && c <= '9';
    }
    std::vector<Token> tokenize(const std::string& source) {
        const std::set<std::string> keywords = {"BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue", "next", "exit", "return", "delete", "in", "getline", "print", "printf"};
        const std::set<std::string> builtins = {"length", "substr", "index", "split", "sprintf", "toupper", "tolower", "close", "int"};
        const std::set<std::string> pairs = {"+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>"};
        const std::map<char, char> escapes = { {'n', '\n'}, {'t', '\t'}, {'\\', '\\'}, {'"', '"'}, {'/', '/'} };
        std::vector<Token> result;
        std::size_t i = 0;
        Position position;
        while (i < source.size()) {
            char c = source[i];
            Position start = position;
            if (c == ' ') {
                ++i;
                ++position.column;
                continue;
            }
            if (c == '\\' && i + 1 < source.size() && source[i + 1] == '\n') {
                i += 2;
                ++position.line;
                position.column = 1;
                continue;
            }
            if (c == '#') {
                while (i < source.size() && source[i] != '\n') {
                    ++i;
                    ++position.column;
                }
                continue;
            }
            if (c == '\n') {
                result.push_back({"newline", "\n", "", start});
                ++i;
                ++position.line;
                position.column = 1;
                continue;
            }
            std::size_t end = i + 1;
            std::string kind, value;
            if (digit(c)) {
                while (end < source.size() && digit(source[end]))++end;
                kind = "number";
                value = source.substr(i, end - i);
            } else if (letter(c)) {
                while (end < source.size() &&(letter(source[end]) || digit(source[end])))++end;
                std::string word = source.substr(i, end - i);
                kind = keywords.count(word) ? "keyword" : builtins.count(word) ? "builtin" : end < source.size() && source[end] == '(' ? "function_name" : "name";
            } else if (c == '"') {
                while (end < source.size() && source[end] != '"') {
                    if (source[end] == '\n') throw Issue {start, "", 0};
                    if (source[end] == '\\') {
                        if (end + 1 >= source.size() || !escapes.count(source[end + 1])) throw Issue { {position.line, position.column + static_cast<int>(end - i)}, "", 0};
                        value.push_back(escapes.at(source[end + 1]));
                        end += 2;
                    } else value.push_back(source[end++]);
                }
                if (end == source.size()) throw Issue {start, "", 0};
                ++end;
                kind = "string";
            } else if (pairs.count(source.substr(i, 2))) {
                ++end;
                kind = "symbol";
            } else if (std::string("+-*/%^!><?:=()[]{},;$").find(c) != std::string::npos) kind = "symbol";
            else throw Issue {start, "", 0};
            result.push_back({kind, source.substr(i, end - i), value, start});
            position.column += static_cast<int>(end - i);
            i = end;
        }
        result.push_back({"end", "", "", {static_cast<int>(std::count(source.begin(), source.end(), '\n')) + 1, 1} });
        return result;
    }
}
