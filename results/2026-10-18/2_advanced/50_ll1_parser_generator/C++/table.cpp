#include "parser.hpp"
Table build_table(const Grammar &grammar, const Sets &sets) {
    Table out;
    Terminals terminals;
    for (const std::string &name : grammar.order)
        for (const Sequence &alternative : grammar.rules.at(name)) {
            const int number = out.productions.size();
            out.productions.push_back({name, alternative});
            out.by_lhs[name].push_back(number);
            const auto first = first_sequence(alternative, sets);
            out.first.push_back(first.first);
            Terminals predict = first.first;
            if (first.second) {
                const auto &follow = sets.follow.at(name);
                predict.insert(follow.begin(), follow.end());
            }
            out.predict.push_back(predict);
            for (const std::string &terminal : predict)
                out.cells[{name, terminal}].push_back(number);
            for (const std::string &symbol : alternative)
                if (!nonterminal(symbol))
                    terminals.insert(symbol);
        }
    terminals.insert("$");
    out.terminals.assign(terminals.begin(), terminals.end());
    for (const auto &entry : out.cells) {
        const auto &cell = entry.second;
        if (cell.size() > 1)
            ++out.conflicts;
        int chosen = cell[0];
        for (int number : cell)
            if (out.first[number].count(entry.first.second)) {
                chosen = number;
                break;
            }
        out.chosen[entry.first] = chosen;
    }
    return out;
}
std::string reason(const Table &table, int production, const std::string &terminal) {
    return table.first[production].count(terminal) ? "FIRST" : "FOLLOW";
}
std::string conflict_kind(const Table &table, const Ints &cell, const std::string &terminal) {
    int first = 0;
    for (int production : cell)
        first += table.first[production].count(terminal);
    return first == int(cell.size()) ? "FIRST/FIRST" : first == 0 ? "FOLLOW/FOLLOW" : "FIRST/FOLLOW";
}
