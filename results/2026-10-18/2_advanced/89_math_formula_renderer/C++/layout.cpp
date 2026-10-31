#include "formula.hpp"
static ElementTypes elementTypes(const Node &node) {
    Type type = Type::Ordinary;
    if (node.kind == Kind::Symbol) {
        static const std::map<std::string, Type> types{
            {"+", Type::Binary},      {"-", Type::Binary},     {"*", Type::Binary},
            {"=", Type::Relation},    {"<", Type::Relation},   {">", Type::Relation},
            {":", Type::Relation},    {"(", Type::Open},       {"[", Type::Open},
            {")", Type::Close},       {"]", Type::Close},      {"!", Type::Close},
            {",", Type::Punctuation}, {";", Type::Punctuation}};
        auto found = types.find(node.value);
        if (found != types.end())
            type = found->second;
    } else if (node.kind == Kind::Command)
        type = symbolCommands().at(node.value).type;
    else if (node.kind == Kind::Delimited)
        return {Type::Open, Type::Close};
    else if (node.kind == Kind::Script)
        return elementTypes(*node.base);
    else if (node.kind == Kind::Overset || node.kind == Kind::Underset)
        return elementTypes(*node.items[1]);
    return {type, type};
}
static bool wordElement(const Node &node) {
    if (node.kind == Kind::Script)
        return wordElement(*node.base);
    return node.kind == Kind::Command &&
           (greekName(node.value.substr(1)) || node.value == "\\infty");
}
static bool alphanumeric(const Node &node) {
    if (node.kind == Kind::Identifier || node.kind == Kind::Number || wordElement(node))
        return true;
    if (node.kind == Kind::Script)
        return alphanumeric(*node.base);
    return node.kind == Kind::Accent && containsWord("overline hat vec dot tilde", node.value) &&
           alphanumeric(*node.items[0]);
}
Spacing spacing(const Nodes &nodes, bool script, const Params &params) {
    Spacing out;
    for (const NodePtr &node : nodes)
        out.types.push_back(elementTypes(*node));
    for (std::size_t i = 0; i < out.types.size(); ++i) {
        Type previous = i ? out.types[i - 1].right : Type::Ordinary;
        if (out.types[i].left == Type::Binary &&
            (!i || previous == Type::Binary || previous == Type::Operator ||
             previous == Type::Relation || previous == Type::Open || previous == Type::Punctuation))
            out.types[i] = {Type::Ordinary, Type::Ordinary};
        Type current = out.types[i].left;
        if (i &&
            (current == Type::Relation || current == Type::Close || current == Type::Punctuation) &&
            out.types[i - 1].right == Type::Binary)
            out.types[i - 1] = {Type::Ordinary, Type::Ordinary};
    }
    if (!out.types.empty() && out.types.back().right == Type::Binary)
        out.types.back() = {Type::Ordinary, Type::Ordinary};
    static const char table[7][8] = {"01BR000", "11-R000", "BB--B--", "RR-0R00",
                                     "00-0000", "01BR000", "PP-PPPP"};
    for (std::size_t i = 0; i + 1 < nodes.size(); ++i) {
        int gap = 0;
        if (alphanumeric(*nodes[i]) && alphanumeric(*nodes[i + 1]) &&
            (wordElement(*nodes[i]) || wordElement(*nodes[i + 1])))
            gap = 1;
        else {
            char entry = table[static_cast<int>(out.types[i].right)]
                              [static_cast<int>(out.types[i + 1].left)];
            if (entry == '1')
                gap = 1;
            if (!script) {
                if (entry == 'B')
                    gap = params.binSpace;
                else if (entry == 'R')
                    gap = params.relSpace;
                else if (entry == 'P')
                    gap = params.punctSpace;
            }
        }
        out.gaps.push_back(gap);
    }
    return out;
}
BoxPtr rowBox(const std::vector<BoxPtr> &children, const std::vector<int> &gaps,
              const std::string &description, const Lines &roles) {
    int ascent = 0, descent = 0, width = 0;
    for (const BoxPtr &child : children) {
        ascent = std::max(ascent, child->baseline);
        descent = std::max(descent, child->descent());
        width += child->width;
    }
    for (int gap : gaps)
        width += gap;
    BoxPtr out = newBox(width, ascent + descent + 1, ascent, description);
    int x = 0;
    for (std::size_t i = 0; i < children.size(); ++i) {
        out->add(children[i], x, ascent - children[i]->baseline, roles.empty() ? "" : roles[i]);
        x += children[i]->width;
        if (i < gaps.size())
            x += gaps[i];
    }
    return out;
}
