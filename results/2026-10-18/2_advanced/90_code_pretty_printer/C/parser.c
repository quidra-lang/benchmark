#include "formatter.h"
void nodes_push(Nodes *nodes, Node *node) {
    if (nodes->count == nodes->capacity) {
        nodes->capacity = nodes->capacity ? nodes->capacity * 2 : 8;
        nodes->data = resize(nodes->data, (size_t)nodes->capacity * sizeof *nodes->data);
    }
    nodes->data[nodes->count++] = node;
}
Nodes node_children(const Node *node) {
    Nodes out = {0};
    Node *fields[] = {node->expr, node->left, node->right,     node->then_part, node->else_part,
                      node->body, node->init, node->condition, node->update};
    for (int i = 0; i < 9; ++i)
        if (fields[i])
            nodes_push(&out, fields[i]);
    for (int i = 0; i < node->elements.count; ++i)
        nodes_push(&out, node->elements.data[i]);
    for (int i = 0; i < node->dimensions.count; ++i)
        nodes_push(&out, node->dimensions.data[i]);
    return out;
}
bool type_name(const Token *token) { return word_in("int float bool string void", token->value); }
int precedence(const char *op) {
    if (!strcmp(op, "||"))
        return 1;
    if (!strcmp(op, "&&"))
        return 2;
    if (!strcmp(op, "==") || !strcmp(op, "!="))
        return 3;
    if (word_in("< <= > >=", op))
        return 4;
    if (!strcmp(op, "+") || !strcmp(op, "-"))
        return 5;
    if (word_in("* / %", op))
        return 6;
    return 0;
}
int expression_level(const Node *node) {
    if (node->kind == N_CONDITIONAL)
        return 0;
    if (node->kind == N_BINARY)
        return precedence(node->op->value);
    if (node->kind == N_UNARY)
        return 7;
    return 8;
}
static Node *make_node(Parser *parser, NodeKind kind) {
    Node *out = allocate(sizeof *out);
    out->kind = kind;
    out->value = "";
    nodes_push(&parser->pool.nodes, out);
    return out;
}
static Token *peek(const Parser *parser) {
    int last = parser->tokens->count - 1;
    return parser->tokens->data[parser->position < last ? parser->position : last];
}
static Token *read_token(Parser *parser) {
    Token *out = peek(parser);
    if (parser->position < parser->tokens->count - 1)
        ++parser->position;
    return out;
}
static void fail(Parser *parser, const char *expected) {
    if (parser->error.message)
        return;
    Token *token = peek(parser);
    char *actual =
        token->kind == TOKEN_END ? copy_text("end of file") : format_text("'%s'", token->value);
    parser->error =
        (FileError){token->position, format_text("expected %s, found %s", expected, actual)};
    free(actual);
}
static Token *take(Parser *parser, const char *value) {
    if (strcmp(peek(parser)->value, value)) {
        char *expected = format_text("'%s'", value);
        fail(parser, expected);
        free(expected);
        return peek(parser);
    }
    return read_token(parser);
}
static Token *take_type(Parser *parser) {
    if (!type_name(peek(parser))) {
        fail(parser, "type");
        return peek(parser);
    }
    return read_token(parser);
}
static Token *identifier(Parser *parser) {
    if (peek(parser)->kind != TOKEN_IDENTIFIER) {
        fail(parser, "identifier");
        return peek(parser);
    }
    return read_token(parser);
}
static Node *mark(Parser *parser, Node *node, int start) {
    node->first = start;
    node->last = parser->position - 1 > start ? parser->position - 1 : start;
    return node;
}
static Node *parse_list(Parser *parser, const char *kind, const char *open, const char *close,
                        bool trailing);
static Node *parameter(Parser *parser);
static Node *declaration(Parser *parser, Token *type, Token *name, int start, bool semi);
static Node *initializer(Parser *parser);
static Node *block(Parser *parser);
static Node *statement(Parser *parser);
static Node *simple(Parser *parser);
static Node *expression(Parser *parser);
static Node *binary(Parser *parser, int level);
static Node *unary(Parser *parser);
Node *parse_program(Parser *parser) {
    Node *out = make_node(parser, N_PROGRAM);
    while (!parser->error.message && peek(parser)->kind != TOKEN_END) {
        int start = parser->position;
        Token *type = take_type(parser), *name = identifier(parser);
        if (parser->error.message)
            break;
        if (!strcmp(peek(parser)->value, "(")) {
            Node *node = make_node(parser, N_FUNCTION);
            node->token = type;
            node->name = name;
            node->init = parse_list(parser, "parameters", "(", ")", false);
            node->body = block(parser);
            nodes_push(&out->elements, mark(parser, node, start));
        } else
            nodes_push(&out->elements, declaration(parser, type, name, start, true));
    }
    return out;
}
static Node *parse_list(Parser *parser, const char *kind, const char *open, const char *close,
                        bool trailing) {
    int start = parser->position;
    Node *out = make_node(parser, N_LIST);
    out->value = kind;
    out->open = take(parser, open);
    if (strcmp(peek(parser)->value, close) && !parser->error.message)
        while (!parser->error.message) {
            Node *child = !strcmp(kind, "parameters")    ? parameter(parser)
                          : !strcmp(kind, "initializer") ? initializer(parser)
                                                         : expression(parser);
            nodes_push(&out->elements, child);
            if (strcmp(peek(parser)->value, ","))
                break;
            Token *comma = read_token(parser);
            if (trailing && !strcmp(peek(parser)->value, close)) {
                out->trailing = comma;
                break;
            }
            tokens_push(&out->commas, comma);
        }
    out->close = take(parser, close);
    return mark(parser, out, start);
}
static Node *parameter(Parser *parser) {
    int start = parser->position;
    Node *out = make_node(parser, N_PARAMETER);
    out->token = take_type(parser);
    out->name = identifier(parser);
    while (!parser->error.message && !strcmp(peek(parser)->value, "[")) {
        int begin = parser->position;
        Node *dimension = make_node(parser, N_DIMENSION);
        dimension->open = read_token(parser);
        dimension->close = take(parser, "]");
        nodes_push(&out->dimensions, mark(parser, dimension, begin));
    }
    return mark(parser, out, start);
}
static Node *declaration(Parser *parser, Token *type, Token *name, int start, bool semi) {
    Node *out = make_node(parser, N_DECLARATION);
    out->token = type;
    out->name = name;
    while (!parser->error.message && !strcmp(peek(parser)->value, "[")) {
        int begin = parser->position;
        Node *dimension = make_node(parser, N_DIMENSION);
        dimension->open = read_token(parser);
        if (strcmp(peek(parser)->value, "]"))
            dimension->expr = expression(parser);
        dimension->close = take(parser, "]");
        nodes_push(&out->dimensions, mark(parser, dimension, begin));
    }
    if (!parser->error.message && !strcmp(peek(parser)->value, "=")) {
        out->op = read_token(parser);
        out->init = initializer(parser);
    }
    if (semi)
        out->semi = take(parser, ";");
    return mark(parser, out, start);
}
static Node *initializer(Parser *parser) {
    return !strcmp(peek(parser)->value, "{") ? parse_list(parser, "initializer", "{", "}", true)
                                             : expression(parser);
}
static Node *block(Parser *parser) {
    int start = parser->position;
    Node *out = make_node(parser, N_BLOCK);
    out->open = take(parser, "{");
    while (!parser->error.message && strcmp(peek(parser)->value, "}") &&
           peek(parser)->kind != TOKEN_END)
        nodes_push(&out->elements, statement(parser));
    out->close = take(parser, "}");
    return mark(parser, out, start);
}
static Node *statement(Parser *parser) {
    int start = parser->position;
    Token *token = peek(parser);
    if (!strcmp(token->value, "{"))
        return block(parser);
    if (type_name(token)) {
        Token *type = read_token(parser), *name = identifier(parser);
        return declaration(parser, type, name, start, true);
    }
    Node *out = make_node(parser, N_SIMPLE);
    out->token = read_token(parser);
    if (!strcmp(token->value, "if") || !strcmp(token->value, "while")) {
        out->kind = !strcmp(token->value, "if") ? N_IF : N_WHILE;
        out->open = take(parser, "(");
        out->expr = expression(parser);
        out->close = take(parser, ")");
        if (!parser->error.message)
            out->body = statement(parser);
        if (out->kind == N_IF && !parser->error.message && !strcmp(peek(parser)->value, "else")) {
            out->else_token = read_token(parser);
            out->else_part = statement(parser);
        }
    } else if (!strcmp(token->value, "for")) {
        out->kind = N_FOR;
        out->open = take(parser, "(");
        if (!parser->error.message && strcmp(peek(parser)->value, ";")) {
            if (type_name(peek(parser))) {
                int begin = parser->position;
                Token *type = read_token(parser), *name = identifier(parser);
                out->init = declaration(parser, type, name, begin, false);
            } else
                out->init = simple(parser);
        }
        out->semi = take(parser, ";");
        if (!parser->error.message && strcmp(peek(parser)->value, ";"))
            out->condition = expression(parser);
        out->semi2 = take(parser, ";");
        if (!parser->error.message && strcmp(peek(parser)->value, ")"))
            out->update = simple(parser);
        out->close = take(parser, ")");
        if (!parser->error.message)
            out->body = statement(parser);
    } else if (!strcmp(token->value, "switch")) {
        out->kind = N_SWITCH;
        out->open = take(parser, "(");
        out->expr = expression(parser);
        out->close = take(parser, ")");
        int begin = parser->position;
        Node *body = make_node(parser, N_SWITCH_BODY);
        body->open = take(parser, "{");
        while (!parser->error.message &&
               (!strcmp(peek(parser)->value, "case") || !strcmp(peek(parser)->value, "default"))) {
            int clause_start = parser->position;
            Node *clause = make_node(parser, N_CLAUSE);
            clause->token = read_token(parser);
            if (!strcmp(clause->token->value, "case"))
                clause->expr = expression(parser);
            clause->colon = take(parser, ":");
            while (!parser->error.message && !word_in("case default }", peek(parser)->value) &&
                   peek(parser)->kind != TOKEN_END)
                nodes_push(&clause->elements, statement(parser));
            nodes_push(&body->elements, mark(parser, clause, clause_start));
        }
        body->close = take(parser, "}");
        out->body = mark(parser, body, begin);
    } else if (!strcmp(token->value, "return")) {
        out->kind = N_RETURN;
        if (!parser->error.message && strcmp(peek(parser)->value, ";"))
            out->expr = expression(parser);
        out->semi = take(parser, ";");
    } else if (!strcmp(token->value, "break") || !strcmp(token->value, "continue")) {
        out->kind = !strcmp(token->value, "break") ? N_BREAK : N_CONTINUE;
        out->semi = take(parser, ";");
    } else {
        parser->position = start;
        out = simple(parser);
        out->semi = take(parser, ";");
    }
    return mark(parser, out, start);
}
static Node *simple(Parser *parser) {
    int start = parser->position;
    Node *left = expression(parser), *out = make_node(parser, N_SIMPLE);
    out->expr = left;
    if (!parser->error.message && word_in("= += -= *= /= %=", peek(parser)->value)) {
        out = make_node(parser, N_ASSIGNMENT);
        out->left = left;
        out->op = read_token(parser);
        out->right = expression(parser);
    }
    return mark(parser, out, start);
}
static Node *expression(Parser *parser) {
    int start = parser->position;
    Node *out = binary(parser, 1);
    if (!parser->error.message && !strcmp(peek(parser)->value, "?")) {
        Node *node = make_node(parser, N_CONDITIONAL);
        node->expr = out;
        node->op = read_token(parser);
        node->then_part = expression(parser);
        node->colon = take(parser, ":");
        node->else_part = expression(parser);
        out = mark(parser, node, start);
    }
    return out;
}
static Node *binary(Parser *parser, int level) {
    if (level == 7)
        return unary(parser);
    Node *left = binary(parser, level + 1);
    while (!parser->error.message && precedence(peek(parser)->value) == level) {
        Node *out = make_node(parser, N_BINARY);
        out->left = left;
        out->op = read_token(parser);
        out->right = binary(parser, level + 1);
        out->first = left->first;
        out->last = out->right->last;
        left = out;
    }
    return left;
}
static Node *unary(Parser *parser) {
    int start = parser->position;
    if (parser->error.message) {
        Node *out = make_node(parser, N_ATOM);
        out->token = peek(parser);
        out->first = out->last = start;
        return out;
    }
    if (!strcmp(peek(parser)->value, "-") || !strcmp(peek(parser)->value, "!")) {
        Node *out = make_node(parser, N_UNARY);
        out->op = read_token(parser);
        out->expr = unary(parser);
        return mark(parser, out, start);
    }
    Token *token = peek(parser);
    Node *out;
    if (token->kind == TOKEN_IDENTIFIER || token->kind == TOKEN_NUMBER ||
        token->kind == TOKEN_STRING || !strcmp(token->value, "true") ||
        !strcmp(token->value, "false")) {
        out = make_node(parser, N_ATOM);
        out->token = read_token(parser);
        mark(parser, out, start);
    } else if (!strcmp(token->value, "(")) {
        out = make_node(parser, N_PAREN);
        out->open = read_token(parser);
        out->expr = expression(parser);
        out->close = take(parser, ")");
        mark(parser, out, start);
    } else {
        fail(parser, "expression");
        out = make_node(parser, N_ATOM);
        out->token = token;
        out->first = out->last = start;
        return out;
    }
    while (!parser->error.message) {
        if (!strcmp(peek(parser)->value, "(")) {
            Node *node = make_node(parser, N_CALL);
            node->left = out;
            node->init = parse_list(parser, "arguments", "(", ")", false);
            out = mark(parser, node, start);
        } else if (!strcmp(peek(parser)->value, "[")) {
            Node *node = make_node(parser, N_INDEX);
            node->left = out;
            node->open = read_token(parser);
            node->expr = expression(parser);
            node->close = take(parser, "]");
            out = mark(parser, node, start);
        } else if (!strcmp(peek(parser)->value, ".")) {
            Node *node = make_node(parser, N_MEMBER);
            node->left = out;
            node->op = read_token(parser);
            node->name = identifier(parser);
            out = mark(parser, node, start);
        } else
            break;
    }
    return out;
}
void parser_free(Parser *parser) {
    for (int i = 0; i < parser->pool.nodes.count; ++i) {
        Node *node = parser->pool.nodes.data[i];
        free(node->elements.data);
        free(node->dimensions.data);
        free(node->commas.data);
        free(node);
    }
    free(parser->pool.nodes.data);
    free(parser->error.message);
}
