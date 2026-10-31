#include "chemistry.hpp"
#include <algorithm>
#include <set>
bool digit(char c) { return c >= '0' && c <= '9'; }
std::optional<std::pair<Atom, std::size_t>> organic(const std::string &source, std::size_t at) {
    Atom atom;
    if (at + 1 < source.size() && (source.substr(at, 2) == "Cl" || source.substr(at, 2) == "Br")) {
        atom.symbol = source.substr(at, 2);
        return std::make_pair(atom, at + 2);
    }
    char c = source[at];
    if (std::string("BCNOPSFI").find(c) != std::string::npos) {
        atom.symbol = std::string(1, c);
        return std::make_pair(atom, at + 1);
    }
    if (std::string("bcnops").find(c) != std::string::npos) {
        atom.symbol = std::string(1, static_cast<char>(c - 'a' + 'A'));
        atom.aromatic = true;
        return std::make_pair(atom, at + 1);
    }
    return std::nullopt;
}
std::pair<Atom, std::string> bracket(const std::string &content, const Elements &elements) {
    Atom atom;
    atom.bracket = true;
    std::size_t i = 0;
    while (i < content.size() && digit(content[i]))
        ++i;
    if (i >= 4 || (i && content[0] == '0'))
        return {atom, "bad bracket atom"};
    if (i)
        atom.mass = std::stoi(content.substr(0, i));
    if (i == content.size())
        return {atom, "bad bracket atom"};
    char c = content[i];
    if (std::string("bcnops").find(c) != std::string::npos) {
        atom.symbol = std::string(1, static_cast<char>(c - 'a' + 'A'));
        atom.aromatic = true;
        ++i;
    } else if (c >= 'A' && c <= 'Z') {
        if (i + 1 < content.size() && content[i + 1] >= 'a' && content[i + 1] <= 'z' &&
            elements.count(content.substr(i, 2))) {
            atom.symbol = content.substr(i, 2);
            i += 2;
        } else {
            atom.symbol = std::string(1, c);
            if (!elements.count(atom.symbol))
                return {atom, "unknown element"};
            ++i;
        }
    } else
        return {atom, "bad bracket atom"};
    if (content.substr(i, 2) == "@@")
        i += 2;
    else if (i < content.size() && content[i] == '@')
        ++i;
    if (i < content.size() && content[i] == 'H') {
        atom.hydrogens = 1;
        ++i;
        if (i < content.size() && digit(content[i]))
            atom.hydrogens = content[i++] - '0';
    }
    if (i < content.size() && (content[i] == '+' || content[i] == '-')) {
        int sign = content[i++] == '+' ? 1 : -1, magnitude = 1;
        if (i < content.size() && content[i] >= '1' && content[i] <= '9')
            magnitude = content[i++] - '0';
        atom.charge = sign * magnitude;
    }
    return {atom, i == content.size() ? "" : "bad bracket atom"};
}
int symbolType(char c) {
    if (c == '-' || c == '/' || c == '\\')
        return 1;
    if (c == '=')
        return 2;
    if (c == '#')
        return 3;
    if (c == ':')
        return 4;
    if (c == '~')
        return 5;
    return 0;
}
Parsed parseSmiles(const std::string &source, const Elements &elements, bool pattern) {
    Molecule m;
    int current = -1, pendingColumn = 0;
    char pending = 0;
    std::vector<std::pair<int, int>> stack;
    struct Open {
        int atom, column;
        char symbol;
    };
    std::map<int, Open> open;
    std::set<std::pair<int, int>> existing;
    const auto fail = [](const std::string &reason, int column) {
        return Parsed{std::nullopt, ParseError{reason, column}};
    };
    const auto addBond = [&](int a, int b, char symbol) {
        if (a > b)
            std::swap(a, b);
        Bond bond{a, b, symbol};
        if (pattern) {
            int kind = symbolType(symbol);
            bond.match = kind == 0   ? (1 << 1) | (1 << 4)
                         : kind == 5 ? (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
                                     : 1 << kind;
        }
        m.bonds.push_back(bond);
        existing.insert({a, b});
    };
    for (std::size_t i = 0; i < source.size();) {
        char c = source[i];
        int column = static_cast<int>(i) + 1;
        const std::string symbols = pattern ? "-=#:~" : "-/\\=#:";
        if (symbols.find(c) != std::string::npos) {
            if (current < 0 || pending)
                return fail("misplaced bond", column);
            pending = c;
            pendingColumn = column;
            ++i;
        } else if (c == '(') {
            if (current < 0 || pending || (i && source[i - 1] == '('))
                return fail("misplaced branch", column);
            stack.emplace_back(current, column);
            ++i;
        } else if (c == ')') {
            if (stack.empty())
                return fail("unmatched parenthesis", column);
            if (pending)
                return fail("dangling bond", pendingColumn);
            if (i && source[i - 1] == '(')
                return fail("empty branch", column);
            current = stack.back().first;
            stack.pop_back();
            ++i;
        } else if (digit(c) || c == '%') {
            if (current < 0)
                return fail("misplaced ring closure", column);
            int number;
            if (c == '%') {
                if (i + 2 >= source.size() || !digit(source[i + 1]) || !digit(source[i + 2]))
                    return fail("bad ring number", column);
                number = 10 * (source[i + 1] - '0') + source[i + 2] - '0';
                i += 3;
            } else {
                number = c - '0';
                ++i;
            }
            char symbol = pending;
            pending = 0;
            auto found = open.find(number);
            if (found == open.end())
                open[number] = {current, column, symbol};
            else {
                Open old = found->second;
                if (old.atom == current)
                    return fail("self bond", column);
                if (old.symbol && symbol &&
                    (pattern ? old.symbol != symbol : symbolType(old.symbol) != symbolType(symbol)))
                    return fail("ring bond mismatch", column);
                std::pair<int, int> key = {std::min(old.atom, current),
                                           std::max(old.atom, current)};
                if (existing.count(key))
                    return fail("duplicate bond", column);
                addBond(old.atom, current, symbol ? symbol : old.symbol);
                open.erase(found);
            }
        } else {
            Atom atom;
            std::size_t next = i;
            std::string reason;
            if (pattern) {
                auto parsed = patternAtom(source, i, next);
                atom = std::move(parsed.first);
                reason = std::move(parsed.second);
            } else if (c == '[') {
                std::size_t end = source.find(']', i + 1);
                if (end == std::string::npos)
                    return fail("unclosed bracket", column);
                auto parsed = bracket(source.substr(i + 1, end - i - 1), elements);
                atom = std::move(parsed.first);
                reason = std::move(parsed.second);
                next = end + 1;
            } else {
                auto parsed = organic(source, i);
                if (!parsed)
                    reason = "unexpected character";
                else {
                    atom = std::move(parsed->first);
                    next = parsed->second;
                }
            }
            if (!reason.empty())
                return fail(reason, column);
            atom.column = column;
            m.atoms.push_back(std::move(atom));
            int index = static_cast<int>(m.atoms.size()) - 1;
            if (current >= 0)
                addBond(current, index, pending);
            current = index;
            pending = 0;
            i = next;
        }
    }
    if (pending)
        return fail("dangling bond", pendingColumn);
    if (!stack.empty())
        return fail("unmatched parenthesis", stack.front().second);
    if (!open.empty()) {
        int column = static_cast<int>(source.size()) + 1;
        for (const auto &entry : open)
            column = std::min(column, entry.second.column);
        return fail("unclosed ring", column);
    }
    m.build();
    return {std::move(m), std::nullopt};
}
