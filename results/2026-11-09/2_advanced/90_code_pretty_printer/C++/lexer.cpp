#include "formatter.hpp"
std::string trimRight(std::string value) {
    while (!value.empty() && value.back() == ' ')
        value.pop_back();
    return value;
}
bool wordIn(const std::string &words, const std::string &word) {
    std::istringstream input(words);
    for (std::string candidate; input >> candidate;)
        if (candidate == word)
            return true;
    return false;
}
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static bool digit(char c) { return c >= '0' && c <= '9'; }
Lexed lex(const Lines &source) {
    Lexed out;
    int previousLine = 0;
    for (int row = 0; row < static_cast<int>(source.size()); ++row) {
        const std::string &line = source[row];
        for (std::size_t at = 0; at < line.size();) {
            char c = line[at];
            if (c == ' ') {
                ++at;
                continue;
            }
            Position position{row + 1, static_cast<int>(at + 1)};
            int blank = std::max(0, row - previousLine);
            const auto addToken = [&](std::string value, TokenKind kind) {
                std::unique_ptr<Token> token = std::make_unique<Token>();
                token->value = std::move(value);
                token->kind = kind;
                token->position = position;
                token->blank = blank;
                token->index = static_cast<int>(out.tokens.size());
                out.items.push_back({token.get(), nullptr});
                out.tokens.push_back(std::move(token));
                previousLine = row + 1;
            };
            const auto addComment = [&](std::string value, bool lineComment) {
                std::unique_ptr<Comment> comment = std::make_unique<Comment>();
                comment->value = std::move(value);
                comment->line = lineComment;
                comment->position = position;
                comment->blank = blank;
                out.items.push_back({nullptr, comment.get()});
                out.comments.push_back(std::move(comment));
                previousLine = row + 1;
            };
            if (line.compare(at, 2, "//") == 0) {
                addComment(trimRight(line.substr(at)), true);
                break;
            }
            if (line.compare(at, 2, "/*") == 0) {
                std::size_t end = line.find("*/", at + 2);
                if (end == std::string::npos)
                    throw FileError{position, "unterminated comment"};
                end += 2;
                addComment(line.substr(at, end - at), false);
                at = end;
                continue;
            }
            if (letter(c)) {
                std::size_t end = at + 1;
                while (end < line.size() && (letter(line[end]) || digit(line[end])))
                    ++end;
                std::string value = line.substr(at, end - at);
                addToken(
                    value,
                    wordIn(
                        "int float bool string void if else while for return break continue true false switch case default",
                        value)
                        ? TokenKind::Keyword
                        : TokenKind::Identifier);
                at = end;
                continue;
            }
            if (digit(c)) {
                std::size_t end = at + 1;
                while (end < line.size() && digit(line[end]))
                    ++end;
                if (end + 1 < line.size() && line[end] == '.' && digit(line[end + 1])) {
                    end += 2;
                    while (end < line.size() && digit(line[end]))
                        ++end;
                }
                addToken(line.substr(at, end - at), TokenKind::Number);
                at = end;
                continue;
            }
            if (c == '"') {
                std::size_t end = at + 1;
                while (end < line.size() && line[end] != '"')
                    end += line[end] == '\\' ? 2 : 1;
                if (end >= line.size())
                    throw FileError{position, "unterminated string"};
                ++end;
                addToken(line.substr(at, end - at), TokenKind::String);
                at = end;
                continue;
            }
            if (at + 1 < line.size() &&
                wordIn("<= >= == != && || += -= *= /= %=", line.substr(at, 2))) {
                addToken(line.substr(at, 2), TokenKind::Symbol);
                at += 2;
                continue;
            }
            if (std::string("+-*/%<>=!()[]{},;.?:").find(c) != std::string::npos) {
                addToken(std::string(1, c), TokenKind::Symbol);
                ++at;
                continue;
            }
            throw FileError{position, "unexpected character '" + std::string(1, c) + "'"};
        }
    }
    std::unique_ptr<Token> end = std::make_unique<Token>();
    end->position = {static_cast<int>(source.size() + 1), 1};
    end->index = static_cast<int>(out.tokens.size());
    out.tokens.push_back(std::move(end));
    return out;
}
