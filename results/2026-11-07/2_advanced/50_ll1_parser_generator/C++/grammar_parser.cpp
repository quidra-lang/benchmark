#include "parser.hpp"
bool nonterminal(const std::string &symbol) {
    return symbol.size() >= 2 && symbol.front() == '<' && symbol.back() == '>';
}
std::string notation(const Sequence &sequence) {
    if (sequence.empty())
        return "%empty";
    std::string out;
    for (const std::string &symbol : sequence)
        out += (out.empty() ? "" : " ") + symbol;
    return out;
}
std::string production_text(const std::string &lhs, const Sequence &rhs) {
    return lhs + " -> " + notation(rhs);
}
static bool letter(char ch) {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}
static bool word_character(char ch) {
    return letter(ch) || (ch >= '0' && ch <= '9') || ch == '_';
}
struct Token {
    std::string kind, text;
    int start, end;
};
static std::vector<Token> lex(const std::string &line) {
    std::vector<Token> out;
    std::size_t i = 0;
    while (i < line.size()) {
        if (line[i] == ' ') {
            ++i;
            continue;
        }
        if (line[i] == '#')
            break;
        const std::size_t start = i;
        std::string kind = "invalid", text;
        if (line[i] == '<') {
            std::size_t j = i + 1;
            if (j < line.size() && letter(line[j])) {
                ++j;
                while (j < line.size() && word_character(line[j]))
                    ++j;
                if (j < line.size() && line[j] == '>') {
                    i = j + 1;
                    kind = "nt";
                    text = line.substr(start, i - start);
                }
            }
        } else if (line[i] == '"') {
            std::size_t j = i + 1;
            while (j < line.size() && line[j] != ' ' && line[j] != '"')
                ++j;
            if (j > i + 1 && j < line.size() && line[j] == '"') {
                kind = "quoted";
                text = line.substr(i + 1, j - i - 1);
                i = j + 1;
            }
        } else if (letter(line[i])) {
            ++i;
            while (i < line.size() && word_character(line[i]))
                ++i;
            kind = "word";
            text = line.substr(start, i - start);
        } else if (line.compare(i, 3, "::=") == 0) {
            kind = "definition";
            text = "::=";
            i += 3;
        } else if (line[i] == '|') {
            kind = "bar";
            text = "|";
            ++i;
        } else if (line[i] == '%') {
            std::size_t j = i + 1;
            while (j < line.size() && letter(line[j]))
                ++j;
            const std::string directive = line.substr(i + 1, j - i - 1);
            if (directive == "empty" || directive == "start" || directive == "token") {
                kind = directive;
                text = "%" + directive;
                i = j;
            }
        }
        if (kind == "invalid") {
            out.push_back({kind, "", int(start + 1), int(start + 1)});
            break;
        }
        out.push_back({kind, text, int(start + 1), int(i)});
    }
    return out;
}
static int transition(int state, const std::string &kind) {
    if (state == 0) {
        if (kind == "nt")
            return 1;
        if (kind == "bar")
            return 2;
        if (kind == "start")
            return 5;
        if (kind == "token")
            return 7;
    } else if (state == 1) {
        if (kind == "definition")
            return 2;
    } else if (state == 2) {
        if (kind == "nt" || kind == "word" || kind == "quoted")
            return 3;
        if (kind == "empty")
            return 4;
    } else if (state == 3) {
        if (kind == "nt" || kind == "word" || kind == "quoted")
            return 3;
        if (kind == "bar")
            return 2;
    } else if (state == 4) {
        if (kind == "bar")
            return 2;
    } else if (state == 5) {
        if (kind == "nt")
            return 6;
    } else if (state == 7 || state == 8) {
        if (kind == "word")
            return 8;
    }
    return -1;
}
Parsed read_grammar(const Lines &lines) {
    Parsed out;
    std::string attached;
    bool start_seen = false;
    for (std::size_t index = 0; index < lines.size(); ++index) {
        const auto tokens = lex(lines[index]);
        if (tokens.empty())
            continue;
        const int line = index + 1;
        int state = 0, column = 0;
        for (const Token &token : tokens) {
            state = transition(state, token.kind);
            if (state < 0) {
                column = token.start;
                break;
            }
        }
        if (!column && state != 3 && state != 4 && state != 6 && state != 8)
            column = tokens.back().end + 1;
        if (column) {
            out.diagnostics.push_back("line " + std::to_string(line) + ": syntax error at column " +
                                      std::to_string(column));
            attached.clear();
            continue;
        }
        const std::string first = tokens[0].kind;
        if (first == "start") {
            if (start_seen)
                out.diagnostics.push_back("line " + std::to_string(line) + ": duplicate %start");
            else {
                out.grammar.start = tokens[1].text;
                start_seen = true;
            }
            attached.clear();
            continue;
        }
        if (first == "token") {
            out.declarations = true;
            for (std::size_t i = 1; i < tokens.size(); ++i)
                out.declared.insert(tokens[i].text);
            attached.clear();
            continue;
        }
        std::size_t begin;
        if (first == "nt") {
            attached = tokens[0].text;
            if (!out.grammar.rules.count(attached)) {
                out.grammar.order.push_back(attached);
                out.grammar.rules[attached] = {};
            }
            begin = 2;
        } else {
            if (attached.empty()) {
                out.diagnostics.push_back("line " + std::to_string(line) + ": continuation without a rule");
                continue;
            }
            begin = 1;
        }
        Sequence alternative;
        auto append = [&] {
            auto &alternatives = out.grammar.rules[attached];
            if (std::find(alternatives.begin(), alternatives.end(), alternative) != alternatives.end())
                out.diagnostics.push_back("line " + std::to_string(line) + ": duplicate alternative " +
                                          production_text(attached, alternative));
            else
                alternatives.push_back(alternative);
            alternative.clear();
        };
        for (std::size_t i = begin; i < tokens.size(); ++i) {
            const Token &token = tokens[i];
            if (token.kind == "bar") {
                append();
                continue;
            }
            if (token.kind == "word" && !out.word_first.count(token.text))
                out.word_first[token.text] = line;
            if (token.kind != "empty")
                alternative.push_back(token.text);
        }
        append();
    }
    if (!start_seen)
        out.grammar.start = out.grammar.order[0];
    return out;
}
