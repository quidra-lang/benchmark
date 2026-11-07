#include "formatter.hpp"
struct Command {
    int indent;
    bool flat;
    DocPtr doc;
};
static void pushChildren(std::vector<Command> &stack, const Command &command) {
    for (auto child = command.doc->children.rbegin(); child != command.doc->children.rend();
         ++child)
        stack.push_back({command.indent, command.flat, *child});
}
static bool fits(int remaining, Command first, const std::vector<Command> &original) {
    if (remaining < 0)
        return false;
    std::vector<Command> stack{std::move(first)};
    int unused = static_cast<int>(original.size()) - 1;
    while (!stack.empty() || unused >= 0) {
        if (stack.empty())
            stack.push_back(original[unused--]);
        Command command = std::move(stack.back());
        stack.pop_back();
        const DocPtr &doc = command.doc;
        switch (doc->kind) {
        case DocKind::Text:
            remaining -= static_cast<int>(doc->value.size());
            break;
        case DocKind::IfBreak:
            remaining -= static_cast<int>((command.flat ? doc->other : doc->value).size());
            break;
        case DocKind::Line:
            if (!command.flat)
                return true;
            --remaining;
            break;
        case DocKind::Softline:
            if (!command.flat)
                return true;
            break;
        case DocKind::Hardline:
            return true;
        case DocKind::Concat:
            pushChildren(stack, command);
            break;
        case DocKind::Group:
            stack.push_back({command.indent, doc->forced ? false : command.flat, doc->children[0]});
            break;
        case DocKind::Nest:
        case DocKind::Align:
            stack.push_back({command.indent, command.flat, doc->children[0]});
            break;
        default:
            break;
        }
        if (remaining < 0)
            return false;
    }
    return true;
}
Lines printDoc(const DocPtr &document, int width, int commentColumn) {
    Lines lines, pending;
    std::string current;
    int column = 0;
    std::vector<Command> stack{{0, false, document}};
    const auto finalize = [&]() {
        std::string line = trimRight(current);
        if (!pending.empty()) {
            std::string comments = join(pending);
            if (commentColumn > 0 && static_cast<int>(line.size()) < commentColumn - 1 &&
                commentColumn - 1 + static_cast<int>(comments.size()) <= width)
                line += std::string(commentColumn - 1 - line.size(), ' ') + comments;
            else
                line += " " + comments;
        }
        pending.clear();
        lines.push_back(std::move(line));
    };
    while (!stack.empty()) {
        Command command = std::move(stack.back());
        stack.pop_back();
        DocPtr doc = command.doc;
        bool newline = false;
        switch (doc->kind) {
        case DocKind::Text:
            current += doc->value;
            column += static_cast<int>(doc->value.size());
            break;
        case DocKind::IfBreak: {
            const std::string &value = command.flat ? doc->other : doc->value;
            current += value;
            column += static_cast<int>(value.size());
            break;
        }
        case DocKind::Line:
            if (command.flat) {
                current += ' ';
                ++column;
            } else
                newline = true;
            break;
        case DocKind::Softline:
            newline = !command.flat;
            break;
        case DocKind::Hardline:
            newline = true;
            break;
        case DocKind::Concat:
            pushChildren(stack, command);
            break;
        case DocKind::Nest:
            stack.push_back({command.indent + doc->number, command.flat, doc->children[0]});
            break;
        case DocKind::Align:
            stack.push_back({column, command.flat, doc->children[0]});
            break;
        case DocKind::Suffix:
            pending.push_back(doc->value);
            break;
        case DocKind::Group: {
            bool flat = true;
            doc->mode = Mode::Flat;
            if (!command.flat) {
                if (doc->forced) {
                    flat = false;
                    doc->mode = Mode::Forced;
                } else if (!fits(width - column, {command.indent, true, doc->children[0]}, stack)) {
                    flat = false;
                    doc->mode = Mode::Break;
                }
            }
            stack.push_back({command.indent, flat, doc->children[0]});
            break;
        }
        default:
            break;
        }
        if (newline) {
            finalize();
            current = std::string(command.indent, ' ');
            column = command.indent;
        }
    }
    finalize();
    return lines;
}
