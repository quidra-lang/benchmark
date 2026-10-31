#include "formula.h"
void node_push(NodeList *nodes, Node *node) {
    if (nodes->count == nodes->capacity) {
        nodes->capacity = nodes->capacity ? nodes->capacity * 2 : 8;
        nodes->data = resize(nodes->data, (size_t)nodes->capacity * sizeof *nodes->data);
    }
    nodes->data[nodes->count++] = node;
}
Node *node_new(NodePool *pool, Kind kind) {
    Node *out = allocate(sizeof *out);
    out->kind = kind;
    out->value = out->left = out->right = "";
    node_push(&pool->nodes, out);
    return out;
}
void node_pool_free(NodePool *pool) {
    for (int i = 0; i < pool->nodes.count; ++i) {
        Node *node = pool->nodes.data[i];
        free(node->items.data);
        for (int j = 0; j < node->rows.count; ++j)
            free(node->rows.data[j].data);
        free(node->rows.data);
        free(node);
    }
    free(pool->nodes.data);
}
static Node *collapse(Parser *parser, NodeList nodes) {
    if (nodes.count == 1) {
        Node *out = nodes.data[0];
        free(nodes.data);
        return out;
    }
    Node *out = node_new(parser->pool, K_ROW);
    out->items = nodes;
    return out;
}
Issue check_braces(const TokenList *tokens) {
    IntList stack = {0};
    Issue out = {0};
    for (int i = 0; i < tokens->count; ++i) {
        const Token *token = &tokens->data[i];
        if (token->kind == K_OPEN_BRACE)
            int_push(&stack, token->column);
        else if (token->kind == K_CLOSE_BRACE) {
            if (!stack.count) {
                out = (Issue){token->column, copy_text("unmatched }")};
                break;
            }
            --stack.count;
        }
    }
    if (!out.message && stack.count)
        out = (Issue){stack.data[stack.count - 1], copy_text("unclosed {")};
    int_free(&stack);
    return out;
}
Token parser_peek(const Parser *parser) {
    return parser->position < parser->tokens->count ? parser->tokens->data[parser->position]
                                                    : (Token){K_EOF, "", parser->end};
}
static Token parser_read(Parser *parser) {
    Token token = parser_peek(parser);
    if (parser->position < parser->tokens->count)
        ++parser->position;
    return token;
}
static void fail(Parser *parser, int column, char *message) {
    if (!parser->error.message)
        parser->error = (Issue){column, message};
    else
        free(message);
}
void parser_unexpected(Parser *parser, Token token) {
    const char *message = token.kind == K_RIGHT ? "unexpected \\right"
                          : token.kind == K_END ? "unexpected \\end"
                          : token.kind == K_AMP ? "misplaced &"
                                                : "misplaced \\\\";
    fail(parser, token.column, copy_text(message));
}
static bool terminator(Kind kind) {
    return kind == K_CLOSE_BRACE || kind == K_AMP || kind == K_NEWLINE || kind == K_RIGHT ||
           kind == K_END || kind == K_EOF;
}
static Node *element(Parser *parser);
static Node *nucleus(Parser *parser);
NodeList parse_elements(Parser *parser, bool top, bool index) {
    NodeList out = {0};
    while (!parser->error.message) {
        Token token = parser_peek(parser);
        if (terminator(token.kind) ||
            (index && token.kind == K_SYMBOL && !strcmp(token.value, "]")))
            break;
        if (token.kind == K_TAG || token.kind == K_LABEL) {
            const char *name = token.kind == K_TAG ? "tag" : "label";
            if (!top) {
                fail(parser, token.column, format_text("misplaced \\%s", name));
                break;
            }
            Token **target = token.kind == K_TAG ? &parser->tag : &parser->label;
            if (*target) {
                fail(parser, token.column, format_text("duplicate \\%s", name));
                break;
            }
            *target = &parser->tokens->data[parser->position];
            parser_read(parser);
            continue;
        }
        node_push(&out, element(parser));
    }
    return out;
}
static Node *argument(Parser *parser, const char *name) {
    if (parser->error.message)
        return node_new(parser->pool, K_ROW);
    Token token = parser_peek(parser);
    Kind kind = token.kind;
    if (kind == K_IDENTIFIER || kind == K_NUMBER || kind == K_SYMBOL || kind == K_COMMAND ||
        kind == K_TEXT || kind == K_EQREF || kind == K_OPEN_BRACE || kind == K_FRAC ||
        kind == K_BINOM || kind == K_OVERSET || kind == K_UNDERSET || kind == K_SQRT ||
        kind == K_ACCENT)
        return nucleus(parser);
    fail(parser, token.column, format_text("missing argument for %s", name));
    return node_new(parser->pool, K_ROW);
}
static Node *element(Parser *parser) {
    Token token = parser_peek(parser);
    Node *base = token.kind == K_SUP || token.kind == K_SUB ? node_new(parser->pool, K_ROW)
                                                            : nucleus(parser),
         *sub = NULL, *sup = NULL;
    while (!parser->error.message &&
           (parser_peek(parser).kind == K_SUP || parser_peek(parser).kind == K_SUB)) {
        token = parser_read(parser);
        if (token.kind == K_SUP) {
            if (sup) {
                fail(parser, token.column, copy_text("double superscript"));
                break;
            }
            sup = argument(parser, "^");
        } else {
            if (sub) {
                fail(parser, token.column, copy_text("double subscript"));
                break;
            }
            sub = argument(parser, "_");
        }
    }
    if (!sub && !sup)
        return base;
    Node *out = node_new(parser->pool, K_SCRIPT);
    out->base = base;
    out->sub = sub;
    out->sup = sup;
    return out;
}
static const char *delimiter(Parser *parser) {
    Token token = parser_read(parser);
    if ((token.kind == K_SYMBOL && contains_word("( ) [ ] | .", token.value)) ||
        (token.kind == K_COMMAND && (!strcmp(token.value, "\\{") || !strcmp(token.value, "\\}"))))
        return token.value;
    fail(parser, token.column, copy_text("invalid delimiter"));
    return ".";
}
static void row_push(NodeRows *rows, NodeList row) {
    if (rows->count == rows->capacity) {
        rows->capacity = rows->capacity ? rows->capacity * 2 : 4;
        rows->data = resize(rows->data, (size_t)rows->capacity * sizeof *rows->data);
    }
    rows->data[rows->count++] = row;
}
static Node *nucleus(Parser *parser) {
    if (parser->error.message)
        return node_new(parser->pool, K_ROW);
    Token token = parser_read(parser);
    Node *out = node_new(parser->pool, token.kind);
    out->value = token.value;
    out->column = token.column;
    switch (token.kind) {
    case K_IDENTIFIER:
    case K_NUMBER:
    case K_SYMBOL:
    case K_COMMAND:
    case K_TEXT:
        return out;
    case K_EQREF:
        out->kind = K_REFERENCE;
        return out;
    case K_OPEN_BRACE: {
        NodeList nodes = parse_elements(parser, false, false);
        if (!parser->error.message) {
            if (parser_peek(parser).kind != K_CLOSE_BRACE)
                parser_unexpected(parser, parser_peek(parser));
            else
                parser_read(parser);
        }
        return collapse(parser, nodes);
    }
    case K_FRAC:
    case K_BINOM:
    case K_OVERSET:
    case K_UNDERSET: {
        const char *name = token.kind == K_FRAC      ? "\\frac"
                           : token.kind == K_BINOM   ? "\\binom"
                           : token.kind == K_OVERSET ? "\\overset"
                                                     : "\\underset";
        node_push(&out->items, argument(parser, name));
        node_push(&out->items, argument(parser, name));
        return out;
    }
    case K_SQRT: {
        Token next = parser_peek(parser);
        if (next.kind == K_SYMBOL && !strcmp(next.value, "[")) {
            Token open = parser_read(parser);
            NodeList nodes = parse_elements(parser, false, true);
            next = parser_peek(parser);
            if (!parser->error.message) {
                if (next.kind != K_SYMBOL || strcmp(next.value, "]"))
                    fail(parser, open.column, copy_text("missing ]"));
                else
                    parser_read(parser);
            }
            out->kind = K_ROOT;
            node_push(&out->items, collapse(parser, nodes));
        }
        node_push(&out->items, argument(parser, "\\sqrt"));
        return out;
    }
    case K_ACCENT: {
        char *name = format_text("\\%s", token.value);
        node_push(&out->items, argument(parser, name));
        free(name);
        return out;
    }
    case K_LEFT: {
        out->kind = K_DELIM;
        out->left = delimiter(parser);
        NodeList body = parse_elements(parser, false, false);
        if (!parser->error.message) {
            if (parser_peek(parser).kind != K_RIGHT)
                fail(parser, token.column, copy_text("missing \\right"));
            else {
                out->right_column = parser_read(parser).column;
                out->right = delimiter(parser);
            }
        }
        node_push(&out->items, collapse(parser, body));
        return out;
    }
    case K_BEGIN: {
        out->kind = K_MATRIX;
        row_push(&out->rows, (NodeList){0});
        while (!parser->error.message) {
            NodeList cells = parse_elements(parser, false, false);
            node_push(&out->rows.data[out->rows.count - 1], collapse(parser, cells));
            if (parser->error.message)
                break;
            Token end = parser_read(parser);
            if (end.kind == K_AMP)
                continue;
            if (end.kind == K_NEWLINE) {
                row_push(&out->rows, (NodeList){0});
                continue;
            }
            if (end.kind == K_END) {
                if (strcmp(end.value, token.value))
                    fail(parser, end.column, copy_text("mismatched \\end"));
                break;
            }
            fail(parser, token.column, copy_text("missing \\end"));
        }
        if (out->rows.count > 1) {
            NodeList *last = &out->rows.data[out->rows.count - 1];
            if (last->count == 1 && last->data[0]->kind == K_ROW && !last->data[0]->items.count) {
                free(last->data);
                --out->rows.count;
            }
        }
        int width = 0;
        for (int i = 0; i < out->rows.count; ++i)
            if (out->rows.data[i].count > width)
                width = out->rows.data[i].count;
        for (int i = 0; i < out->rows.count; ++i)
            while (out->rows.data[i].count < width)
                node_push(&out->rows.data[i], node_new(parser->pool, K_ROW));
        return out;
    }
    default:
        return out;
    }
}
