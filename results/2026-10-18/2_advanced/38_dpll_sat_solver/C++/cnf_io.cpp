#include "sat.hpp"
Lines read_lines(const std::string &path) {
    std::ifstream in(path);
    Lines out;
    std::string line;
    while (std::getline(in, line))
        out.push_back(line);
    return out;
}
Lines words(const std::string &line) {
    std::istringstream in(line);
    Lines out;
    std::string word;
    while (in >> word)
        out.push_back(word);
    return out;
}
bool well_number(const std::string &text, int maximum_length) {
    if (text.empty() || int(text.size()) > maximum_length)
        return false;
    if (text == "0")
        return true;
    if (text[0] < '1' || text[0] > '9')
        return false;
    return std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
CnfInput read_cnf(const std::string &name) {
    CnfInput out;
    bool header = false;
    int declared = 0;
    Clause current;
    const Lines lines = read_lines("input/" + name);
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const std::string &line = lines[i];
        if (!line.empty() && line[0] == 'c')
            continue;
        const Lines tokens = words(line);
        if (tokens.empty())
            continue;
        const std::string suffix = " at line " + number(i + 1);
        if (tokens[0] == "p") {
            if (header) {
                out.error = "duplicate header" + suffix;
                return out;
            }
            if (tokens.size() != 4 || tokens[1] != "cnf" || !well_number(tokens[2]) ||
                !well_number(tokens[3])) {
                out.error = "bad header" + suffix;
                return out;
            }
            header = true;
            out.formula.variables = std::stoi(tokens[2]);
            declared = std::stoi(tokens[3]);
            continue;
        }
        if (!header) {
            out.error = "missing header";
            return out;
        }
        for (const std::string &token : tokens) {
            const bool negative = token[0] == '-';
            const std::string magnitude = negative ? token.substr(1) : token;
            if (!well_number(magnitude) || (negative && magnitude == "0")) {
                out.error = "bad token " + token + suffix;
                return out;
            }
            const int literal = std::stoi(token);
            if (std::abs(literal) > out.formula.variables) {
                out.error = "literal out of range " + token + suffix;
                return out;
            }
            if (literal)
                current.push_back(literal);
            else {
                out.formula.clauses.push_back(current);
                current.clear();
            }
        }
    }
    if (!header)
        out.error = "missing header";
    else if (!current.empty())
        out.error = "unterminated clause";
    else if (int(out.formula.clauses.size()) != declared)
        out.error = "clause count mismatch header=" + number(declared) +
                    " found=" + number(out.formula.clauses.size());
    return out;
}
Lines model_lines(const Model &model) {
    Lines tokens;
    for (int x = 1; x < int(model.size()); ++x)
        tokens.push_back(number(model[x] ? x : -x));
    tokens.push_back("0");
    Lines out;
    for (std::size_t first = 0; first < tokens.size(); first += 10) {
        std::string line = "v";
        for (std::size_t i = first; i < std::min(first + 10, tokens.size()); ++i)
            line += " " + tokens[i];
        out.push_back(line);
    }
    return out;
}
