#include "formula.hpp"
bool containsWord(const std::string &words, const std::string &value) {
    std::istringstream input(words);
    for (std::string word; input >> word;)
        if (word == value)
            return true;
    return false;
}
bool greekName(const std::string &name) {
    return containsWord(
        "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega",
        name);
}
bool commandName(const std::string &name) {
    return name.size() > 1 && symbolCommands().count("\\" + name);
}
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static bool digit(char c) { return c >= '0' && c <= '9'; }
Lexed tokenize(const std::string &line) {
    Lexed out;
    const auto fail = [&](int column, const std::string &message) {
        out.error = Issue{column, message};
    };
    for (std::size_t at = 0; at < line.size();) {
        char c = line[at];
        int column = static_cast<int>(at + 1);
        if (c == ' ') {
            ++at;
            continue;
        }
        if (letter(c) || digit(c)) {
            bool identifier = letter(c);
            std::size_t end = at + 1;
            while (end < line.size() && (identifier ? letter(line[end]) : digit(line[end])))
                ++end;
            if (!identifier && end + 1 < line.size() && line[end] == '.' && digit(line[end + 1])) {
                end += 2;
                while (end < line.size() && digit(line[end]))
                    ++end;
            }
            out.tokens.push_back(
                {identifier ? Kind::Identifier : Kind::Number, line.substr(at, end - at), column});
            at = end;
            continue;
        }
        if (std::string("+-*/=<>:()[],;.!|'").find(c) != std::string::npos) {
            out.tokens.push_back({Kind::Symbol, std::string(1, c), column});
            ++at;
            continue;
        }
        const std::map<char, Kind> special{{'{', Kind::OpenBrace},
                                           {'}', Kind::CloseBrace},
                                           {'^', Kind::Sup},
                                           {'_', Kind::Sub},
                                           {'&', Kind::Amp}};
        auto specialToken = special.find(c);
        if (specialToken != special.end()) {
            out.tokens.push_back({specialToken->second, std::string(1, c), column});
            ++at;
            continue;
        }
        if (c != '\\') {
            fail(column, "invalid character " + std::string(1, c));
            return out;
        }
        if (at + 1 < line.size() && line[at + 1] == '\\') {
            out.tokens.push_back({Kind::Newline, "", column});
            at += 2;
            continue;
        }
        if (at + 1 < line.size() && std::string("{},").find(line[at + 1]) != std::string::npos) {
            out.tokens.push_back({Kind::Command, line.substr(at, 2), column});
            at += 2;
            continue;
        }
        std::size_t end = at + 1;
        while (end < line.size() && letter(line[end]))
            ++end;
        if (end == at + 1) {
            fail(column, "invalid command");
            return out;
        }
        std::string name = line.substr(at + 1, end - at - 1);
        at = end;
        const std::map<std::string, Kind> raw{{"text", Kind::Text},   {"begin", Kind::Begin},
                                              {"end", Kind::End},     {"tag", Kind::Tag},
                                              {"label", Kind::Label}, {"eqref", Kind::Eqref}};
        auto rawKind = raw.find(name);
        if (rawKind != raw.end()) {
            while (at < line.size() && line[at] == ' ')
                ++at;
            if (at == line.size() || line[at] != '{') {
                fail(static_cast<int>(at + 1), "expected {");
                return out;
            }
            end = line.find('}', at + 1);
            if (end == std::string::npos) {
                fail(column, "unterminated argument");
                return out;
            }
            std::string value = line.substr(at + 1, end - at - 1);
            at = end + 1;
            if ((name == "begin" || name == "end") &&
                !containsWord("matrix pmatrix bmatrix vmatrix cases", value)) {
                fail(column, "unknown environment \"" + value + "\"");
                return out;
            }
            out.tokens.push_back({rawKind->second, value, column});
            continue;
        }
        if (symbolCommands().count("\\" + name)) {
            out.tokens.push_back({Kind::Command, "\\" + name, column});
            continue;
        }
        if (containsWord("overline hat vec dot tilde overbrace underbrace", name)) {
            out.tokens.push_back({Kind::Accent, name, column});
            continue;
        }
        const std::map<std::string, Kind> constructs{
            {"frac", Kind::Fraction},     {"binom", Kind::Binomial},  {"overset", Kind::Overset},
            {"underset", Kind::Underset}, {"sqrt", Kind::SquareRoot}, {"left", Kind::Left},
            {"right", Kind::Right}};
        auto construct = constructs.find(name);
        if (construct == constructs.end()) {
            fail(column, "unknown command \\" + name);
            return out;
        }
        out.tokens.push_back({construct->second, "", column});
    }
    return out;
}
