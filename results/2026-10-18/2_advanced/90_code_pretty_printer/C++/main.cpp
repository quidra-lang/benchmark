#include "formatter.hpp"
std::string join(const Lines &values, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += separator;
        out += values[i];
    }
    return out;
}
void append(Lines &to, const Lines &from) { to.insert(to.end(), from.begin(), from.end()); }
struct Profile {
    int width = 0, indent = 0, maxBlank = 0, commentColumn = 0;
    bool allman = false, spaces = false, keywordSpace = false, indentCases = false,
         addBraces = false, removeParens = false;
};
struct Source {
    std::string header, name, profile;
    Lines lines;
};
struct FormatResult {
    Lines lines;
    std::optional<FileError> error;
    DocPtr document, functionDoc;
    std::string functionName;
    int comments = 0;
};
static int attachComments(Lexed &lexed) {
    std::vector<Token *> next(lexed.items.size());
    Token *following = nullptr;
    for (int i = static_cast<int>(lexed.items.size()) - 1; i >= 0; --i) {
        next[i] = following;
        if (lexed.items[i].token)
            following = lexed.items[i].token;
    }
    Token *previous = nullptr;
    int count = 0;
    for (std::size_t i = 0; i < lexed.items.size(); ++i) {
        const Lexeme &item = lexed.items[i];
        if (item.token) {
            previous = item.token;
            continue;
        }
        ++count;
        Comment *comment = item.comment;
        Token *token = next[i];
        if (previous && previous->position.line == comment->position.line &&
            (!token || token->position.line > comment->position.line)) {
            previous->trailing.push_back(comment);
            previous->originalTrailing = true;
        } else {
            comment->own = comment->line || i + 1 == lexed.items.size() ||
                           lexed.items[i + 1].line() > comment->position.line;
            if (!token)
                token = lexed.tokens.back().get();
            token->leading.push_back(comment);
        }
    }
    return count;
}
static void checkComments(const NodePtr &root, const std::vector<std::unique_ptr<Token>> &tokens) {
    std::vector<bool> allowed(tokens.size()), trailing(tokens.size());
    allowed.back() = true;
    std::function<void(const NodePtr &)> walk = [&](const NodePtr &node) {
        if (!node)
            return;
        switch (node->kind) {
        case NodeKind::Program:
            for (const NodePtr &item : node->elements)
                allowed[item->first] = true;
            break;
        case NodeKind::Block:
            allowed[node->close->index] = true;
            for (const NodePtr &statement : node->elements)
                allowed[statement->first] = true;
            break;
        case NodeKind::SwitchBody:
            allowed[node->close->index] = true;
            for (const NodePtr &clause : node->elements) {
                allowed[clause->token->index] = true;
                for (const NodePtr &statement : clause->elements)
                    allowed[statement->first] = true;
            }
            break;
        case NodeKind::If:
        case NodeKind::While:
        case NodeKind::For:
            if (node->body->kind != NodeKind::Block)
                allowed[node->body->first] = true;
            if (node->kind == NodeKind::If && node->elsePart &&
                node->elsePart->kind != NodeKind::Block && node->elsePart->kind != NodeKind::If)
                allowed[node->elsePart->first] = true;
            break;
        case NodeKind::List:
            for (const NodePtr &element : node->elements)
                allowed[element->first] = true;
            if (node->trailing)
                trailing[node->trailing->index] = true;
            break;
        default:
            break;
        }
        for (const NodePtr &child : nodeChildren(*node))
            walk(child);
    };
    walk(root);
    for (const std::unique_ptr<Token> &token : tokens)
        for (Comment *comment : token->leading)
            if (trailing[token->index] || (comment->own && !allowed[token->index]))
                throw FileError{comment->position, "comment not allowed here"};
}
struct Builder {
    Profile profile;
    const std::vector<std::unique_ptr<Token>> &tokens;
    DocPtr firstFunction;
    std::string functionName;
    DocPtr space() const { return stringDoc(profile.spaces ? " " : ""); }
    DocPtr operatorLine() const {
        return marker(profile.spaces ? DocKind::Line : DocKind::Softline);
    }
    DocPtr keywordSpace() const { return stringDoc(profile.keywordSpace ? " " : ""); }
    DocPtr braceSeparator() const {
        return profile.allman ? marker(DocKind::Hardline) : stringDoc(" ");
    }
    DocPtr separator(int blank) const;
    DocPtr comments(const std::vector<Comment *> &comments, std::optional<int> lastBlank) const;
    DocPtr tokenLeading(Token *token, const std::vector<Comment *> &leading) const;
    DocPtr token(Token *token) const;
    DocPtr whole(const NodePtr &root);
    DocPtr list(const NodePtr &node);
    DocPtr block(const NodePtr &node);
    DocPtr body(const NodePtr &node);
    DocPtr declaration(const NodePtr &node);
    DocPtr simple(const NodePtr &node);
    DocPtr statement(const NodePtr &node);
    NodePtr opening(NodePtr node, int required);
    DocPtr postfixDocument(const NodePtr &node);
    DocPtr expression(const NodePtr &node, int required);
};
DocPtr Builder::separator(int blank) const {
    Docs docs;
    for (int i = 0; i <= std::min(blank, profile.maxBlank); ++i)
        docs.push_back(marker(DocKind::Hardline));
    return cat(docs);
}
static int preBlank(Token *token) {
    return token->leading.empty() ? token->blank : token->leading[0]->blank;
}
DocPtr Builder::comments(const std::vector<Comment *> &items, std::optional<int> lastBlank) const {
    Docs docs;
    for (std::size_t i = 0; i < items.size(); ++i) {
        Comment *comment = items[i];
        docs.push_back(stringDoc(comment->value));
        std::optional<int> next =
            i + 1 < items.size() ? std::optional<int>(items[i + 1]->blank) : lastBlank;
        if (next)
            docs.push_back(comment->own ? separator(*next) : stringDoc(" "));
    }
    return cat(docs);
}
static DocPtr trailingPart(Token *token) {
    if (token->trailing.empty())
        return stringDoc("");
    Lines parts;
    for (Comment *comment : token->trailing)
        parts.push_back(comment->value);
    return suffix(join(parts));
}
DocPtr Builder::tokenLeading(Token *value, const std::vector<Comment *> &leading) const {
    return cat({comments(leading, value->blank), stringDoc(value->value), trailingPart(value)});
}
DocPtr Builder::token(Token *value) const {
    return value ? tokenLeading(value, value->leading) : stringDoc("");
}
static std::pair<std::vector<Comment *>, std::vector<Comment *>> splitClosing(Token *token) {
    std::size_t split = 0;
    for (std::size_t i = 0; i < token->leading.size(); ++i)
        if (token->leading[i]->own)
            split = i + 1;
    return {{token->leading.begin(), token->leading.begin() + static_cast<std::ptrdiff_t>(split)},
            {token->leading.begin() + static_cast<std::ptrdiff_t>(split), token->leading.end()}};
}
DocPtr Builder::whole(const NodePtr &root) {
    Docs docs;
    for (std::size_t i = 0; i < root->elements.size(); ++i) {
        const NodePtr &item = root->elements[i];
        if (i)
            docs.push_back(separator(preBlank(tokens[item->first].get())));
        DocPtr doc = statement(item);
        docs.push_back(doc);
        if (item->kind == NodeKind::Function && !firstFunction) {
            firstFunction = doc;
            functionName = item->name->value;
        }
    }
    Token *end = tokens.back().get();
    if (!end->leading.empty()) {
        if (!root->elements.empty())
            docs.push_back(separator(end->leading[0]->blank));
        docs.push_back(comments(end->leading, std::nullopt));
    }
    return cat(docs);
}
DocPtr Builder::list(const NodePtr &node) {
    if (node->elements.empty())
        return cat({token(node->open), token(node->close)});
    DocPtr force = stringDoc("");
    for (int i = node->open->index; i < node->close->index; ++i)
        if (tokens[i]->originalTrailing) {
            force = marker(DocKind::BreakParent);
            break;
        }
    Docs inside{marker(DocKind::Softline)};
    for (std::size_t i = 0; i < node->elements.size(); ++i) {
        if (i) {
            inside.push_back(token(node->commas[i - 1]));
            inside.push_back(marker(DocKind::Line));
        }
        inside.push_back(node->value == "arguments" ? expression(node->elements[i], 0)
                                                    : statement(node->elements[i]));
    }
    if (node->value == "initializer") {
        inside.push_back(ifBreak(",", ""));
        if (node->trailing)
            inside.push_back(trailingPart(node->trailing));
    }
    return group({force, token(node->open), nest(profile.indent, inside), marker(DocKind::Softline),
                  token(node->close)});
}
DocPtr Builder::block(const NodePtr &node) {
    auto [own, inlineComments] = splitClosing(node->close);
    if (node->elements.empty() && own.empty())
        return cat({token(node->open), tokenLeading(node->close, inlineComments)});
    Docs inside{marker(DocKind::Hardline)};
    for (std::size_t i = 0; i < node->elements.size(); ++i) {
        const NodePtr &child = node->elements[i];
        if (i)
            inside.push_back(separator(preBlank(tokens[child->first].get())));
        inside.push_back(statement(child));
    }
    if (!own.empty()) {
        if (!node->elements.empty())
            inside.push_back(separator(own[0]->blank));
        inside.push_back(comments(own, std::nullopt));
    }
    return cat({token(node->open), nest(profile.indent, inside), marker(DocKind::Hardline),
                tokenLeading(node->close, inlineComments)});
}
DocPtr Builder::body(const NodePtr &node) {
    if (node->kind == NodeKind::Block)
        return cat({braceSeparator(), block(node)});
    if (profile.addBraces)
        return cat({braceSeparator(), stringDoc("{"),
                    nest(profile.indent, {marker(DocKind::Hardline), statement(node)}),
                    marker(DocKind::Hardline), stringDoc("}")});
    return nest(profile.indent, {marker(DocKind::Hardline), statement(node)});
}
DocPtr Builder::declaration(const NodePtr &node) {
    Docs docs{token(node->token), stringDoc(" "), token(node->name)};
    for (const NodePtr &dimension : node->dimensions) {
        docs.push_back(token(dimension->open));
        if (dimension->expr)
            docs.push_back(expression(dimension->expr, 0));
        docs.push_back(token(dimension->close));
    }
    if (node->op) {
        docs.push_back(space());
        docs.push_back(token(node->op));
        docs.push_back(space());
        docs.push_back(node->init->kind == NodeKind::List ? list(node->init)
                                                          : expression(node->init, 0));
    }
    docs.push_back(token(node->semi));
    return cat(docs);
}
DocPtr Builder::simple(const NodePtr &node) {
    return node->kind == NodeKind::Assignment
               ? cat({expression(node->left, 0), space(), token(node->op), space(),
                      expression(node->right, 0)})
               : expression(node->expr, 0);
}
DocPtr Builder::statement(const NodePtr &node) {
    switch (node->kind) {
    case NodeKind::Function:
        return cat({token(node->token), stringDoc(" "), token(node->name), list(node->init),
                    marker(DocKind::Hardline), block(node->body)});
    case NodeKind::Parameter:
    case NodeKind::Declaration:
        return declaration(node);
    case NodeKind::List:
        return list(node);
    case NodeKind::Block:
        return block(node);
    case NodeKind::Assignment:
    case NodeKind::Simple:
        return cat({simple(node), token(node->semi)});
    case NodeKind::Return: {
        Docs docs{token(node->token)};
        if (node->expr) {
            docs.push_back(stringDoc(" "));
            docs.push_back(expression(node->expr, 0));
        }
        docs.push_back(token(node->semi));
        return cat(docs);
    }
    case NodeKind::Break:
    case NodeKind::Continue:
        return cat({token(node->token), token(node->semi)});
    case NodeKind::While:
        return cat({token(node->token), keywordSpace(), token(node->open),
                    expression(node->expr, 0), token(node->close), body(node->body)});
    case NodeKind::For: {
        Docs parts;
        if (node->init)
            parts.push_back(node->init->kind == NodeKind::Declaration ? declaration(node->init)
                                                                      : simple(node->init));
        parts.push_back(token(node->semi));
        if (node->condition) {
            parts.push_back(marker(DocKind::Line));
            parts.push_back(expression(node->condition, 0));
        }
        parts.push_back(token(node->semi2));
        if (node->update) {
            parts.push_back(marker(DocKind::Line));
            parts.push_back(simple(node->update));
        }
        return cat({token(node->token), keywordSpace(), token(node->open), group({align(parts)}),
                    token(node->close), body(node->body)});
    }
    case NodeKind::If: {
        Docs docs{token(node->token),        keywordSpace(),     token(node->open),
                  expression(node->expr, 0), token(node->close), body(node->body)};
        if (node->elsePart) {
            docs.push_back(!profile.allman &&
                                   (node->body->kind == NodeKind::Block || profile.addBraces)
                               ? stringDoc(" ")
                               : marker(DocKind::Hardline));
            docs.push_back(token(node->elseToken));
            if (node->elsePart->kind == NodeKind::If) {
                docs.push_back(stringDoc(" "));
                docs.push_back(statement(node->elsePart));
            } else
                docs.push_back(body(node->elsePart));
        }
        return cat(docs);
    }
    case NodeKind::Switch: {
        const NodePtr &switchBody = node->body;
        auto [own, inlineComments] = splitClosing(switchBody->close);
        DocPtr head =
            cat({token(node->token), keywordSpace(), token(node->open), expression(node->expr, 0),
                 token(node->close), braceSeparator(), token(switchBody->open)});
        if (switchBody->elements.empty() && own.empty())
            return cat({head, tokenLeading(switchBody->close, inlineComments)});
        Docs inside{marker(DocKind::Hardline)};
        for (std::size_t i = 0; i < switchBody->elements.size(); ++i) {
            const NodePtr &clause = switchBody->elements[i];
            if (i)
                inside.push_back(separator(preBlank(clause->token)));
            Docs parts{token(clause->token)};
            if (clause->expr) {
                parts.push_back(stringDoc(" "));
                parts.push_back(expression(clause->expr, 0));
            }
            parts.push_back(token(clause->colon));
            if (!clause->elements.empty()) {
                Docs statements{marker(DocKind::Hardline)};
                for (std::size_t j = 0; j < clause->elements.size(); ++j) {
                    const NodePtr &child = clause->elements[j];
                    if (j)
                        statements.push_back(separator(preBlank(tokens[child->first].get())));
                    statements.push_back(statement(child));
                }
                parts.push_back(nest(profile.indent, statements));
            }
            inside.push_back(cat(parts));
        }
        if (!own.empty()) {
            if (!switchBody->elements.empty())
                inside.push_back(separator(own[0]->blank));
            inside.push_back(comments(own, std::nullopt));
        }
        return cat({head, nest(profile.indentCases ? profile.indent : 0, inside),
                    marker(DocKind::Hardline), tokenLeading(switchBody->close, inlineComments)});
    }
    default:
        return expression(node, 0);
    }
}
NodePtr Builder::opening(NodePtr node, int required) {
    if (!profile.removeParens)
        return node;
    while (node->kind == NodeKind::Parenthesized && expressionLevel(node->expr) >= required &&
           node->open->leading.empty() && node->close->leading.empty()) {
        NodePtr inner = node->expr;
        Token *first = tokens[inner->first].get(), *last = tokens[inner->last].get();
        first->trailing.insert(first->trailing.begin(), node->open->trailing.begin(),
                               node->open->trailing.end());
        last->trailing.insert(last->trailing.end(), node->close->trailing.begin(),
                              node->close->trailing.end());
        node->open->trailing.clear();
        node->close->trailing.clear();
        node = inner;
    }
    return node;
}
static bool postfix(const NodePtr &node) {
    return node->kind == NodeKind::Call || node->kind == NodeKind::Index ||
           node->kind == NodeKind::Member;
}
DocPtr Builder::postfixDocument(const NodePtr &node) {
    if (node->kind == NodeKind::Call)
        return list(node->init);
    if (node->kind == NodeKind::Index)
        return cat({token(node->open), expression(node->expr, 0), token(node->close)});
    return cat({token(node->op), token(node->name)});
}
DocPtr Builder::expression(const NodePtr &original, int required) {
    NodePtr node = opening(original, required);
    switch (node->kind) {
    case NodeKind::Atom:
        return token(node->token);
    case NodeKind::Parenthesized:
        return cat({token(node->open), expression(node->expr, 0), token(node->close)});
    case NodeKind::Unary:
        return cat({token(node->op), expression(node->expr, 8)});
    case NodeKind::Binary: {
        int level = expressionLevel(node);
        std::vector<Token *> operators;
        Nodes operands;
        NodePtr head = node;
        while (head->kind == NodeKind::Binary && expressionLevel(head) == level) {
            operators.push_back(head->op);
            operands.push_back(head->right);
            head = opening(head->left, level);
        }
        Docs inside;
        for (int i = static_cast<int>(operators.size()) - 1; i >= 0; --i) {
            inside.push_back(operatorLine());
            inside.push_back(token(operators[i]));
            inside.push_back(space());
            inside.push_back(expression(operands[i], level + 1));
        }
        return group({expression(head, level), nest(profile.indent, inside)});
    }
    case NodeKind::Conditional: {
        Docs inside;
        NodePtr current = node;
        for (;;) {
            inside.push_back(operatorLine());
            inside.push_back(token(current->op));
            inside.push_back(space());
            inside.push_back(expression(current->thenPart, 0));
            inside.push_back(operatorLine());
            inside.push_back(token(current->colon));
            inside.push_back(space());
            NodePtr other = opening(current->elsePart, 0);
            if (other->kind == NodeKind::Conditional) {
                inside.push_back(expression(other->expr, 1));
                current = other;
            } else {
                inside.push_back(expression(other, 0));
                break;
            }
        }
        return group({expression(node->expr, 1), nest(profile.indent, inside)});
    }
    case NodeKind::Call:
    case NodeKind::Index:
    case NodeKind::Member: {
        Nodes operations;
        NodePtr head = node;
        while (postfix(head)) {
            operations.push_back(head);
            head = opening(head->left, 8);
        }
        std::reverse(operations.begin(), operations.end());
        std::vector<Nodes> segments(1);
        for (const NodePtr &operation : operations) {
            if (operation->kind == NodeKind::Member)
                segments.push_back({});
            segments.back().push_back(operation);
        }
        int count = 0, first = -1;
        for (int i = 1; i < static_cast<int>(segments.size()); ++i) {
            bool hasCall = false;
            for (const NodePtr &operation : segments[i])
                if (operation->kind == NodeKind::Call)
                    hasCall = true;
            if (hasCall) {
                ++count;
                if (first < 0)
                    first = i;
            }
        }
        Docs docs{expression(head, 8)};
        if (count < 2) {
            for (const NodePtr &operation : operations)
                docs.push_back(postfixDocument(operation));
            return cat(docs);
        }
        for (int i = 0; i < first; ++i)
            for (const NodePtr &operation : segments[i])
                docs.push_back(postfixDocument(operation));
        Docs inside;
        for (int i = first; i < static_cast<int>(segments.size()); ++i) {
            inside.push_back(marker(DocKind::Softline));
            for (const NodePtr &operation : segments[i])
                inside.push_back(postfixDocument(operation));
        }
        docs.push_back(nest(profile.indent, inside));
        return group(docs);
    }
    default:
        throw std::logic_error("unexpected expression");
    }
}
static FormatResult format(const Lines &source, Profile profile) {
    FormatResult out;
    try {
        Lexed lexed = lex(source);
        out.comments = attachComments(lexed);
        Parser parser{lexed.tokens};
        NodePtr root = parser.program();
        checkComments(root, lexed.tokens);
        Builder builder{profile, lexed.tokens, {}, ""};
        out.document = builder.whole(root);
        out.functionDoc = builder.firstFunction;
        out.functionName = builder.functionName;
        if (!root->elements.empty() || !lexed.tokens.back()->leading.empty())
            out.lines = printDoc(out.document, profile.width, profile.commentColumn);
    } catch (const FileError &error) {
        out.error = error;
    }
    return out;
}
static Lines readLines(const std::string &path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot read " + path);
    Lines out;
    for (std::string line; std::getline(input, line);)
        out.push_back(line);
    return out;
}
static std::map<std::string, Profile> readProfiles() {
    std::map<std::string, Profile> out;
    Profile *profile = nullptr;
    for (const std::string &line : readLines("input/style.txt")) {
        if (line.empty())
            continue;
        if (line[0] == '[') {
            profile = &out[line.substr(1, line.size() - 2)];
            continue;
        }
        std::size_t separator = line.find('=');
        std::string key = line.substr(0, separator), value = line.substr(separator + 1);
        if (key == "width")
            profile->width = std::stoi(value);
        else if (key == "indent")
            profile->indent = std::stoi(value);
        else if (key == "max_blank_lines")
            profile->maxBlank = std::stoi(value);
        else if (key == "comment_column")
            profile->commentColumn = std::stoi(value);
        else if (key == "brace_style")
            profile->allman = value == "allman";
        else if (key == "space_around_operators")
            profile->spaces = value == "yes";
        else if (key == "space_after_keyword")
            profile->keywordSpace = value == "yes";
        else if (key == "indent_case_labels")
            profile->indentCases = value == "yes";
        else if (key == "add_braces")
            profile->addBraces = value == "yes";
        else
            profile->removeParens = value == "yes";
    }
    return out;
}
static std::vector<Source> readSources() {
    std::vector<Source> out;
    for (const std::string &line : readLines("input/sources.txt")) {
        if (line.compare(0, 4, "=== ") == 0) {
            std::istringstream input(line);
            std::string marker, name, profile;
            input >> marker >> name >> profile;
            out.push_back({line, name, profile, {}});
        } else
            out.back().lines.push_back(line);
    }
    return out;
}
static void writeLines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    if (!output)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        output << line << '\n';
    if (!output)
        throw std::runtime_error("cannot write " + name);
}
int main() {
    const std::map<std::string, Profile> profiles = readProfiles();
    Lines formatted, idempotency, diagnostics, trees, changes;
    for (const Source &source : readSources()) {
        Profile profile = profiles.at(source.profile);
        FormatResult result = format(source.lines, profile);
        Lines original;
        for (const std::string &line : source.lines)
            original.push_back(trimRight(line));
        formatted.push_back(source.header);
        trees.push_back("=== " + source.name);
        changes.push_back("=== " + source.name);
        if (result.error) {
            const FileError &error = *result.error;
            append(formatted, original);
            idempotency.push_back(source.name + ": skipped (syntax error)");
            diagnostics.push_back(text(source.name, ":", error.position.line, ":",
                                       error.position.column, ": error: ", error.message));
            trees.push_back("syntax error");
            changes.push_back("skipped (syntax error)");
            continue;
        }
        append(formatted, result.lines);
        FormatResult second = format(result.lines, profile);
        if (second.error) {
            const FileError &error = *second.error;
            idempotency.push_back(text(source.name,
                                       ": unstable (second pass: ", error.position.line, ":",
                                       error.position.column, ": ", error.message, ")"));
        } else {
            int difference = -1;
            std::size_t common = std::min(result.lines.size(), second.lines.size());
            for (std::size_t i = 0; i < common; ++i)
                if (result.lines[i] != second.lines[i]) {
                    difference = static_cast<int>(i + 1);
                    break;
                }
            if (difference < 0 && result.lines.size() != second.lines.size())
                difference = static_cast<int>(common + 1);
            idempotency.push_back(difference < 0
                                      ? source.name + ": stable"
                                      : text(source.name, ": unstable at line ", difference));
        }
        int longest = 0;
        for (std::size_t i = 0; i < result.lines.size(); ++i) {
            longest = std::max(longest, static_cast<int>(result.lines[i].size()));
            if (static_cast<int>(result.lines[i].size()) > profile.width)
                diagnostics.push_back(text(source.name, ":", i + 1, ": warning: line too long (",
                                           result.lines[i].size(), " > ", profile.width, ")"));
        }
        GroupMetrics metrics = groupMetrics(result.document);
        trees.push_back(text("metrics lines=", result.lines.size(), " longest=", longest,
                             " comments=", result.comments, " groups=", metrics.groups,
                             " broken=", metrics.broken, " forced=", metrics.forced));
        if (!result.functionDoc)
            trees.push_back("no function");
        else {
            trees.push_back("function " + result.functionName);
            append(trees, docTree(result.functionDoc));
        }
        append(changes, diffLines(original, result.lines));
    }
    if (diagnostics.empty())
        diagnostics.push_back("no diagnostics");
    std::filesystem::create_directories("output");
    writeLines("formatted.txt", formatted);
    writeLines("idempotency.txt", idempotency);
    writeLines("diagnostics.txt", diagnostics);
    writeLines("doc_tree.txt", trees);
    writeLines("changes.txt", changes);
}
