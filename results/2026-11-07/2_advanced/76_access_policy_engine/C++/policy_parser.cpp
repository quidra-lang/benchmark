#include "policy.hpp"
Policies read_policies() {
    Policies out;
    std::vector<Element *> stack;
    for (const std::string &raw : read_lines("input/policies.txt")) {
        std::string source = trim(raw);
        if (source.empty() || source[0] == '#')
            continue;
        std::size_t space = source.find(' ');
        std::string keyword = source.substr(0, space),
                    rest = space == std::string::npos ? "" : source.substr(space + 1);
        if (keyword == "POLICYSET" || keyword == "POLICY" || keyword == "RULE") {
            Names fields = split(rest);
            auto owned = std::make_unique<Element>();
            Element *e = owned.get();
            e->kind = keyword == "RULE" ? "rule" : keyword == "POLICY" ? "policy" : "policyset";
            e->identifier = fields[0];
            e->behavior = fields[1];
            e->index = int(out.elements.size());
            if (!stack.empty()) {
                e->parent = stack.back();
                e->parent->children.push_back(e);
            }
            out.elements.push_back(std::move(owned));
            stack.push_back(e);
        } else if (keyword == "END")
            stack.pop_back();
        else if (keyword == "CONDITION")
            stack.back()->condition = parse_expression(rest);
        else if (keyword == "TARGET") {
            TargetLine target;
            for (const std::string &alternative : split(rest, " | ")) {
                Alternative clauses;
                for (const std::string &clause : split(alternative, " & ")) {
                    Names fields = split(clause);
                    std::string reference = fields[0];
                    bool mandatory = reference.back() == '!';
                    if (mandatory)
                        reference.pop_back();
                    clauses.push_back(
                        {reference, fields[1], mandatory, parse_expression(fields[2])});
                }
                target.push_back(clauses);
            }
            stack.back()->targets.push_back(target);
        } else {
            std::size_t first = rest.find(' '), second = rest.find(' ', first + 1);
            Attachment item{
                rest.substr(0, first),
                rest.substr(first + 1, second == std::string::npos ? second : second - first - 1),
                {}};
            if (second != std::string::npos)
                for (std::string argument : split(rest.substr(second + 1), ";")) {
                    argument = trim(argument);
                    std::size_t equal = argument.find('=');
                    item.arguments.push_back(
                        {argument.substr(0, equal), parse_expression(argument.substr(equal + 1))});
                }
            (keyword == "OBLIGATION" ? stack.back()->obligations : stack.back()->advice)
                .push_back(item);
        }
    }
    out.root = out.elements.front().get();
    return out;
}
