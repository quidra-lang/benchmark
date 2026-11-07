#include "parser.hpp"
#include <filesystem>
static Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines out;
    std::string line;
    while (std::getline(file, line))
        out.push_back(line);
    return out;
}
static Sequence words(const std::string &line) {
    std::istringstream input(line);
    Sequence out;
    std::string word;
    while (input >> word)
        out.push_back(word);
    return out;
}
static std::string join(const Lines &values, const std::string &separator = " ") {
    std::string out;
    for (const std::string &value : values)
        out += (out.empty() ? "" : separator) + value;
    return out;
}
static std::string number_list(const Ints &values, bool productions = false) {
    Lines out;
    for (int value : values)
        out.push_back(std::to_string(value + (productions ? 1 : 0)));
    return join(out);
}
static void heading_list(std::ostream &out, const std::string &heading, const Lines &values) {
    out << heading;
    for (const std::string &value : values)
        out << ' ' << value;
    out << '\n';
}
static void number_heading(std::ostream &out, const std::string &heading, const Ints &values,
                           bool productions = false) {
    out << heading;
    for (int value : values)
        out << ' ' << value + (productions ? 1 : 0);
    out << '\n';
}
static Lines terminal_list(const Terminals &values) {
    return {values.begin(), values.end()};
}
static void remove_names(Grammar &grammar, const std::set<std::string> &removed) {
    Lines kept;
    for (const std::string &name : grammar.order)
        if (removed.count(name))
            grammar.rules.erase(name);
        else
            kept.push_back(name);
    grammar.order = std::move(kept);
}
static std::set<std::string> reachable(const Grammar &grammar) {
    std::set<std::string> seen{grammar.start};
    std::queue<std::string> queue;
    queue.push(grammar.start);
    while (!queue.empty()) {
        const std::string current = queue.front();
        queue.pop();
        for (const Sequence &alternative : grammar.rules.at(current))
            for (const std::string &symbol : alternative)
                if (nonterminal(symbol) && seen.insert(symbol).second)
                    queue.push(symbol);
    }
    return seen;
}
static void clean(Grammar &grammar, Lines &diagnostics) {
    std::set<std::string> undefined;
    for (const std::string &name : grammar.order)
        for (const Sequence &alternative : grammar.rules.at(name))
            for (const std::string &symbol : alternative)
                if (nonterminal(symbol) && !grammar.rules.count(symbol))
                    undefined.insert(symbol);
    Lines ordered(undefined.begin(), undefined.end());
    std::sort(ordered.begin(), ordered.end(), [](const std::string &a, const std::string &b) {
        return a.substr(1, a.size() - 2) < b.substr(1, b.size() - 2);
    });
    for (const std::string &name : ordered)
        diagnostics.push_back("undefined nonterminal " + name);
    auto remove_alternatives = [&](const std::set<std::string> &removed, const std::string &kind) {
        for (const std::string &name : grammar.order) {
            Alternatives kept;
            for (const Sequence &alternative : grammar.rules.at(name)) {
                std::string first;
                for (const std::string &symbol : alternative)
                    if (removed.count(symbol)) {
                        first = symbol;
                        break;
                    }
                if (first.empty())
                    kept.push_back(alternative);
                else
                    diagnostics.push_back("removed " + production_text(name, alternative) + " (" + kind +
                                          " " + first + ")");
            }
            grammar.rules[name] = std::move(kept);
        }
    };
    remove_alternatives(undefined, "undefined");
    std::set<std::string> productive;
    bool changed;
    do {
        changed = false;
        for (const std::string &name : grammar.order)
            for (const Sequence &alternative : grammar.rules.at(name)) {
                bool possible = true;
                for (const std::string &symbol : alternative)
                    if (nonterminal(symbol) && !productive.count(symbol)) {
                        possible = false;
                        break;
                    }
                if (possible)
                    changed = productive.insert(name).second || changed;
            }
    } while (changed);
    std::set<std::string> unproductive;
    for (const std::string &name : grammar.order)
        if (!productive.count(name)) {
            unproductive.insert(name);
            diagnostics.push_back("unproductive nonterminal " + name);
        }
    remove_names(grammar, unproductive);
    remove_alternatives(unproductive, "unproductive");
    const auto seen = reachable(grammar);
    std::set<std::string> unreachable;
    for (const std::string &name : grammar.order)
        if (!seen.count(name)) {
            unreachable.insert(name);
            diagnostics.push_back("unreachable nonterminal " + name);
        }
    remove_names(grammar, unreachable);
}
static void report_recursion(const Grammar &grammar, Lines &diagnostics) {
    for (const std::string &start : grammar.order) {
        std::queue<std::string> queue;
        std::set<std::string> seen{start};
        std::map<std::string, std::string> parent;
        queue.push(start);
        bool found = false;
        std::string last;
        while (!queue.empty() && !found) {
            const std::string current = queue.front();
            queue.pop();
            for (const Sequence &alternative : grammar.rules.at(current))
                if (!alternative.empty() && nonterminal(alternative[0])) {
                    const std::string next = alternative[0];
                    if (next == start) {
                        found = true;
                        last = current;
                        break;
                    }
                    if (seen.insert(next).second) {
                        parent[next] = current;
                        queue.push(next);
                    }
                }
        }
        if (found) {
            Lines path;
            std::string current = last;
            while (current != start) {
                path.push_back(current);
                current = parent.at(current);
            }
            std::reverse(path.begin(), path.end());
            path.insert(path.begin(), start);
            path.push_back(start);
            diagnostics.push_back("left recursion: " + join(path, " -> "));
        }
    }
}
static std::string summary_line(const Grammar &grammar) {
    Terminals terminals;
    int productions = 0, empty = 0, unit = 0;
    for (const std::string &name : grammar.order)
        for (const Sequence &alternative : grammar.rules.at(name)) {
            ++productions;
            empty += alternative.empty();
            unit += alternative.size() == 1 && nonterminal(alternative[0]);
            for (const std::string &symbol : alternative)
                if (!nonterminal(symbol))
                    terminals.insert(symbol);
        }
    return "start=" + grammar.start + " nonterminals=" + std::to_string(grammar.order.size()) +
           " terminals=" + std::to_string(terminals.size()) + " productions=" + std::to_string(productions) +
           " empty=" + std::to_string(empty) + " unit=" + std::to_string(unit);
}
static void listing(std::ostream &out, const Grammar &grammar, bool numbered = false) {
    int total = 0;
    for (const std::string &name : grammar.order)
        total += grammar.rules.at(name).size();
    const int width = std::to_string(total).size();
    int number = 0;
    for (const std::string &name : grammar.order) {
        bool first = true;
        for (const Sequence &alternative : grammar.rules.at(name)) {
            ++number;
            if (numbered)
                out << std::setw(width) << number << "  ";
            if (first)
                out << name << " -> ";
            else
                out << std::string(name.size(), ' ') << " | ";
            out << notation(alternative) << '\n';
            first = false;
        }
    }
}
static void logs(std::ostream &out, const Lines &values) {
    if (values.empty())
        out << "none\n";
    else
        for (const std::string &value : values)
            out << value << '\n';
}
using Cost = std::pair<int, int>;
static const Cost infinity = {1000000000, 1000000000};
struct Sentences {
    std::map<std::string, Cost> length, context;
    std::map<std::string, Sequence> shortest, left, right;
};
static Cost alternative_cost(const Sequence &sequence, const std::map<std::string, Cost> &length) {
    int terminals = 0, height = 0;
    for (const std::string &symbol : sequence)
        if (nonterminal(symbol)) {
            const Cost value = length.at(symbol);
            if (value == infinity)
                return infinity;
            terminals += value.first;
            height = std::max(height, value.second);
        } else
            ++terminals;
    return {terminals, height + 1};
}
static Sequence concatenate(const Sequence &a, const Sequence &b) {
    Sequence out = a;
    out.insert(out.end(), b.begin(), b.end());
    return out;
}
static Sequence sentence_of(const Sequence &sequence, const std::map<std::string, Sequence> &shortest) {
    Sequence out;
    for (const std::string &symbol : sequence)
        if (nonterminal(symbol)) {
            const Sequence &value = shortest.at(symbol);
            out.insert(out.end(), value.begin(), value.end());
        } else
            out.push_back(symbol);
    return out;
}
static Sentences sentences(const Grammar &grammar, const Table &table) {
    Sentences out;
    for (const std::string &name : grammar.order) {
        out.length[name] = infinity;
        out.context[name] = infinity;
    }
    bool changed;
    do {
        changed = false;
        for (const std::string &name : grammar.order)
            for (const Sequence &alternative : grammar.rules.at(name)) {
                const Cost value = alternative_cost(alternative, out.length);
                if (value < out.length[name]) {
                    out.length[name] = value;
                    changed = true;
                }
            }
    } while (changed);
    std::function<Sequence(const std::string &)> shortest = [&](const std::string &name) {
        const auto known = out.shortest.find(name);
        if (known != out.shortest.end())
            return known->second;
        for (const Sequence &alternative : grammar.rules.at(name))
            if (alternative_cost(alternative, out.length) == out.length[name]) {
                Sequence value;
                for (const std::string &symbol : alternative)
                    if (nonterminal(symbol))
                        value = concatenate(value, shortest(symbol));
                    else
                        value.push_back(symbol);
                out.shortest[name] = value;
                return value;
            }
        return Sequence{};
    };
    for (const std::string &name : grammar.order)
        shortest(name);
    out.context[grammar.start] = {0, 0};
    auto occurrence_cost = [&](const Production &production, std::size_t position) {
        if (out.context.at(production.lhs) == infinity)
            return infinity;
        int size = out.context.at(production.lhs).first;
        for (std::size_t i = 0; i < production.rhs.size(); ++i)
            if (i != position)
                size += nonterminal(production.rhs[i]) ? out.length.at(production.rhs[i]).first : 1;
        return Cost{size, out.context.at(production.lhs).second + 1};
    };
    do {
        changed = false;
        for (const Production &production : table.productions)
            for (std::size_t i = 0; i < production.rhs.size(); ++i)
                if (nonterminal(production.rhs[i])) {
                    const Cost value = occurrence_cost(production, i);
                    if (value < out.context[production.rhs[i]]) {
                        out.context[production.rhs[i]] = value;
                        changed = true;
                    }
                }
    } while (changed);
    out.left[grammar.start] = {};
    out.right[grammar.start] = {};
    std::function<void(const std::string &)> context = [&](const std::string &name) {
        if (out.left.count(name))
            return;
        for (const Production &production : table.productions)
            for (std::size_t i = 0; i < production.rhs.size(); ++i)
                if (production.rhs[i] == name && occurrence_cost(production, i) == out.context.at(name)) {
                    context(production.lhs);
                    const Sequence before(production.rhs.begin(), production.rhs.begin() + i),
                        after(production.rhs.begin() + i + 1, production.rhs.end());
                    out.left[name] =
                        concatenate(out.left.at(production.lhs), sentence_of(before, out.shortest));
                    out.right[name] =
                        concatenate(sentence_of(after, out.shortest), out.right.at(production.lhs));
                    return;
                }
    };
    for (const std::string &name : grammar.order)
        context(name);
    return out;
}
static Ints conflict_path(const Grammar &grammar, const Sets &sets, const Table &table, int number,
                          const std::string &terminal) {
    const std::string why = reason(table, number, terminal);
    if (why == "FIRST") {
        std::queue<int> queue;
        std::set<int> seen{number};
        std::map<int, int> parent;
        queue.push(number);
        while (!queue.empty()) {
            const int current = queue.front();
            queue.pop();
            for (const std::string &symbol : table.productions[current].rhs) {
                if (symbol == terminal) {
                    Ints out;
                    int at = current;
                    while (at != number) {
                        out.push_back(at);
                        at = parent.at(at);
                    }
                    std::reverse(out.begin(), out.end());
                    return out;
                }
                if (nonterminal(symbol))
                    for (int next : table.by_lhs.at(symbol))
                        if (seen.insert(next).second) {
                            parent[next] = current;
                            queue.push(next);
                        }
                if (!nonterminal(symbol) || !sets.nullable.at(symbol))
                    break;
            }
        }
        return {};
    }
    std::queue<std::string> queue;
    std::map<std::string, Ints> paths;
    const std::string start = table.productions[number].lhs;
    queue.push(start);
    paths[start] = {};
    while (!queue.empty()) {
        const std::string current = queue.front();
        queue.pop();
        if (current == grammar.start && terminal == "$")
            return paths.at(current);
        for (std::size_t p = 0; p < table.productions.size(); ++p) {
            const Production &production = table.productions[p];
            for (std::size_t i = 0; i < production.rhs.size(); ++i)
                if (production.rhs[i] == current) {
                    const Sequence suffix(production.rhs.begin() + i + 1, production.rhs.end());
                    const auto first = first_sequence(suffix, sets);
                    Ints path = paths.at(current);
                    path.push_back(p);
                    if (first.first.count(terminal))
                        return path;
                    if (first.second && !paths.count(production.lhs)) {
                        paths[production.lhs] = path;
                        queue.push(production.lhs);
                    }
                }
        }
    }
    return {};
}
struct EarleyItem {
    int production, dot, origin;
    bool operator<(const EarleyItem &other) const {
        return std::tie(production, dot, origin) < std::tie(other.production, other.dot, other.origin);
    }
};
static bool language(const Grammar &grammar, const Sequence &tokens) {
    std::vector<Production> productions;
    std::map<std::string, Ints> by_lhs;
    for (const std::string &name : grammar.order)
        for (const Sequence &alternative : grammar.rules.at(name)) {
            by_lhs[name].push_back(productions.size());
            productions.push_back({name, alternative});
        }
    const int augmented = productions.size();
    productions.push_back({"<@start>", {grammar.start}});
    struct Chart {
        std::vector<EarleyItem> items;
        std::set<EarleyItem> seen;
        void add(EarleyItem item) {
            if (seen.insert(item).second)
                items.push_back(item);
        }
    };
    std::vector<Chart> chart(tokens.size() + 1);
    chart[0].add({augmented, 0, 0});
    for (std::size_t position = 0; position < chart.size(); ++position) {
        std::size_t previous;
        do {
            previous = chart[position].items.size();
            for (std::size_t index = 0; index < chart[position].items.size(); ++index) {
                const EarleyItem item = chart[position].items[index];
                const Production &production = productions[item.production];
                if (item.dot == int(production.rhs.size())) {
                    const std::size_t count = chart[item.origin].items.size();
                    for (std::size_t i = 0; i < count; ++i) {
                        const EarleyItem waiting = chart[item.origin].items[i];
                        const Production &source = productions[waiting.production];
                        if (waiting.dot < int(source.rhs.size()) && source.rhs[waiting.dot] == production.lhs)
                            chart[position].add({waiting.production, waiting.dot + 1, waiting.origin});
                    }
                } else {
                    const std::string &symbol = production.rhs[item.dot];
                    if (nonterminal(symbol)) {
                        for (int p : by_lhs.at(symbol))
                            chart[position].add({p, 0, int(position)});
                    } else if (position < tokens.size() && symbol == tokens[position])
                        chart[position + 1].add({item.production, item.dot + 1, item.origin});
                }
            }
        } while (chart[position].items.size() != previous);
    }
    return chart.back().seen.count({augmented, 1, 0}) != 0;
}
static std::unique_ptr<Tree> compact(const Tree &node) {
    std::vector<std::unique_ptr<Tree>> children;
    for (const auto &child : node.children) {
        if (child->symbol == "%empty")
            continue;
        auto value = compact(*child);
        if (value->mark.empty() && nonterminal(value->symbol) && value->children.empty())
            continue;
        if (value->mark.empty() && nonterminal(value->symbol) &&
            value->symbol.find('\'') != std::string::npos) {
            for (auto &grandchild : value->children)
                children.push_back(std::move(grandchild));
        } else
            children.push_back(std::move(value));
    }
    if (children.size() == 1 && node.mark.empty())
        return std::move(children[0]);
    auto out = std::make_unique<Tree>();
    out->symbol = node.symbol;
    out->mark = node.mark;
    out->children = std::move(children);
    return out;
}
static std::string label(const Tree &node) {
    return node.symbol + (node.mark.empty() ? "" : " (" + node.mark + ")");
}
static void tree_children(std::ostream &out, const Tree &node, const std::string &prefix) {
    for (std::size_t i = 0; i < node.children.size(); ++i) {
        const bool last = i + 1 == node.children.size();
        out << prefix << (last ? "`-- " : "|-- ") << label(*node.children[i]) << '\n';
        tree_children(out, *node.children[i], prefix + (last ? "    " : "|   "));
    }
}
static void print_tree(std::ostream &out, const Tree &tree) {
    out << label(tree) << '\n';
    tree_children(out, tree, "");
}
static std::string action_text(const Step &step, const Table &table) {
    switch (step.action) {
    case Action::accept:
        return "accept";
    case Action::match:
        return "match " + step.current;
    case Action::predict:
        return "predict " + std::to_string(step.production + 1) + ": " +
               production_text(table.productions[step.production].lhs,
                               table.productions[step.production].rhs);
    case Action::skip:
        return "error: skip " + step.current;
    case Action::pop:
        return "error: pop " + step.top;
    case Action::missing:
        return "error: missing " + step.top;
    }
    return "";
}
static std::string error_text(const Step &step, int number, const Table &table) {
    const std::string unexpected = step.current == "$"
                                       ? "end of input"
                                       : "\"" + step.current + "\" at token " + std::to_string(step.position);
    Lines expected;
    if (nonterminal(step.top)) {
        for (const std::string &terminal : table.terminals)
            if (table.cells.count({step.top, terminal}))
                expected.push_back(terminal == "$" ? terminal : "\"" + terminal + "\"");
    } else
        expected.push_back(step.top == "$" ? step.top : "\"" + step.top + "\"");
    const std::string recovery = step.action == Action::skip  ? "skipped \"" + step.current + "\""
                                 : step.action == Action::pop ? "popped " + step.top
                                                              : "inserted \"" + step.top + "\"";
    return "step " + std::to_string(number) + ": unexpected " + unexpected + "; expected " + join(expected) +
           "; " + recovery;
}
static void trace(std::ostream &out, const Parse &parse, const Table &table) {
    std::vector<std::array<std::string, 4>> rows{{"step", "stack", "input", "action"}};
    for (std::size_t i = 0; i < parse.steps.size(); ++i) {
        const Step &step = parse.steps[i];
        rows.push_back(
            {std::to_string(i + 1), notation(step.stack), notation(step.input), action_text(step, table)});
    }
    std::array<std::size_t, 3> widths{};
    for (const auto &row : rows)
        for (int column = 0; column < 3; ++column)
            widths[column] = std::max(widths[column], row[column].size());
    for (const auto &row : rows)
        out << std::left << std::setw(widths[0]) << row[0] << "  " << std::setw(widths[1]) << row[1] << "  "
            << std::setw(widths[2]) << row[2] << "  " << row[3] << '\n';
}
static void save(const std::string &name, const std::ostringstream &stream) {
    std::istringstream input(stream.str());
    Lines lines;
    std::string line;
    while (std::getline(input, line))
        lines.push_back(line);
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &value : lines)
        file << value << '\n';
}
int main() {
    std::filesystem::create_directories("output");
    const Parsed parsed = read_grammar(read_lines("input/grammar.bnf"));
    Grammar grammar = parsed.grammar;
    Lines diagnostics = parsed.diagnostics;
    if (parsed.declarations)
        for (const auto &entry : parsed.word_first)
            if (!parsed.declared.count(entry.first))
                diagnostics.push_back("undeclared terminal " + entry.first + " at line " +
                                      std::to_string(entry.second));
    clean(grammar, diagnostics);
    const Grammar cleaned = grammar;
    report_recursion(cleaned, diagnostics);
    const int before = build_table(cleaned, first_follow(cleaned)).conflicts;
    const Lines elimination = eliminate_recursion(grammar);
    const Grammar eliminated = grammar;
    const Lines factoring = left_factor(grammar);
    const Grammar factored = grammar;
    const auto seen = reachable(grammar);
    std::set<std::string> removed;
    Lines removal;
    for (const std::string &name : grammar.order)
        if (!seen.count(name)) {
            removed.insert(name);
            removal.push_back("remove unreachable " + name);
            diagnostics.push_back("unreachable after transformation " + name);
        }
    remove_names(grammar, removed);
    const Sets sets = first_follow(grammar);
    const Table table = build_table(grammar, sets);
    const Sentences sentence = sentences(grammar, table);
    Terminals known;
    for (const std::string &terminal : table.terminals)
        if (terminal != "$")
            known.insert(terminal);
    if (parsed.declarations)
        for (const std::string &terminal : parsed.declared)
            if (!known.count(terminal))
                diagnostics.push_back("unused token " + terminal);
    std::ostringstream grammar_file, sets_file, table_file, parses_file, diagnostics_file;
    grammar_file << "== cleaned grammar ==\n" << summary_line(cleaned) << '\n';
    listing(grammar_file, cleaned);
    grammar_file << "\n== left recursion elimination ==\n";
    logs(grammar_file, elimination);
    grammar_file << summary_line(eliminated) << '\n';
    listing(grammar_file, eliminated);
    grammar_file << "\n== left factoring ==\n";
    logs(grammar_file, factoring);
    grammar_file << summary_line(factored) << '\n';
    listing(grammar_file, factored);
    grammar_file << "\n== final grammar ==\n";
    logs(grammar_file, removal);
    grammar_file << summary_line(grammar) << '\n';
    listing(grammar_file, grammar, true);
    grammar_file << "\n== cross reference ==\n";
    Lines symbols = grammar.order;
    symbols.insert(symbols.end(), known.begin(), known.end());
    for (const std::string &symbol : symbols) {
        Ints used;
        for (std::size_t p = 0; p < table.productions.size(); ++p)
            if (std::find(table.productions[p].rhs.begin(), table.productions[p].rhs.end(), symbol) !=
                table.productions[p].rhs.end())
                used.push_back(p);
        const std::string name = nonterminal(symbol) ? symbol : "\"" + symbol + "\"";
        if (used.empty())
            grammar_file << name << " not used\n";
        else
            number_heading(grammar_file, name + " used in", used, true);
    }
    sets_file << "passes: nullable=" << sets.nullable_passes << " first=" << sets.first_passes
              << " follow=" << sets.follow_passes << "\n\n";
    for (const std::string &name : grammar.order) {
        sets_file << name << "\n  nullable: " << (sets.nullable.at(name) ? "yes" : "no") << '\n';
        heading_list(sets_file, "  first:", terminal_list(sets.first.at(name)));
        heading_list(sets_file, "  follow:", terminal_list(sets.follow.at(name)));
        heading_list(sets_file, "  shortest:", sentence.shortest.at(name));
    }
    table_file << "== predict sets ==\n";
    for (std::size_t p = 0; p < table.productions.size(); ++p) {
        table_file << p + 1 << ": " << production_text(table.productions[p].lhs, table.productions[p].rhs)
                   << '\n';
        heading_list(table_file, "  predict:", terminal_list(table.predict[p]));
    }
    table_file << "\n== parse table ==\n";
    std::vector<Lines> rows;
    Lines header = {""};
    header.insert(header.end(), table.terminals.begin(), table.terminals.end());
    rows.push_back(header);
    for (const std::string &name : grammar.order) {
        Lines row = {name};
        for (const std::string &terminal : table.terminals) {
            const auto cell = table.cells.find({name, terminal});
            if (cell == table.cells.end())
                row.push_back(".");
            else {
                Lines values;
                for (int number : cell->second)
                    values.push_back(std::to_string(number + 1));
                row.push_back(join(values, "/"));
            }
        }
        rows.push_back(std::move(row));
    }
    std::vector<std::size_t> widths(header.size());
    for (const Lines &row : rows)
        for (std::size_t i = 0; i < row.size(); ++i)
            widths[i] = std::max(widths[i], row[i].size());
    for (const Lines &row : rows) {
        table_file << std::left << std::setw(widths[0]) << row[0];
        for (std::size_t i = 1; i < row.size(); ++i)
            table_file << "  " << std::right << std::setw(widths[i]) << row[i];
        table_file << '\n';
    }
    table_file << "\n== conflicts ==\n";
    if (!table.conflicts)
        table_file << "none\n";
    for (const std::string &name : grammar.order)
        for (const std::string &terminal : table.terminals) {
            const auto found = table.cells.find({name, terminal});
            if (found == table.cells.end() || found->second.size() < 2)
                continue;
            const Ints &cell = found->second;
            table_file << "conflict " << name << " on " << terminal << ": "
                       << conflict_kind(table, cell, terminal) << ", chosen "
                       << table.chosen.at({name, terminal}) + 1 << '\n';
            for (int number : cell) {
                const Ints path = conflict_path(grammar, sets, table, number, terminal);
                table_file << "  " << number + 1 << ": "
                           << production_text(table.productions[number].lhs, table.productions[number].rhs)
                           << " (" << reason(table, number, terminal);
                if (!path.empty())
                    table_file << " via " << number_list(path, true);
                table_file << ")\n";
            }
        }
    table_file << "LL(1): " << (table.conflicts ? "no" : "yes")
               << "\nconflicts before transformation: " << before << '\n';
    const Lines inputs = read_lines("input/inputs.txt");
    std::set<int> used;
    Ints mismatches;
    int accepted_count = 0, in_language = 0, unknown_total = 0, skip_total = 0, pop_total = 0,
        missing_total = 0;
    for (std::size_t input = 0; input < inputs.size(); ++input) {
        const Sequence original = words(inputs[input]);
        std::vector<InputToken> tokens;
        Lines errors;
        for (std::size_t i = 0; i < original.size(); ++i)
            if (!known.count(original[i])) {
                errors.push_back("unknown \"" + original[i] + "\" at token " + std::to_string(i + 1) +
                                 "; removed");
                ++unknown_total;
            } else
                tokens.push_back({original[i], int(i + 1)});
        Parse parse = drive(grammar, sets, table, tokens);
        for (std::size_t i = 0; i < parse.steps.size(); ++i)
            if (parse.steps[i].action == Action::skip || parse.steps[i].action == Action::pop ||
                parse.steps[i].action == Action::missing)
                errors.push_back(error_text(parse.steps[i], i + 1, table));
        const bool accepted = errors.empty(), belongs = language(cleaned, original);
        accepted_count += accepted;
        in_language += belongs;
        if (accepted != belongs)
            mismatches.push_back(input + 1);
        skip_total += parse.skip;
        pop_total += parse.pop;
        missing_total += parse.missing;
        used.insert(parse.left_parse.begin(), parse.left_parse.end());
        parses_file << "== input " << input + 1 << " ==\n";
        heading_list(parses_file, "tokens:", original);
        trace(parses_file, parse, table);
        number_heading(parses_file, "left parse:", parse.left_parse, true);
        parses_file << "stats: steps=" << parse.steps.size() << " predicts=" << parse.left_parse.size()
                    << " matches=" << parse.matches << " max_stack=" << parse.max_stack << '\n';
        if (!errors.empty()) {
            parses_file << "errors:\n";
            for (const std::string &error : errors)
                parses_file << "  " << error << '\n';
        }
        parses_file << "result: ";
        if (accepted)
            parses_file << "accepted\n";
        else
            parses_file << "rejected (errors: " << errors.size() << ")\n";
        parses_file << "language: " << (belongs ? "yes" : "no") << '\n';
        if (accepted) {
            parses_file << "derivation:\n  " << grammar.start << '\n';
            Sequence form{grammar.start};
            for (int number : parse.left_parse) {
                const auto first = std::find_if(
                    form.begin(), form.end(), [](const std::string &symbol) { return nonterminal(symbol); });
                const std::size_t position = first - form.begin();
                form.erase(first);
                form.insert(form.begin() + position, table.productions[number].rhs.begin(),
                            table.productions[number].rhs.end());
                parses_file << "  => " << notation(form) << '\n';
            }
        }
        parses_file << "tree:\n";
        print_tree(parses_file, *parse.tree);
        parses_file << "compact tree:\n";
        const auto tree = compact(*parse.tree);
        print_tree(parses_file, *tree);
        parses_file << '\n';
    }
    parses_file << "== summary ==\ninputs=" << inputs.size() << " accepted=" << accepted_count
                << " rejected=" << inputs.size() - accepted_count << " in_language=" << in_language << '\n';
    number_heading(parses_file, "mismatches:", mismatches);
    parses_file << "recovery: unknown=" << unknown_total << " skip=" << skip_total << " pop=" << pop_total
                << " missing=" << missing_total << "\ncoverage: " << used.size() << " of "
                << table.productions.size() << " productions used\n";
    Ints unused;
    for (std::size_t number = 0; number < table.productions.size(); ++number)
        if (!used.count(number))
            unused.push_back(number);
    number_heading(parses_file, "unused:", unused, true);
    for (int number : unused) {
        const Production &production = table.productions[number];
        Sequence example = concatenate(
            concatenate(sentence.left.at(production.lhs), sentence_of(production.rhs, sentence.shortest)),
            sentence.right.at(production.lhs));
        std::vector<InputToken> tokens;
        for (std::size_t i = 0; i < example.size(); ++i)
            tokens.push_back({example[i], int(i + 1)});
        const Parse parse = drive(grammar, sets, table, tokens);
        const int errors = parse.skip + parse.pop + parse.missing;
        parses_file << "  " << number + 1 << ": " << production_text(production.lhs, production.rhs) << '\n';
        heading_list(parses_file, "    example:", example);
        if (errors)
            parses_file << "    result: rejected (errors: " << errors << ")\n";
        else
            parses_file << "    result: accepted\n";
        parses_file << "    used: "
                    << (std::find(parse.left_parse.begin(), parse.left_parse.end(), number) !=
                                parse.left_parse.end()
                            ? "yes"
                            : "no")
                    << '\n';
    }
    for (const std::string &diagnostic : diagnostics)
        diagnostics_file << diagnostic << '\n';
    if (table.conflicts)
        diagnostics_file << "result: not LL(1) (conflicts: " << table.conflicts << ")\n";
    else
        diagnostics_file << "result: LL(1)\n";
    save("grammar.txt", grammar_file);
    save("sets.txt", sets_file);
    save("table.txt", table_file);
    save("parses.txt", parses_file);
    save("diagnostics.txt", diagnostics_file);
}
