#include "formatter.h"
static void append_owned(TextLines *to, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(to, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
typedef struct {
    int width, indent, max_blank, comment_column;
    bool allman, spaces, keyword_space, indent_cases, add_braces, remove_parens;
} Profile;
typedef struct {
    char name[17];
    Profile profile;
} NamedProfile;
typedef struct {
    char *header;
    char name[33], profile[17];
    TextLines lines;
} Source;
typedef struct {
    TextLines lines;
    FileError error;
    DocPool pool;
    Doc *document, *function_doc;
    char *function_name;
    int comments;
} FormatResult;
static int lexeme_line(Lexeme lexeme) {
    return lexeme.token ? lexeme.token->position.line : lexeme.comment->position.line;
}
static int attach_comments(Lexed *lexed) {
    Token **next = allocate((size_t)lexed->item_count * sizeof *next);
    Token *following = NULL;
    for (int i = lexed->item_count - 1; i >= 0; --i) {
        next[i] = following;
        if (lexed->items[i].token)
            following = lexed->items[i].token;
    }
    Token *previous = NULL;
    int count = 0;
    for (int i = 0; i < lexed->item_count; ++i) {
        Lexeme item = lexed->items[i];
        if (item.token) {
            previous = item.token;
            continue;
        }
        ++count;
        Comment *comment = item.comment;
        Token *token = next[i];
        if (previous && previous->position.line == comment->position.line &&
            (!token || token->position.line > comment->position.line)) {
            comments_push(&previous->trailing, comment);
            previous->original_trailing = true;
        } else {
            comment->own = comment->line || i + 1 == lexed->item_count ||
                           lexeme_line(lexed->items[i + 1]) > comment->position.line;
            if (!token)
                token = lexed->tokens.data[lexed->tokens.count - 1];
            comments_push(&token->leading, comment);
        }
    }
    free(next);
    return count;
}
static void allow_comments(const Node *node, bool *allowed, bool *trailing) {
    if (!node)
        return;
    switch (node->kind) {
    case N_PROGRAM:
        for (int i = 0; i < node->elements.count; ++i)
            allowed[node->elements.data[i]->first] = true;
        break;
    case N_BLOCK:
        allowed[node->close->index] = true;
        for (int i = 0; i < node->elements.count; ++i)
            allowed[node->elements.data[i]->first] = true;
        break;
    case N_SWITCH_BODY:
        allowed[node->close->index] = true;
        for (int i = 0; i < node->elements.count; ++i) {
            const Node *clause = node->elements.data[i];
            allowed[clause->token->index] = true;
            for (int j = 0; j < clause->elements.count; ++j)
                allowed[clause->elements.data[j]->first] = true;
        }
        break;
    case N_IF:
    case N_WHILE:
    case N_FOR:
        if (node->body->kind != N_BLOCK)
            allowed[node->body->first] = true;
        if (node->kind == N_IF && node->else_part && node->else_part->kind != N_BLOCK &&
            node->else_part->kind != N_IF)
            allowed[node->else_part->first] = true;
        break;
    case N_LIST:
        for (int i = 0; i < node->elements.count; ++i)
            allowed[node->elements.data[i]->first] = true;
        if (node->trailing)
            trailing[node->trailing->index] = true;
        break;
    default:
        break;
    }
    Nodes children = node_children(node);
    for (int i = 0; i < children.count; ++i)
        allow_comments(children.data[i], allowed, trailing);
    free(children.data);
}
static FileError check_comments(const Node *root, const Tokens *tokens) {
    bool *allowed = allocate((size_t)tokens->count * sizeof *allowed),
         *trailing = allocate((size_t)tokens->count * sizeof *trailing);
    allowed[tokens->count - 1] = true;
    allow_comments(root, allowed, trailing);
    FileError out = {0};
    for (int i = 0; i < tokens->count && !out.message; ++i) {
        const Token *token = tokens->data[i];
        for (int j = 0; j < token->leading.count; ++j) {
            const Comment *comment = token->leading.data[j];
            if (trailing[token->index] || (comment->own && !allowed[token->index])) {
                out = (FileError){comment->position, copy_text("comment not allowed here")};
                break;
            }
        }
    }
    free(allowed);
    free(trailing);
    return out;
}
typedef struct {
    Profile profile;
    const Tokens *tokens;
    DocPool *pool;
    Doc *first_function;
    const char *function_name;
} Builder;
static Doc *expression(Builder *builder, Node *node, int required);
static Doc *statement(Builder *builder, Node *node);
static Doc *build_list(Builder *builder, Node *node);
static Doc *build_block(Builder *builder, Node *node);
static Doc *body(Builder *builder, Node *node);
static Doc *declaration(Builder *builder, Node *node);
static Doc *simple(Builder *builder, Node *node);
static Doc *space(Builder *builder) {
    return doc_text(builder->pool, builder->profile.spaces ? " " : "");
}
static Doc *operator_line(Builder *builder) {
    return doc_marker(builder->pool, builder->profile.spaces ? D_LINE : D_SOFTLINE);
}
static Doc *keyword_space(Builder *builder) {
    return doc_text(builder->pool, builder->profile.keyword_space ? " " : "");
}
static Doc *brace_separator(Builder *builder) {
    return builder->profile.allman ? doc_marker(builder->pool, D_HARDLINE)
                                   : doc_text(builder->pool, " ");
}
static Doc *separator(Builder *builder, int blank) {
    Docs docs = {0};
    int count = blank < builder->profile.max_blank ? blank : builder->profile.max_blank;
    for (int i = 0; i <= count; ++i)
        docs_push(&docs, doc_marker(builder->pool, D_HARDLINE));
    return doc_cat(builder->pool, docs);
}
static int pre_blank(const Token *token) {
    return token->leading.count ? token->leading.data[0]->blank : token->blank;
}
static Doc *comment_doc(Builder *builder, const Comments *comments, bool has_last, int last_blank) {
    Docs docs = {0};
    for (int i = 0; i < comments->count; ++i) {
        const Comment *comment = comments->data[i];
        docs_push(&docs, doc_text(builder->pool, comment->value));
        bool next = i + 1 < comments->count;
        if (next || has_last)
            docs_push(&docs, comment->own ? separator(builder, next ? comments->data[i + 1]->blank
                                                                    : last_blank)
                                          : doc_text(builder->pool, " "));
    }
    return doc_cat(builder->pool, docs);
}
static Doc *trailing_part(Builder *builder, const Token *token) {
    if (!token->trailing.count)
        return doc_text(builder->pool, "");
    TextLines parts = {0};
    for (int i = 0; i < token->trailing.count; ++i)
        lines_add(&parts, token->trailing.data[i]->value);
    char *joined = join_texts(&parts, " ");
    Doc *out = doc_suffix(builder->pool, joined);
    free(joined);
    lines_free(&parts);
    return out;
}
static Doc *token_leading(Builder *builder, Token *token, const Comments *leading) {
    return concat(builder->pool, 3, comment_doc(builder, leading, true, token->blank),
                  doc_text(builder->pool, token->value), trailing_part(builder, token));
}
static Doc *token_doc(Builder *builder, Token *token) {
    return token ? token_leading(builder, token, &token->leading) : doc_text(builder->pool, "");
}
typedef struct {
    Comments own, inline_comments;
} ClosingComments;
static ClosingComments split_closing(const Token *token) {
    int split = 0;
    for (int i = 0; i < token->leading.count; ++i)
        if (token->leading.data[i]->own)
            split = i + 1;
    ClosingComments out = {0};
    out.own = (Comments){token->leading.data, split, split};
    out.inline_comments = (Comments){token->leading.data ? token->leading.data + split : NULL,
                                     token->leading.count - split, token->leading.count - split};
    return out;
}
static Doc *whole(Builder *builder, Node *root) {
    Docs docs = {0};
    for (int i = 0; i < root->elements.count; ++i) {
        Node *item = root->elements.data[i];
        if (i)
            docs_push(&docs, separator(builder, pre_blank(builder->tokens->data[item->first])));
        Doc *doc = statement(builder, item);
        docs_push(&docs, doc);
        if (item->kind == N_FUNCTION && !builder->first_function) {
            builder->first_function = doc;
            builder->function_name = item->name->value;
        }
    }
    Token *end = builder->tokens->data[builder->tokens->count - 1];
    if (end->leading.count) {
        if (root->elements.count)
            docs_push(&docs, separator(builder, end->leading.data[0]->blank));
        docs_push(&docs, comment_doc(builder, &end->leading, false, 0));
    }
    return doc_cat(builder->pool, docs);
}
static Doc *build_list(Builder *builder, Node *node) {
    DocPool *pool = builder->pool;
    if (!node->elements.count)
        return concat(pool, 2, token_doc(builder, node->open), token_doc(builder, node->close));
    Doc *force = doc_text(pool, "");
    for (int i = node->open->index; i < node->close->index; ++i)
        if (builder->tokens->data[i]->original_trailing) {
            force = doc_marker(pool, D_BREAK_PARENT);
            break;
        }
    Docs inside = {0};
    docs_push(&inside, doc_marker(pool, D_SOFTLINE));
    for (int i = 0; i < node->elements.count; ++i) {
        if (i) {
            docs_push(&inside, token_doc(builder, node->commas.data[i - 1]));
            docs_push(&inside, doc_marker(pool, D_LINE));
        }
        docs_push(&inside, !strcmp(node->value, "arguments")
                               ? expression(builder, node->elements.data[i], 0)
                               : statement(builder, node->elements.data[i]));
    }
    if (!strcmp(node->value, "initializer")) {
        docs_push(&inside, doc_if_break(pool, ",", ""));
        if (node->trailing)
            docs_push(&inside, trailing_part(builder, node->trailing));
    }
    return doc_group(pool, concat(pool, 5, force, token_doc(builder, node->open),
                                  doc_nest(pool, builder->profile.indent, doc_cat(pool, inside)),
                                  doc_marker(pool, D_SOFTLINE), token_doc(builder, node->close)));
}
static Doc *build_block(Builder *builder, Node *node) {
    DocPool *pool = builder->pool;
    ClosingComments comments = split_closing(node->close);
    if (!node->elements.count && !comments.own.count)
        return concat(pool, 2, token_doc(builder, node->open),
                      token_leading(builder, node->close, &comments.inline_comments));
    Docs inside = {0};
    docs_push(&inside, doc_marker(pool, D_HARDLINE));
    for (int i = 0; i < node->elements.count; ++i) {
        Node *child = node->elements.data[i];
        if (i)
            docs_push(&inside, separator(builder, pre_blank(builder->tokens->data[child->first])));
        docs_push(&inside, statement(builder, child));
    }
    if (comments.own.count) {
        if (node->elements.count)
            docs_push(&inside, separator(builder, comments.own.data[0]->blank));
        docs_push(&inside, comment_doc(builder, &comments.own, false, 0));
    }
    return concat(pool, 4, token_doc(builder, node->open),
                  doc_nest(pool, builder->profile.indent, doc_cat(pool, inside)),
                  doc_marker(pool, D_HARDLINE),
                  token_leading(builder, node->close, &comments.inline_comments));
}
static Doc *body(Builder *builder, Node *node) {
    DocPool *pool = builder->pool;
    if (node->kind == N_BLOCK)
        return concat(pool, 2, brace_separator(builder), build_block(builder, node));
    if (builder->profile.add_braces)
        return concat(
            pool, 5, brace_separator(builder), doc_text(pool, "{"),
            doc_nest(pool, builder->profile.indent,
                     concat(pool, 2, doc_marker(pool, D_HARDLINE), statement(builder, node))),
            doc_marker(pool, D_HARDLINE), doc_text(pool, "}"));
    return doc_nest(pool, builder->profile.indent,
                    concat(pool, 2, doc_marker(pool, D_HARDLINE), statement(builder, node)));
}
static Doc *declaration(Builder *builder, Node *node) {
    DocPool *pool = builder->pool;
    Docs docs = {0};
    docs_push(&docs, token_doc(builder, node->token));
    docs_push(&docs, doc_text(pool, " "));
    docs_push(&docs, token_doc(builder, node->name));
    for (int i = 0; i < node->dimensions.count; ++i) {
        Node *dimension = node->dimensions.data[i];
        docs_push(&docs, token_doc(builder, dimension->open));
        if (dimension->expr)
            docs_push(&docs, expression(builder, dimension->expr, 0));
        docs_push(&docs, token_doc(builder, dimension->close));
    }
    if (node->op) {
        docs_push(&docs, space(builder));
        docs_push(&docs, token_doc(builder, node->op));
        docs_push(&docs, space(builder));
        docs_push(&docs, node->init->kind == N_LIST ? build_list(builder, node->init)
                                                    : expression(builder, node->init, 0));
    }
    docs_push(&docs, token_doc(builder, node->semi));
    return doc_cat(pool, docs);
}
static Doc *simple(Builder *builder, Node *node) {
    return node->kind == N_ASSIGNMENT ? concat(builder->pool, 5, expression(builder, node->left, 0),
                                               space(builder), token_doc(builder, node->op),
                                               space(builder), expression(builder, node->right, 0))
                                      : expression(builder, node->expr, 0);
}
static Doc *statement(Builder *builder, Node *node) {
    DocPool *pool = builder->pool;
    switch (node->kind) {
    case N_FUNCTION:
        return concat(pool, 6, token_doc(builder, node->token), doc_text(pool, " "),
                      token_doc(builder, node->name), build_list(builder, node->init),
                      doc_marker(pool, D_HARDLINE), build_block(builder, node->body));
    case N_PARAMETER:
    case N_DECLARATION:
        return declaration(builder, node);
    case N_LIST:
        return build_list(builder, node);
    case N_BLOCK:
        return build_block(builder, node);
    case N_ASSIGNMENT:
    case N_SIMPLE:
        return concat(pool, 2, simple(builder, node), token_doc(builder, node->semi));
    case N_RETURN: {
        Docs docs = {0};
        docs_push(&docs, token_doc(builder, node->token));
        if (node->expr) {
            docs_push(&docs, doc_text(pool, " "));
            docs_push(&docs, expression(builder, node->expr, 0));
        }
        docs_push(&docs, token_doc(builder, node->semi));
        return doc_cat(pool, docs);
    }
    case N_BREAK:
    case N_CONTINUE:
        return concat(pool, 2, token_doc(builder, node->token), token_doc(builder, node->semi));
    case N_WHILE:
        return concat(pool, 6, token_doc(builder, node->token), keyword_space(builder),
                      token_doc(builder, node->open), expression(builder, node->expr, 0),
                      token_doc(builder, node->close), body(builder, node->body));
    case N_FOR: {
        Docs parts = {0};
        if (node->init)
            docs_push(&parts, node->init->kind == N_DECLARATION ? declaration(builder, node->init)
                                                                : simple(builder, node->init));
        docs_push(&parts, token_doc(builder, node->semi));
        if (node->condition) {
            docs_push(&parts, doc_marker(pool, D_LINE));
            docs_push(&parts, expression(builder, node->condition, 0));
        }
        docs_push(&parts, token_doc(builder, node->semi2));
        if (node->update) {
            docs_push(&parts, doc_marker(pool, D_LINE));
            docs_push(&parts, simple(builder, node->update));
        }
        return concat(pool, 6, token_doc(builder, node->token), keyword_space(builder),
                      token_doc(builder, node->open),
                      doc_group(pool, doc_align(pool, doc_cat(pool, parts))),
                      token_doc(builder, node->close), body(builder, node->body));
    }
    case N_IF: {
        Docs docs = {0};
        docs_push(&docs, token_doc(builder, node->token));
        docs_push(&docs, keyword_space(builder));
        docs_push(&docs, token_doc(builder, node->open));
        docs_push(&docs, expression(builder, node->expr, 0));
        docs_push(&docs, token_doc(builder, node->close));
        docs_push(&docs, body(builder, node->body));
        if (node->else_part) {
            docs_push(&docs, !builder->profile.allman &&
                                     (node->body->kind == N_BLOCK || builder->profile.add_braces)
                                 ? doc_text(pool, " ")
                                 : doc_marker(pool, D_HARDLINE));
            docs_push(&docs, token_doc(builder, node->else_token));
            if (node->else_part->kind == N_IF) {
                docs_push(&docs, doc_text(pool, " "));
                docs_push(&docs, statement(builder, node->else_part));
            } else
                docs_push(&docs, body(builder, node->else_part));
        }
        return doc_cat(pool, docs);
    }
    case N_SWITCH: {
        Node *switch_body = node->body;
        ClosingComments comments = split_closing(switch_body->close);
        Doc *head = concat(pool, 7, token_doc(builder, node->token), keyword_space(builder),
                           token_doc(builder, node->open), expression(builder, node->expr, 0),
                           token_doc(builder, node->close), brace_separator(builder),
                           token_doc(builder, switch_body->open));
        if (!switch_body->elements.count && !comments.own.count)
            return concat(pool, 2, head,
                          token_leading(builder, switch_body->close, &comments.inline_comments));
        Docs inside = {0};
        docs_push(&inside, doc_marker(pool, D_HARDLINE));
        for (int i = 0; i < switch_body->elements.count; ++i) {
            Node *clause = switch_body->elements.data[i];
            if (i)
                docs_push(&inside, separator(builder, pre_blank(clause->token)));
            Docs parts = {0};
            docs_push(&parts, token_doc(builder, clause->token));
            if (clause->expr) {
                docs_push(&parts, doc_text(pool, " "));
                docs_push(&parts, expression(builder, clause->expr, 0));
            }
            docs_push(&parts, token_doc(builder, clause->colon));
            if (clause->elements.count) {
                Docs statements = {0};
                docs_push(&statements, doc_marker(pool, D_HARDLINE));
                for (int j = 0; j < clause->elements.count; ++j) {
                    Node *child = clause->elements.data[j];
                    if (j)
                        docs_push(
                            &statements,
                            separator(builder, pre_blank(builder->tokens->data[child->first])));
                    docs_push(&statements, statement(builder, child));
                }
                docs_push(&parts,
                          doc_nest(pool, builder->profile.indent, doc_cat(pool, statements)));
            }
            docs_push(&inside, doc_cat(pool, parts));
        }
        if (comments.own.count) {
            if (switch_body->elements.count)
                docs_push(&inside, separator(builder, comments.own.data[0]->blank));
            docs_push(&inside, comment_doc(builder, &comments.own, false, 0));
        }
        return concat(pool, 4, head,
                      doc_nest(pool, builder->profile.indent_cases ? builder->profile.indent : 0,
                               doc_cat(pool, inside)),
                      doc_marker(pool, D_HARDLINE),
                      token_leading(builder, switch_body->close, &comments.inline_comments));
    }
    default:
        return expression(builder, node, 0);
    }
}
static Node *opening(Builder *builder, Node *node, int required) {
    if (!builder->profile.remove_parens)
        return node;
    while (node->kind == N_PAREN && expression_level(node->expr) >= required &&
           !node->open->leading.count && !node->close->leading.count) {
        Node *inner = node->expr;
        Token *first = builder->tokens->data[inner->first],
              *last = builder->tokens->data[inner->last];
        Comments front = {0};
        for (int i = 0; i < node->open->trailing.count; ++i)
            comments_push(&front, node->open->trailing.data[i]);
        for (int i = 0; i < first->trailing.count; ++i)
            comments_push(&front, first->trailing.data[i]);
        free(first->trailing.data);
        first->trailing = front;
        for (int i = 0; i < node->close->trailing.count; ++i)
            comments_push(&last->trailing, node->close->trailing.data[i]);
        node->open->trailing.count = 0;
        node->close->trailing.count = 0;
        node = inner;
    }
    return node;
}
static bool postfix(const Node *node) {
    return node->kind == N_CALL || node->kind == N_INDEX || node->kind == N_MEMBER;
}
static Doc *postfix_document(Builder *builder, Node *node) {
    if (node->kind == N_CALL)
        return build_list(builder, node->init);
    if (node->kind == N_INDEX)
        return concat(builder->pool, 3, token_doc(builder, node->open),
                      expression(builder, node->expr, 0), token_doc(builder, node->close));
    return concat(builder->pool, 2, token_doc(builder, node->op), token_doc(builder, node->name));
}
static Doc *expression(Builder *builder, Node *original, int required) {
    Node *node = opening(builder, original, required);
    DocPool *pool = builder->pool;
    switch (node->kind) {
    case N_ATOM:
        return token_doc(builder, node->token);
    case N_PAREN:
        return concat(pool, 3, token_doc(builder, node->open), expression(builder, node->expr, 0),
                      token_doc(builder, node->close));
    case N_UNARY:
        return concat(pool, 2, token_doc(builder, node->op), expression(builder, node->expr, 8));
    case N_BINARY: {
        int level = expression_level(node);
        Tokens operators = {0};
        Nodes operands = {0};
        Node *head = node;
        while (head->kind == N_BINARY && expression_level(head) == level) {
            tokens_push(&operators, head->op);
            nodes_push(&operands, head->right);
            head = opening(builder, head->left, level);
        }
        Docs inside = {0};
        for (int i = operators.count - 1; i >= 0; --i) {
            docs_push(&inside, operator_line(builder));
            docs_push(&inside, token_doc(builder, operators.data[i]));
            docs_push(&inside, space(builder));
            docs_push(&inside, expression(builder, operands.data[i], level + 1));
        }
        Doc *out =
            doc_group(pool, concat(pool, 2, expression(builder, head, level),
                                   doc_nest(pool, builder->profile.indent, doc_cat(pool, inside))));
        free(operators.data);
        free(operands.data);
        return out;
    }
    case N_CONDITIONAL: {
        Docs inside = {0};
        Node *current = node;
        for (;;) {
            docs_push(&inside, operator_line(builder));
            docs_push(&inside, token_doc(builder, current->op));
            docs_push(&inside, space(builder));
            docs_push(&inside, expression(builder, current->then_part, 0));
            docs_push(&inside, operator_line(builder));
            docs_push(&inside, token_doc(builder, current->colon));
            docs_push(&inside, space(builder));
            Node *other = opening(builder, current->else_part, 0);
            if (other->kind == N_CONDITIONAL) {
                docs_push(&inside, expression(builder, other->expr, 1));
                current = other;
            } else {
                docs_push(&inside, expression(builder, other, 0));
                break;
            }
        }
        return doc_group(pool,
                         concat(pool, 2, expression(builder, node->expr, 1),
                                doc_nest(pool, builder->profile.indent, doc_cat(pool, inside))));
    }
    case N_CALL:
    case N_INDEX:
    case N_MEMBER: {
        Nodes operations = {0};
        Node *head = node;
        while (postfix(head)) {
            nodes_push(&operations, head);
            head = opening(builder, head->left, 8);
        }
        for (int i = 0; i < operations.count / 2; ++i) {
            Node *value = operations.data[i];
            operations.data[i] = operations.data[operations.count - 1 - i];
            operations.data[operations.count - 1 - i] = value;
        }
        Nodes *segments = allocate((size_t)(operations.count + 1) * sizeof *segments);
        int segment_count = 1;
        for (int i = 0; i < operations.count; ++i) {
            Node *operation = operations.data[i];
            if (operation->kind == N_MEMBER)
                ++segment_count;
            nodes_push(&segments[segment_count - 1], operation);
        }
        int count = 0, first = -1;
        for (int i = 1; i < segment_count; ++i) {
            bool has_call = false;
            for (int j = 0; j < segments[i].count; ++j)
                if (segments[i].data[j]->kind == N_CALL)
                    has_call = true;
            if (has_call) {
                ++count;
                if (first < 0)
                    first = i;
            }
        }
        Docs docs = {0};
        docs_push(&docs, expression(builder, head, 8));
        Doc *out;
        if (count < 2) {
            for (int i = 0; i < operations.count; ++i)
                docs_push(&docs, postfix_document(builder, operations.data[i]));
            out = doc_cat(pool, docs);
        } else {
            for (int i = 0; i < first; ++i)
                for (int j = 0; j < segments[i].count; ++j)
                    docs_push(&docs, postfix_document(builder, segments[i].data[j]));
            Docs inside = {0};
            for (int i = first; i < segment_count; ++i) {
                docs_push(&inside, doc_marker(pool, D_SOFTLINE));
                for (int j = 0; j < segments[i].count; ++j)
                    docs_push(&inside, postfix_document(builder, segments[i].data[j]));
            }
            docs_push(&docs, doc_nest(pool, builder->profile.indent, doc_cat(pool, inside)));
            out = doc_group(pool, doc_cat(pool, docs));
        }
        for (int i = 0; i < segment_count; ++i)
            free(segments[i].data);
        free(segments);
        free(operations.data);
        return out;
    }
    default:
        exit(EXIT_FAILURE);
    }
}
static FormatResult format(const TextLines *source, Profile profile) {
    FormatResult out = {0};
    Lexed lexed = lex(source);
    if (lexed.error.message) {
        out.error = lexed.error;
        lexed.error.message = NULL;
        lex_free(&lexed);
        return out;
    }
    out.comments = attach_comments(&lexed);
    Parser parser = {0};
    parser.tokens = &lexed.tokens;
    Node *root = parse_program(&parser);
    if (parser.error.message) {
        out.error = parser.error;
        parser.error.message = NULL;
        parser_free(&parser);
        lex_free(&lexed);
        return out;
    }
    out.error = check_comments(root, &lexed.tokens);
    if (!out.error.message) {
        Builder builder = {profile, &lexed.tokens, &out.pool, NULL, NULL};
        out.document = whole(&builder, root);
        out.function_doc = builder.first_function;
        if (builder.function_name)
            out.function_name = copy_text(builder.function_name);
        if (root->elements.count || lexed.tokens.data[lexed.tokens.count - 1]->leading.count)
            out.lines = print_doc(out.document, profile.width, profile.comment_column);
    }
    parser_free(&parser);
    lex_free(&lexed);
    return out;
}
static void result_free(FormatResult *result) {
    lines_free(&result->lines);
    free(result->error.message);
    free(result->function_name);
    doc_pool_free(&result->pool);
}
static NamedProfile *read_profiles(int *count) {
    NamedProfile *out = allocate(5 * sizeof *out);
    *count = 0;
    TextLines lines = read_lines("input/style.txt");
    Profile *profile = NULL;
    for (int i = 0; i < lines.count; ++i) {
        char *line = lines.data[i];
        if (!*line)
            continue;
        if (*line == '[') {
            line[strlen(line) - 1] = 0;
            strcpy(out[*count].name, line + 1);
            profile = &out[(*count)++].profile;
            continue;
        }
        char *value = strchr(line, '=');
        *value++ = 0;
        if (!strcmp(line, "width"))
            profile->width = atoi(value);
        else if (!strcmp(line, "indent"))
            profile->indent = atoi(value);
        else if (!strcmp(line, "max_blank_lines"))
            profile->max_blank = atoi(value);
        else if (!strcmp(line, "comment_column"))
            profile->comment_column = atoi(value);
        else if (!strcmp(line, "brace_style"))
            profile->allman = !strcmp(value, "allman");
        else if (!strcmp(line, "space_around_operators"))
            profile->spaces = !strcmp(value, "yes");
        else if (!strcmp(line, "space_after_keyword"))
            profile->keyword_space = !strcmp(value, "yes");
        else if (!strcmp(line, "indent_case_labels"))
            profile->indent_cases = !strcmp(value, "yes");
        else if (!strcmp(line, "add_braces"))
            profile->add_braces = !strcmp(value, "yes");
        else
            profile->remove_parens = !strcmp(value, "yes");
    }
    lines_free(&lines);
    return out;
}
static Source *read_sources(int *count) {
    Source *out = allocate(20 * sizeof *out);
    *count = 0;
    TextLines lines = read_lines("input/sources.txt");
    for (int i = 0; i < lines.count; ++i) {
        char *line = lines.data[i];
        if (!strncmp(line, "=== ", 4)) {
            Source *source = &out[(*count)++];
            source->header = line;
            char *copy = copy_text(line + 4), *separator = strchr(copy, ' ');
            *separator = 0;
            strcpy(source->name, copy);
            strcpy(source->profile, separator + 1);
            free(copy);
        } else
            lines_push(&out[*count - 1].lines, line);
    }
    free(lines.data);
    return out;
}
static void write_lines(const char *name, const TextLines *lines) {
    char *path = format_text("output/%s", name);
    FILE *output = fopen(path, "wb");
    free(path);
    if (!output)
        exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i)
        if (fputs(lines->data[i], output) == EOF || fputc('\n', output) == EOF)
            exit(EXIT_FAILURE);
    if (fclose(output))
        exit(EXIT_FAILURE);
}
int main(void) {
    int profile_count, source_count;
    NamedProfile *profiles = read_profiles(&profile_count);
    Source *sources = read_sources(&source_count);
    TextLines formatted = {0}, idempotency = {0}, diagnostics = {0}, trees = {0}, changes = {0};
    for (int file = 0; file < source_count; ++file) {
        Source *source = &sources[file];
        Profile profile = {0};
        for (int i = 0; i < profile_count; ++i)
            if (!strcmp(profiles[i].name, source->profile)) {
                profile = profiles[i].profile;
                break;
            }
        FormatResult result = format(&source->lines, profile);
        TextLines original = {0};
        for (int i = 0; i < source->lines.count; ++i)
            lines_push(&original, trim_right(copy_text(source->lines.data[i])));
        lines_add(&formatted, source->header);
        lines_push(&trees, format_text("=== %s", source->name));
        lines_push(&changes, format_text("=== %s", source->name));
        if (result.error.message) {
            FileError error = result.error;
            lines_append(&formatted, &original);
            lines_push(&idempotency, format_text("%s: skipped (syntax error)", source->name));
            lines_push(&diagnostics,
                       format_text("%s:%d:%d: error: %s", source->name, error.position.line,
                                   error.position.column, error.message));
            lines_add(&trees, "syntax error");
            lines_add(&changes, "skipped (syntax error)");
            lines_free(&original);
            result_free(&result);
            continue;
        }
        lines_append(&formatted, &result.lines);
        FormatResult second = format(&result.lines, profile);
        if (second.error.message) {
            FileError error = second.error;
            lines_push(&idempotency,
                       format_text("%s: unstable (second pass: %d:%d: %s)", source->name,
                                   error.position.line, error.position.column, error.message));
        } else {
            int difference = -1, common = result.lines.count < second.lines.count
                                              ? result.lines.count
                                              : second.lines.count;
            for (int i = 0; i < common; ++i)
                if (strcmp(result.lines.data[i], second.lines.data[i])) {
                    difference = i + 1;
                    break;
                }
            if (difference < 0 && result.lines.count != second.lines.count)
                difference = common + 1;
            if (difference < 0)
                lines_push(&idempotency, format_text("%s: stable", source->name));
            else
                lines_push(&idempotency,
                           format_text("%s: unstable at line %d", source->name, difference));
        }
        int longest = 0;
        for (int i = 0; i < result.lines.count; ++i) {
            int length = (int)strlen(result.lines.data[i]);
            if (length > longest)
                longest = length;
            if (length > profile.width)
                lines_push(&diagnostics, format_text("%s:%d: warning: line too long (%d > %d)",
                                                     source->name, i + 1, length, profile.width));
        }
        GroupMetrics metrics = group_metrics(result.document);
        lines_push(
            &trees,
            format_text("metrics lines=%d longest=%d comments=%d groups=%d broken=%d forced=%d",
                        result.lines.count, longest, result.comments, metrics.groups,
                        metrics.broken, metrics.forced));
        if (!result.function_doc)
            lines_add(&trees, "no function");
        else {
            lines_push(&trees, format_text("function %s", result.function_name));
            TextLines doc_lines = doc_tree(result.function_doc, 0);
            append_owned(&trees, &doc_lines);
        }
        TextLines diff = diff_lines(&original, &result.lines);
        append_owned(&changes, &diff);
        lines_free(&original);
        result_free(&result);
        result_free(&second);
    }
    if (!diagnostics.count)
        lines_add(&diagnostics, "no diagnostics");
    mkdir("output", 0755);
    write_lines("formatted.txt", &formatted);
    write_lines("idempotency.txt", &idempotency);
    write_lines("diagnostics.txt", &diagnostics);
    write_lines("doc_tree.txt", &trees);
    write_lines("changes.txt", &changes);
    for (int i = 0; i < source_count; ++i) {
        free(sources[i].header);
        lines_free(&sources[i].lines);
    }
    free(sources);
    free(profiles);
    lines_free(&formatted);
    lines_free(&idempotency);
    lines_free(&diagnostics);
    lines_free(&trees);
    lines_free(&changes);
    return 0;
}
