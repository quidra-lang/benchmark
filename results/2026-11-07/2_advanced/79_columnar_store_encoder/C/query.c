#include "columnar.h"
typedef struct {
    Names tokens;
    size_t position;
} Parser;
static char *peek(Parser *p) {
    return p->position < p->tokens.count ? p->tokens.items[p->position] : "";
}
static char *take(Parser *p) { return p->tokens.items[p->position++]; }
static bool accept(Parser *p, const char *token) {
    if (strcmp(peek(p), token))
        return false;
    ++p->position;
    return true;
}
static Condition *node(char *operation, Condition *left, Condition *right) {
    Condition *out = allocate(sizeof(*out));
    out->operation = operation;
    out->left = left;
    out->right = right;
    out->column = -1;
    return out;
}
static Item item(Parser *p) {
    char *name = take(p);
    if (*name >= 'a' && *name <= 'z')
        return (Item){"COLUMN", name, -1};
    take(p);
    char *operation = accept(p, "DISTINCT") ? "COUNT_DISTINCT" : name;
    char *column = accept(p, "*") ? "" : take(p);
    take(p);
    return (Item){operation, column, -1};
}
static Literal literal(Parser *p) {
    char *token = take(p);
    if (*token == '\'')
        return (Literal){T_STRING, string_value(substring(token + 1, strlen(token) - 2))};
    if (!strcmp(token, "TRUE") || !strcmp(token, "FALSE"))
        return (Literal){T_BOOL, number_value(!strcmp(token, "TRUE"))};
    return (Literal){T_INT, number_value(atoll(token))};
}
static Condition *condition(Parser *p);
static Condition *negation(Parser *p) {
    if (accept(p, "NOT"))
        return node("NOT", negation(p), NULL);
    if (accept(p, "(")) {
        Condition *tree = condition(p);
        take(p);
        return tree;
    }
    char *name = take(p), *operation = take(p);
    Condition *tree = node(operation, NULL, NULL);
    tree->name = name;
    if (!strcmp(operation, "IS")) {
        tree->operation = accept(p, "NOT") ? "IS_NOT_NULL" : "IS_NULL";
        take(p);
    } else if (!strcmp(operation, "BETWEEN")) {
        Literals_add(&tree->literals, literal(p));
        take(p);
        Literals_add(&tree->literals, literal(p));
    } else if (!strcmp(operation, "IN")) {
        take(p);
        Literals_add(&tree->literals, literal(p));
        while (accept(p, ","))
            Literals_add(&tree->literals, literal(p));
        take(p);
    } else
        Literals_add(&tree->literals, literal(p));
    return tree;
}
static Condition *conjunction(Parser *p) {
    Condition *tree = negation(p);
    while (accept(p, "AND"))
        tree = node("AND", tree, negation(p));
    return tree;
}
static Condition *condition(Parser *p) {
    Condition *tree = conjunction(p);
    while (accept(p, "OR"))
        tree = node("OR", tree, conjunction(p));
    return tree;
}
static bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
Query parse_query(const char *source) {
    Parser p = {0};
    size_t length = strlen(source);
    for (size_t i = 0; i < length;) {
        if (source[i] == ' ') {
            ++i;
            continue;
        }
        size_t start = i++;
        char c = source[start];
        if (c == '\'') {
            while (source[i] != '\'')
                ++i;
            ++i;
        } else if (letter(c) || c == '_')
            while (i < length && (letter(source[i]) || (source[i] >= '0' && source[i] <= '9') ||
                                  source[i] == '_'))
                ++i;
        else if ((c >= '0' && c <= '9') || c == '-')
            while (i < length && source[i] >= '0' && source[i] <= '9')
                ++i;
        else if (i < length && ((c == '<' && (source[i] == '=' || source[i] == '>')) ||
                                (c == '>' && source[i] == '=')))
            ++i;
        Names_add(&p.tokens, substring(source + start, i - start));
    }
    Query out = {.group = -1, .order = -1, .limit = -1};
    take(&p);
    out.star = accept(&p, "*");
    if (!out.star) {
        Items_add(&out.items, item(&p));
        while (accept(&p, ","))
            Items_add(&out.items, item(&p));
    }
    if (accept(&p, "WHERE"))
        out.condition = condition(&p);
    if (accept(&p, "GROUP")) {
        take(&p);
        out.group_name = take(&p);
    }
    if (accept(&p, "ORDER")) {
        take(&p);
        out.order_name = take(&p);
        out.descending = accept(&p, "DESC");
        if (!out.descending)
            accept(&p, "ASC");
    }
    if (accept(&p, "LIMIT"))
        out.limit = atoi(take(&p));
    return out;
}
