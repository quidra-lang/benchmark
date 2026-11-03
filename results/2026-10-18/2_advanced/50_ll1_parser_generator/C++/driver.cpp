#include "parser.hpp"
Parse drive(const Grammar &grammar, const Sets &sets, const Table &table, std::vector<InputToken> tokens) {
    tokens.push_back({"$", 0});
    Parse out;
    out.tree = std::make_unique<Tree>();
    out.tree->symbol = grammar.start;
    struct Entry {
        std::string symbol;
        Tree *node;
    };
    std::vector<Entry> stack{{"$", nullptr}, {grammar.start, out.tree.get()}};
    std::size_t current = 0;
    while (true) {
        Step step;
        for (const Entry &entry : stack)
            step.stack.push_back(entry.symbol);
        for (std::size_t i = current; i < tokens.size(); ++i)
            step.input.push_back(tokens[i].name);
        out.max_stack = std::max(out.max_stack, int(stack.size()));
        const Entry top = stack.back();
        step.top = top.symbol;
        step.current = tokens[current].name;
        step.position = tokens[current].position;
        if (top.symbol == "$" && step.current == "$") {
            step.action = Action::accept;
            out.steps.push_back(std::move(step));
            break;
        }
        if (top.symbol == "$") {
            step.action = Action::skip;
            ++out.skip;
            ++current;
        } else if (!nonterminal(top.symbol)) {
            stack.pop_back();
            if (top.symbol == step.current) {
                step.action = Action::match;
                ++out.matches;
                ++current;
            } else {
                step.action = Action::missing;
                ++out.missing;
                top.node->mark = "missing";
            }
        } else {
            const auto found = table.chosen.find({top.symbol, step.current});
            if (found != table.chosen.end()) {
                step.action = Action::predict;
                step.production = found->second;
                out.left_parse.push_back(step.production);
                stack.pop_back();
                const Sequence &rhs = table.productions[step.production].rhs;
                if (rhs.empty()) {
                    auto node = std::make_unique<Tree>();
                    node->symbol = "%empty";
                    top.node->children.push_back(std::move(node));
                } else {
                    for (const std::string &symbol : rhs) {
                        auto node = std::make_unique<Tree>();
                        node->symbol = symbol;
                        top.node->children.push_back(std::move(node));
                    }
                    for (std::size_t i = rhs.size(); i > 0; --i)
                        stack.push_back({rhs[i - 1], top.node->children[i - 1].get()});
                }
            } else if (step.current == "$" || sets.follow.at(top.symbol).count(step.current)) {
                step.action = Action::pop;
                ++out.pop;
                top.node->mark = "error";
                stack.pop_back();
            } else {
                step.action = Action::skip;
                ++out.skip;
                ++current;
            }
        }
        out.steps.push_back(std::move(step));
    }
    return out;
}
