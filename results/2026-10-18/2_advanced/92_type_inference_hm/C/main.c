#include "ml.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *ml_alloc(size_t size) {
    void *value = calloc(1, size ? size : 1);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    record->value = value;
    record->next = allocations;
    allocations = record;
    return value;
}
void *ml_grow(void *items, int *capacity, size_t size, int count) {
    int next = *capacity ? *capacity * 2 : 8;
    void *result = ml_alloc((size_t)next * size);
    if (count)
        memcpy(result, items, (size_t)count * size);
    *capacity = next;
    return result;
}
char *ml_text(const char *text, size_t length) {
    char *result = ml_alloc(length + 1);
    memcpy(result, text, length);
    return result;
}
char *ml_format(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *result = ml_alloc((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, format, args);
    va_end(args);
    return result;
}
void ml_cleanup(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
void text_add(Text *text, const char *value) {
    size_t length = strlen(value);
    while ((size_t)text->capacity < (size_t)text->count + length + 1)
        text->items = ml_grow(text->items, &text->capacity, 1, text->count);
    memcpy(text->items + text->count, value, length + 1);
    text->count += (int)length;
}
void text_char(Text *text, char c) {
    char value[2] = {c, 0};
    text_add(text, value);
}
char *text_value(Text *text) {
    if (!text->items)
        return ml_text("", 0);
    return text->items;
}
typedef struct {
    TypeList variables, quantified;
    StringList names;
    bool local;
} TypePrinter;
static char *type_print(TypePrinter *printer, Type *type) {
    type = resolve(type);
    if (type->kind == TYPE_VAR) {
        for (int i = 0; i < printer->variables.count; ++i)
            if (printer->variables.items[i] == type)
                return printer->names.items[i];
        int index = printer->variables.count;
        const char *prefix = printer->local && !type_member(printer->quantified, type) ? "'_" : "'";
        char *name = index < 26 ? ml_format("%s%c", prefix, 'a' + index % 26)
                                : ml_format("%s%c%d", prefix, 'a' + index % 26, index / 26);
        PUSH(printer->variables, type);
        PUSH(printer->names, name);
        return name;
    }
    if (type->kind == TYPE_INT)
        return "int";
    if (type->kind == TYPE_BOOL)
        return "bool";
    if (type->kind == TYPE_STRING)
        return "string";
    Type *first = resolve(type->first);
    char *left = type_print(printer, first);
    if (type->kind == TYPE_LIST) {
        if (first->kind == TYPE_PAIR || first->kind == TYPE_FUNCTION)
            left = ml_format("(%s)", left);
        return ml_format("%s list", left);
    }
    Type *second = resolve(type->second);
    char *right = type_print(printer, second);
    if (type->kind == TYPE_PAIR) {
        if (first->kind == TYPE_PAIR || first->kind == TYPE_FUNCTION)
            left = ml_format("(%s)", left);
        if (second->kind == TYPE_PAIR || second->kind == TYPE_FUNCTION)
            right = ml_format("(%s)", right);
        return ml_format("%s * %s", left, right);
    }
    if (first->kind == TYPE_FUNCTION)
        left = ml_format("(%s)", left);
    return ml_format("%s -> %s", left, right);
}
static Type *signature_type(Expr *expr, TypeEnv **variables) {
    if (equal(expr->kind, "type_variable")) {
        TypeEnv *found = type_lookup(*variables, expr->value);
        if (found)
            return found->scheme.type;
        Type *type = fresh();
        *variables = type_add(*variables, expr->value, (Scheme){type, {0}});
        return type;
    }
    TypeKind kind = TYPE_INT;
    if (equal(expr->kind, "bool"))
        kind = TYPE_BOOL;
    else if (equal(expr->kind, "string"))
        kind = TYPE_STRING;
    else if (equal(expr->kind, "list"))
        kind = TYPE_LIST;
    else if (equal(expr->kind, "pair"))
        kind = TYPE_PAIR;
    else if (equal(expr->kind, "function"))
        kind = TYPE_FUNCTION;
    Type *first = expr->children.count ? signature_type(expr->children.items[0], variables) : NULL;
    Type *second =
        expr->children.count > 1 ? signature_type(expr->children.items[1], variables) : NULL;
    return construct(kind, first, second);
}
static bool identical_types(Type *left, Type *right) {
    left = resolve(left);
    right = resolve(right);
    if (left->kind == TYPE_VAR || right->kind == TYPE_VAR)
        return left == right;
    if (left->kind != right->kind)
        return false;
    return (!left->first || identical_types(left->first, right->first)) &&
           (!left->second || identical_types(left->second, right->second));
}
static bool signature_matches(Type *inferred, Type *declared, TypeList *original,
                              TypeList *assigned) {
    inferred = resolve(inferred);
    declared = resolve(declared);
    if (inferred->kind == TYPE_VAR) {
        for (int i = 0; i < original->count; ++i)
            if (original->items[i] == inferred)
                return identical_types(assigned->items[i], declared);
        PUSH(*original, inferred);
        PUSH(*assigned, declared);
        return true;
    }
    if (declared->kind == TYPE_VAR || inferred->kind != declared->kind)
        return false;
    return (!inferred->first ||
            signature_matches(inferred->first, declared->first, original, assigned)) &&
           (!inferred->second ||
            signature_matches(inferred->second, declared->second, original, assigned));
}
static void check_signatures(Inferencer *inference, Group *group, Item **signatures) {
    for (int i = 0; i < group->bindings.count; ++i)
        if (signatures[i]) {
            Binding *binding = group->bindings.items[i];
            TypeEnv *variables = NULL;
            Type *declared = signature_type(signatures[i]->declared, &variables);
            TypeList original = {0}, assigned = {0};
            if (!signature_matches(binding->scheme.type, declared, &original, &assigned))
                type_fail(inference, "signature", binding->name.spelling, binding->name.position,
                          binding->scheme.type, declared);
            binding->scheme = (Scheme){declared, free_variables(declared)};
        }
}
static int min3(int a, int b, int c) {
    int m = a < b ? a : b;
    return m < c ? m : c;
}
static int edit_distance(const char *left, const char *right) {
    size_t n = strlen(right);
    int *previous = ml_alloc((n + 1) * sizeof(*previous));
    int *current = ml_alloc((n + 1) * sizeof(*current));
    for (size_t j = 0; j <= n; ++j)
        previous[j] = (int)j;
    for (size_t i = 0; left[i]; ++i) {
        current[0] = (int)i + 1;
        for (size_t j = 0; j < n; ++j)
            current[j + 1] =
                min3(current[j] + 1, previous[j + 1] + 1, previous[j] + (left[i] != right[j]));
        int *swap = previous;
        previous = current;
        current = swap;
    }
    return previous[n];
}
static char *type_error_message(TypeError *error) {
    TypePrinter printer = {0};
    if (equal(error->kind, "unbound")) {
        char *message = ml_format("unbound variable '%s'", error->name);
        const char *best = NULL;
        int best_distance = 3;
        for (int i = 0; i < error->candidates.count; ++i) {
            const char *candidate = error->candidates.items[i];
            int distance = edit_distance(error->name, candidate);
            if (distance <= 2 && distance < (int)strlen(error->name) &&
                (distance < best_distance ||
                 (distance == best_distance && (!best || strcmp(candidate, best) < 0)))) {
                best = candidate;
                best_distance = distance;
            }
        }
        return best ? ml_format("%s (did you mean '%s'?)", message, best) : message;
    }
    if (equal(error->kind, "not_function"))
        return ml_format("expected a function but found %s", type_print(&printer, error->found));
    if (equal(error->kind, "duplicate_pattern"))
        return ml_format("variable '%s' is bound twice in this pattern", error->name);
    if (equal(error->kind, "duplicate_let"))
        return ml_format("variable '%s' is bound twice in this let", error->name);
    if (equal(error->kind, "recursive_function"))
        return ml_format("'%s' in let rec must be a function", error->name);
    char *expected = type_print(&printer, error->expected);
    char *found = type_print(&printer, error->found);
    if (equal(error->kind, "signature"))
        return ml_format("'%s' has type %s but its signature is %s", error->name, expected, found);
    char *message = ml_format("expected %s but found %s", expected, found);
    UnificationFailure failure = error->failure;
    if (failure.infinite) {
        Type *variable = failure.expected;
        Type *value = failure.found;
        if (variable->kind != TYPE_VAR) {
            Type *swap = variable;
            variable = value;
            value = swap;
        }
        char *name = type_print(&printer, variable);
        char *type = type_print(&printer, value);
        return ml_format("%s (infinite type %s = %s)", message, name, type);
    }
    if (failure.nested) {
        char *left = type_print(&printer, failure.expected);
        char *right = type_print(&printer, failure.found);
        return ml_format("%s (%s vs %s)", message, left, right);
    }
    return message;
}
char *quote_string(const char *value) {
    Text result = {0};
    text_char(&result, '"');
    for (const char *p = value; *p; ++p) {
        if (*p == '\\')
            text_add(&result, "\\\\");
        else if (*p == '"')
            text_add(&result, "\\\"");
        else if (*p == '\n')
            text_add(&result, "\\n");
        else if (*p == '\t')
            text_add(&result, "\\t");
        else
            text_char(&result, *p);
    }
    text_char(&result, '"');
    return text_value(&result);
}
char *print_value(Value *value) {
    if (equal(value->kind, "integer"))
        return ml_format("%lld", (long long)value->integer);
    if (equal(value->kind, "boolean"))
        return value->boolean ? "true" : "false";
    if (equal(value->kind, "string"))
        return quote_string(value->text);
    if (equal(value->kind, "pair")) {
        char *first = print_value(value->items.items[0]);
        char *second = print_value(value->items.items[1]);
        return ml_format("(%s, %s)", first, second);
    }
    if (equal(value->kind, "list")) {
        Text result = {0};
        text_char(&result, '[');
        for (int i = 0; i < value->items.count; ++i) {
            if (i)
                text_add(&result, "; ");
            text_add(&result, print_value(value->items.items[i]));
        }
        text_char(&result, ']');
        return text_value(&result);
    }
    return "<fun>";
}
Value *apply_builtin(Evaluator *evaluator, const char *name, Value *argument, Position position) {
    if (equal(name, "fst"))
        return argument->items.items[0];
    if (equal(name, "snd"))
        return argument->items.items[1];
    if (equal(name, "failwith"))
        runtime_fail(evaluator, position, ml_format("failure %s", print_value(argument)));
    Value *result = make_value(equal(name, "not") ? "boolean" : "string");
    if (equal(name, "not"))
        result->boolean = !argument->boolean;
    else
        result->text = ml_format("%lld", (long long)argument->integer);
    return result;
}
static void builtins(TypeEnv **types, ValueEnv **values) {
    const char *names[] = {"fst", "snd", "not", "string_of_int", "failwith"};
    for (int i = 0; i < 5; ++i) {
        Scheme scheme = {0};
        if (i < 2) {
            Type *a = fresh();
            Type *b = fresh();
            scheme.type = construct(TYPE_FUNCTION, construct(TYPE_PAIR, a, b), i == 0 ? a : b);
            PUSH(scheme.quantified, a);
            PUSH(scheme.quantified, b);
        } else if (i == 2)
            scheme.type = construct(TYPE_FUNCTION, primitive(TYPE_BOOL), primitive(TYPE_BOOL));
        else if (i == 3)
            scheme.type = construct(TYPE_FUNCTION, primitive(TYPE_INT), primitive(TYPE_STRING));
        else {
            Type *a = fresh();
            scheme.type = construct(TYPE_FUNCTION, primitive(TYPE_STRING), a);
            PUSH(scheme.quantified, a);
        }
        *types = type_add(*types, names[i], scheme);
        Value *value = make_value("function");
        value->builtin = names[i];
        *values = value_add(*values, names[i], value);
    }
}
static char *declared_type(Expr *e) {
    if (equal(e->kind, "type_variable"))
        return e->value;
    if (word_in("int bool string", e->kind))
        return (char *)e->kind;
    Expr *first = e->children.items[0];
    char *left = declared_type(first);
    if (equal(e->kind, "list")) {
        if (equal(first->kind, "pair") || equal(first->kind, "function"))
            left = ml_format("(%s)", left);
        return ml_format("%s list", left);
    }
    Expr *second = e->children.items[1];
    char *right = declared_type(second);
    if (equal(e->kind, "pair")) {
        if (equal(first->kind, "pair") || equal(first->kind, "function"))
            left = ml_format("(%s)", left);
        if (equal(second->kind, "pair") || equal(second->kind, "function"))
            right = ml_format("(%s)", right);
        return ml_format("%s * %s", left, right);
    }
    if (equal(first->kind, "function"))
        left = ml_format("(%s)", left);
    return ml_format("%s -> %s", left, right);
}
static char *format_expression(Expr *, int);
static Expr *parameters(Expr *e, Text *names) {
    while (equal(e->kind, "fun")) {
        if (names->count)
            text_char(names, ' ');
        text_add(names, e->token.spelling);
        e = e->children.items[0];
    }
    return e;
}
static char *format_group(Group *group) {
    Text result = {0};
    text_add(&result, group->recursive ? "let rec " : "let ");
    for (int i = 0; i < group->bindings.count; ++i) {
        if (i)
            text_add(&result, " and ");
        Binding *binding = group->bindings.items[i];
        Text names = {0};
        Expr *body = parameters(binding->expr, &names);
        text_add(&result, binding->name.spelling);
        if (names.count) {
            text_char(&result, ' ');
            text_add(&result, text_value(&names));
        }
        text_add(&result, " = ");
        text_add(&result, format_expression(body, 0));
    }
    return text_value(&result);
}
static bool ends_with_match(Expr *e) {
    if (equal(e->kind, "match"))
        return true;
    if (equal(e->kind, "let") || equal(e->kind, "fun"))
        return ends_with_match(e->children.items[0]);
    if (equal(e->kind, "if"))
        return ends_with_match(e->children.items[2]);
    return false;
}
static char *format_pattern(Expr *p) {
    if (equal(p->kind, "integer"))
        return ml_format("%lld", (long long)p->integer);
    if (equal(p->kind, "string"))
        return quote_string(p->value);
    if (word_in("name wildcard boolean", p->kind))
        return p->value;
    if (equal(p->kind, "cons")) {
        char *left = format_pattern(p->children.items[0]);
        if (equal(p->children.items[0]->kind, "cons"))
            left = ml_format("(%s)", left);
        char *right = format_pattern(p->children.items[1]);
        return ml_format("%s :: %s", left, right);
    }
    if (equal(p->kind, "pair")) {
        char *first = format_pattern(p->children.items[0]);
        char *second = format_pattern(p->children.items[1]);
        return ml_format("(%s, %s)", first, second);
    }
    Text result = {0};
    text_char(&result, '[');
    for (int i = 0; i < p->children.count; ++i) {
        if (i)
            text_add(&result, "; ");
        text_add(&result, format_pattern(p->children.items[i]));
    }
    text_char(&result, ']');
    return text_value(&result);
}
static char *format_expression(Expr *e, int required) {
    char *text = NULL;
    int strength = 9;
    if (equal(e->kind, "integer"))
        text = ml_format("%lld", (long long)e->integer);
    else if (equal(e->kind, "string"))
        text = quote_string(e->value);
    else if (equal(e->kind, "name") || equal(e->kind, "boolean"))
        text = e->value;
    else if (equal(e->kind, "pair")) {
        char *first = format_expression(e->children.items[0], 0);
        char *second = format_expression(e->children.items[1], 0);
        text = ml_format("(%s, %s)", first, second);
    } else if (equal(e->kind, "list")) {
        Text result = {0};
        text_char(&result, '[');
        for (int i = 0; i < e->children.count; ++i) {
            if (i)
                text_add(&result, "; ");
            text_add(&result, format_expression(e->children.items[i], 0));
        }
        text_char(&result, ']');
        text = text_value(&result);
    } else if (equal(e->kind, "fun")) {
        strength = 0;
        Text names = {0};
        Expr *body = parameters(e, &names);
        text = ml_format("fun %s -> %s", text_value(&names), format_expression(body, 0));
    } else if (equal(e->kind, "apply")) {
        strength = 8;
        char *function = format_expression(e->children.items[0], 8);
        char *argument = format_expression(e->children.items[1], 9);
        text = ml_format("%s %s", function, argument);
    } else if (equal(e->kind, "negate")) {
        strength = 7;
        text = ml_format("-%s", format_expression(e->children.items[0], 7));
    } else if (equal(e->kind, "binary")) {
        bool right;
        strength = operator_precedence(e->token.kind, &right);
        char *first = format_expression(e->children.items[0], strength + (right ? 1 : 0));
        char *second = format_expression(e->children.items[1], strength + (right ? 0 : 1));
        text = ml_format("%s %s %s", first, e->token.kind, second);
    } else if (equal(e->kind, "if")) {
        strength = 0;
        char *condition = format_expression(e->children.items[0], 0);
        char *yes = format_expression(e->children.items[1], 0);
        char *no = format_expression(e->children.items[2], 0);
        text = ml_format("if %s then %s else %s", condition, yes, no);
    } else if (equal(e->kind, "let")) {
        strength = 0;
        char *group = format_group(e->group);
        char *body = format_expression(e->children.items[0], 0);
        text = ml_format("%s in %s", group, body);
    } else if (equal(e->kind, "match")) {
        strength = 0;
        Text result = {0};
        text_add(&result, "match ");
        text_add(&result, format_expression(e->children.items[0], 0));
        text_add(&result, " with ");
        for (int i = 0; i < e->arms.count; ++i) {
            Arm arm = e->arms.items[i];
            if (i)
                text_add(&result, " | ");
            text_add(&result, format_pattern(arm.pattern));
            text_add(&result, " -> ");
            char *body = format_expression(arm.body, 0);
            if (i + 1 < e->arms.count && ends_with_match(arm.body))
                body = ml_format("(%s)", body);
            text_add(&result, body);
        }
        text = text_value(&result);
    }
    return strength < required ? ml_format("(%s)", text) : text;
}
static char *format_item(Item *item) {
    if (equal(item->kind, "signature"))
        return ml_format("val %s : %s;;", item->name.spelling, declared_type(item->declared));
    if (equal(item->kind, "declaration"))
        return ml_format("%s;;", format_group(item->group));
    return ml_format("%s;;", format_expression(item->expr, 0));
}
typedef struct Cover Cover;
typedef struct {
    Cover **items;
    int count, capacity;
} PatternRow;
struct Cover {
    const char *tag;
    PatternRow children;
};
typedef struct {
    PatternRow *items;
    int count, capacity;
} PatternMatrix;
static Cover *cover(const char *tag) {
    Cover *result = ml_alloc(sizeof(*result));
    result->tag = tag;
    return result;
}
static Cover *coverage_pattern(Expr *p) {
    if (equal(p->kind, "name") || equal(p->kind, "wildcard"))
        return NULL;
    if (equal(p->kind, "integer"))
        return cover(ml_format("i:%lld", (long long)p->integer));
    if (equal(p->kind, "string"))
        return cover(ml_format("s:%s", quote_string(p->value)));
    if (equal(p->kind, "boolean"))
        return cover(ml_format("b:%s", p->value));
    if (equal(p->kind, "list")) {
        Cover *result = cover("nil");
        for (int i = p->children.count - 1; i >= 0; --i) {
            Cover *cons = cover("cons");
            Cover *first = coverage_pattern(p->children.items[i]);
            PUSH(cons->children, first);
            PUSH(cons->children, result);
            result = cons;
        }
        return result;
    }
    Cover *result = cover(p->kind);
    for (int i = 0; i < p->children.count; ++i) {
        Cover *child = coverage_pattern(p->children.items[i]);
        PUSH(result->children, child);
    }
    return result;
}
static StringList constructors(Type *type) {
    type = resolve(type);
    StringList result = {0};
    if (type->kind == TYPE_BOOL) {
        PUSH(result, "b:false");
        PUSH(result, "b:true");
    } else if (type->kind == TYPE_LIST) {
        PUSH(result, "nil");
        PUSH(result, "cons");
    } else if (type->kind == TYPE_PAIR)
        PUSH(result, "pair");
    return result;
}
static TypeList constructor_types(const char *tag, Type *type) {
    type = resolve(type);
    TypeList result = {0};
    if (equal(tag, "pair")) {
        PUSH(result, type->first);
        PUSH(result, type->second);
    } else if (equal(tag, "cons")) {
        PUSH(result, type->first);
        PUSH(result, type);
    }
    return result;
}
static PatternMatrix specialize(PatternMatrix matrix, const char *tag, int arity) {
    PatternMatrix result = {0};
    for (int i = 0; i < matrix.count; ++i) {
        PatternRow row = matrix.items[i], next = {0};
        if (!row.items[0]) {
            for (int j = 0; j < arity; ++j)
                PUSH(next, NULL);
        } else if (equal(row.items[0]->tag, tag)) {
            for (int j = 0; j < row.items[0]->children.count; ++j)
                PUSH(next, row.items[0]->children.items[j]);
        } else
            continue;
        for (int j = 1; j < row.count; ++j)
            PUSH(next, row.items[j]);
        PUSH(result, next);
    }
    return result;
}
static void cover_code(Text *text, Cover *p) {
    if (!p) {
        text_char(text, '_');
        return;
    }
    text_add(text, ml_format("%zu:%s(", strlen(p->tag), p->tag));
    for (int i = 0; i < p->children.count; ++i)
        cover_code(text, p->children.items[i]);
    text_char(text, ')');
}
static void coverage_type_code(Text *text, Type *type) {
    type = resolve(type);
    if (type->kind == TYPE_VAR || type->kind == TYPE_FUNCTION) {
        text_add(text, "opaque");
        return;
    }
    const char *kinds[] = {"var", "int", "bool", "string", "list", "pair", "function"};
    text_add(text, kinds[type->kind]);
    text_char(text, '(');
    if (type->first)
        coverage_type_code(text, type->first);
    if (type->second)
        coverage_type_code(text, type->second);
    text_char(text, ')');
}
typedef struct Memo {
    char *key;
    bool result;
    struct Memo *next;
} Memo;
typedef struct {
    Memo *buckets[4096];
} Coverage;
static bool useful(Coverage *, PatternMatrix, PatternRow, TypeList);
static bool useful_compute(Coverage *coverage, PatternMatrix matrix, PatternRow query,
                           TypeList types) {
    if (!query.count)
        return !matrix.count;
    if (!matrix.count)
        return true;
    if (query.items[0]) {
        Cover *head = query.items[0];
        PatternRow next = {0};
        for (int i = 0; i < head->children.count; ++i)
            PUSH(next, head->children.items[i]);
        for (int i = 1; i < query.count; ++i)
            PUSH(next, query.items[i]);
        TypeList next_types = constructor_types(head->tag, types.items[0]);
        for (int i = 1; i < types.count; ++i)
            PUSH(next_types, types.items[i]);
        return useful(coverage, specialize(matrix, head->tag, head->children.count), next,
                      next_types);
    }
    StringList possible = constructors(types.items[0]);
    bool complete = possible.count > 0;
    for (int i = 0; i < possible.count; ++i) {
        bool present = false;
        for (int j = 0; j < matrix.count; ++j)
            if (matrix.items[j].items[0] && equal(matrix.items[j].items[0]->tag, possible.items[i]))
                present = true;
        if (!present)
            complete = false;
    }
    if (complete) {
        for (int i = 0; i < possible.count; ++i) {
            TypeList arguments = constructor_types(possible.items[i], types.items[0]);
            PatternRow next = {0};
            for (int j = 0; j < arguments.count; ++j)
                PUSH(next, NULL);
            for (int j = 1; j < query.count; ++j)
                PUSH(next, query.items[j]);
            int arity = arguments.count;
            for (int j = 1; j < types.count; ++j)
                PUSH(arguments, types.items[j]);
            if (useful(coverage, specialize(matrix, possible.items[i], arity), next, arguments))
                return true;
        }
        return false;
    }
    PatternMatrix defaults = {0};
    for (int i = 0; i < matrix.count; ++i)
        if (!matrix.items[i].items[0]) {
            PatternRow tail = {matrix.items[i].items + 1, matrix.items[i].count - 1, 0};
            PUSH(defaults, tail);
        }
    PatternRow tail = {query.items + 1, query.count - 1, 0};
    TypeList tail_types = {types.items + 1, types.count - 1, 0};
    return useful(coverage, defaults, tail, tail_types);
}
static bool useful(Coverage *coverage, PatternMatrix matrix, PatternRow query, TypeList types) {
    Text key = {0};
    for (int i = 0; i < matrix.count; ++i) {
        text_char(&key, '[');
        for (int j = 0; j < matrix.items[i].count; ++j)
            cover_code(&key, matrix.items[i].items[j]);
        text_char(&key, ']');
    }
    text_char(&key, '?');
    for (int i = 0; i < query.count; ++i)
        cover_code(&key, query.items[i]);
    text_char(&key, ':');
    for (int i = 0; i < types.count; ++i)
        coverage_type_code(&key, types.items[i]);
    char *code = text_value(&key);
    uint32_t hash = 0;
    for (const unsigned char *p = (const unsigned char *)code; *p; ++p)
        hash = hash * 65599u + *p;
    unsigned bucket = hash % 4096;
    for (Memo *m = coverage->buckets[bucket]; m; m = m->next)
        if (equal(m->key, code))
            return m->result;
    bool result = useful_compute(coverage, matrix, query, types);
    Memo *memo = ml_alloc(sizeof(*memo));
    memo->key = code;
    memo->result = result;
    memo->next = coverage->buckets[bucket];
    coverage->buckets[bucket] = memo;
    return result;
}
typedef struct Symbol {
    const char *name;
    Position position;
    bool top, used;
} Symbol;
typedef struct {
    Symbol **items;
    int count, capacity;
} SymbolList;
typedef struct SymbolEnv {
    const char *name;
    Symbol *symbol;
    struct SymbolEnv *next;
} SymbolEnv;
typedef struct {
    Position position;
    int order;
    const char *message;
} Warning;
typedef struct {
    Warning *items;
    int count, capacity;
} WarningList;
typedef struct {
    Group *group;
    SymbolList targets;
} GroupSymbols;
typedef struct {
    GroupSymbols *items;
    int count, capacity;
} GroupSymbolList;
typedef struct {
    SymbolList symbols;
    GroupSymbolList groups;
    WarningList warnings;
} StaticChecks;
static SymbolEnv *symbol_add(SymbolEnv *env, const char *name, Symbol *value) {
    SymbolEnv *result = ml_alloc(sizeof(*result));
    result->name = name;
    result->symbol = value;
    result->next = env;
    return result;
}
static Symbol *symbol_lookup(SymbolEnv *env, const char *name) {
    for (; env; env = env->next)
        if (equal(env->name, name))
            return env->symbol;
    return NULL;
}
static Symbol *symbol_new(StaticChecks *checks, const char *name, Position position, bool top) {
    Symbol *result = ml_alloc(sizeof(*result));
    result->name = name;
    result->position = position;
    result->top = top;
    PUSH(checks->symbols, result);
    return result;
}
static bool symbol_member(SymbolList targets, Symbol *value) {
    for (int i = 0; i < targets.count; ++i)
        if (targets.items[i] == value)
            return true;
    return false;
}
static SymbolEnv *static_pattern(StaticChecks *checks, Expr *p, SymbolEnv *env) {
    if (equal(p->kind, "name"))
        env = symbol_add(env, p->value, symbol_new(checks, p->value, p->position, false));
    for (int i = 0; i < p->children.count; ++i)
        env = static_pattern(checks, p->children.items[i], env);
    return env;
}
static void static_expression(StaticChecks *, Expr *, SymbolEnv *);
static SymbolEnv *static_group(StaticChecks *checks, Group *group, SymbolEnv *env, bool top) {
    SymbolEnv *inner = env;
    GroupSymbols record = {0};
    record.group = group;
    for (int i = 0; i < group->bindings.count; ++i) {
        Binding *binding = group->bindings.items[i];
        Symbol *value = symbol_new(checks, binding->name.spelling, binding->name.position, top);
        inner = symbol_add(inner, value->name, value);
        PUSH(record.targets, value);
    }
    PUSH(checks->groups, record);
    for (int i = 0; i < group->bindings.count; ++i)
        static_expression(checks, group->bindings.items[i]->expr, group->recursive ? inner : env);
    return inner;
}
static void static_expression(StaticChecks *checks, Expr *e, SymbolEnv *env) {
    if (equal(e->kind, "name")) {
        e->reference = symbol_lookup(env, e->value);
        if (e->reference)
            e->reference->used = true;
        return;
    }
    if (equal(e->kind, "fun")) {
        SymbolEnv *inner = env;
        if (!equal(e->token.spelling, "_"))
            inner = symbol_add(inner, e->token.spelling,
                               symbol_new(checks, e->token.spelling, e->token.position, false));
        static_expression(checks, e->children.items[0], inner);
        return;
    }
    if (equal(e->kind, "let")) {
        SymbolEnv *inner = static_group(checks, e->group, env, false);
        static_expression(checks, e->children.items[0], inner);
        return;
    }
    if (equal(e->kind, "match")) {
        static_expression(checks, e->children.items[0], env);
        Coverage *coverage = ml_alloc(sizeof(*coverage));
        PatternMatrix matrix = {0};
        TypeList types = {0};
        PUSH(types, e->children.items[0]->inferred);
        for (int i = 0; i < e->arms.count; ++i) {
            Arm arm = e->arms.items[i];
            PatternRow query = {0};
            Cover *pat = coverage_pattern(arm.pattern);
            PUSH(query, pat);
            if (i && !useful(coverage, matrix, query, types)) {
                Warning warning = {arm.pattern->position, 2, "this match case is unused"};
                PUSH(checks->warnings, warning);
            }
            PUSH(matrix, query);
            SymbolEnv *inner = static_pattern(checks, arm.pattern, env);
            static_expression(checks, arm.body, inner);
        }
        PatternRow wildcard = {0};
        PUSH(wildcard, NULL);
        if (useful(coverage, matrix, wildcard, types)) {
            Warning warning = {e->position, 1, "this match is not exhaustive"};
            PUSH(checks->warnings, warning);
        }
        return;
    }
    for (int i = 0; i < e->children.count; ++i)
        static_expression(checks, e->children.items[i], env);
}
static bool contains_reference(Expr *e, SymbolList targets) {
    if (equal(e->kind, "name") && symbol_member(targets, e->reference))
        return true;
    if (e->group)
        for (int i = 0; i < e->group->bindings.count; ++i)
            if (contains_reference(e->group->bindings.items[i]->expr, targets))
                return true;
    for (int i = 0; i < e->children.count; ++i)
        if (contains_reference(e->children.items[i], targets))
            return true;
    for (int i = 0; i < e->arms.count; ++i)
        if (contains_reference(e->arms.items[i].body, targets))
            return true;
    return false;
}
static void classify_visit(Expr *e, bool tail, SymbolList targets, int *count, bool *all_tail) {
    if (equal(e->kind, "name")) {
        if (symbol_member(targets, e->reference)) {
            ++*count;
            *all_tail = false;
        }
        return;
    }
    if (equal(e->kind, "apply")) {
        Expr *head = e;
        ExprList arguments = {0};
        while (equal(head->kind, "apply")) {
            PUSH(arguments, head->children.items[1]);
            head = head->children.items[0];
        }
        if (equal(head->kind, "name") && symbol_member(targets, head->reference)) {
            ++*count;
            if (!tail)
                *all_tail = false;
        } else
            classify_visit(head, false, targets, count, all_tail);
        for (int i = arguments.count - 1; i >= 0; --i)
            classify_visit(arguments.items[i], false, targets, count, all_tail);
        return;
    }
    if (equal(e->kind, "if")) {
        classify_visit(e->children.items[0], false, targets, count, all_tail);
        classify_visit(e->children.items[1], tail, targets, count, all_tail);
        classify_visit(e->children.items[2], tail, targets, count, all_tail);
        return;
    }
    if (equal(e->kind, "match")) {
        classify_visit(e->children.items[0], false, targets, count, all_tail);
        for (int i = 0; i < e->arms.count; ++i)
            classify_visit(e->arms.items[i].body, tail, targets, count, all_tail);
        return;
    }
    if (equal(e->kind, "let")) {
        for (int i = 0; i < e->group->bindings.count; ++i)
            classify_visit(e->group->bindings.items[i]->expr, false, targets, count, all_tail);
        classify_visit(e->children.items[0], tail, targets, count, all_tail);
        return;
    }
    if (equal(e->kind, "binary") && (equal(e->token.kind, "&&") || equal(e->token.kind, "||"))) {
        classify_visit(e->children.items[0], false, targets, count, all_tail);
        classify_visit(e->children.items[1], tail, targets, count, all_tail);
        return;
    }
    for (int i = 0; i < e->children.count; ++i)
        classify_visit(e->children.items[i], false, targets, count, all_tail);
}
static int warning_compare(const void *left, const void *right) {
    const Warning *a = left;
    const Warning *b = right;
    if (a->position.line != b->position.line)
        return a->position.line - b->position.line;
    if (a->position.column != b->position.column)
        return a->position.column - b->position.column;
    return a->order - b->order;
}
static WarningList static_warnings(Item *item, TypeEnv *types) {
    StaticChecks checks = {0};
    SymbolEnv *names = NULL;
    for (TypeEnv *at = types; at; at = at->next)
        names = symbol_add(names, at->name, NULL);
    if (equal(item->kind, "declaration"))
        static_group(&checks, item->group, names, true);
    else
        static_expression(&checks, item->expr, names);
    for (int i = 0; i < checks.groups.count; ++i) {
        GroupSymbols record = checks.groups.items[i];
        if (!record.group->recursive)
            continue;
        bool used = false;
        for (int j = 0; j < record.group->bindings.count; ++j) {
            Binding *binding = record.group->bindings.items[j];
            if (contains_reference(binding->expr, record.targets))
                used = true;
            Text parameters_text = {0};
            Expr *body = parameters(binding->expr, &parameters_text);
            int count = 0;
            bool all_tail = true;
            classify_visit(body, true, record.targets, &count, &all_tail);
            binding->classification = count ? (all_tail ? "tail recursive" : "recursive") : NULL;
        }
        if (!used) {
            Warning warning = {record.group->rec, 3, "unused rec flag"};
            PUSH(checks.warnings, warning);
        }
    }
    for (int i = 0; i < checks.symbols.count; ++i) {
        Symbol *symbol = checks.symbols.items[i];
        if (!symbol->top && !symbol->used && symbol->name[0] != '_') {
            Warning warning = {symbol->position, 4,
                               ml_format("unused variable '%s'", symbol->name)};
            PUSH(checks.warnings, warning);
        }
    }
    if (checks.warnings.count > 1)
        qsort(checks.warnings.items, (size_t)checks.warnings.count, sizeof(Warning),
              warning_compare);
    return checks.warnings;
}
typedef struct {
    int items, bindings, syntax, type, runtime, warnings;
    int64_t calls;
} Counts;
typedef struct {
    const char *name;
    StringList lines;
    Counts counts;
} Source;
static Source sources[2];
static FILE *types_output, *values_output, *errors_output, *formatted_output;
static void report(Source *current, Position position, const char *kind, const char *message) {
    fprintf(errors_output, "%s:%d:%d: %s: %s\n", position.file, position.line, position.column,
            kind, message);
    Source *source = equal(sources[0].name, position.file) ? &sources[0] : &sources[1];
    if (position.line <= source->lines.count) {
        fprintf(errors_output, "    %s\n", source->lines.items[position.line - 1]);
        for (int i = 0; i < position.column + 3; ++i)
            fputc(' ', errors_output);
        fputs("^\n", errors_output);
    }
    if (equal(kind, "syntax error"))
        ++current->counts.syntax;
    else if (equal(kind, "type error"))
        ++current->counts.type;
    else if (equal(kind, "runtime error"))
        ++current->counts.runtime;
    else
        ++current->counts.warnings;
}
static int binding_position_compare(const void *left, const void *right) {
    const Binding *a = *(Binding *const *)left;
    const Binding *b = *(Binding *const *)right;
    if (a->name.position.line != b->name.position.line)
        return a->name.position.line - b->name.position.line;
    return a->name.position.column - b->name.position.column;
}
static int item_position_compare(const void *left, const void *right) {
    const Item *a = *(Item *const *)left;
    const Item *b = *(Item *const *)right;
    if (a->name.position.line != b->name.position.line)
        return a->name.position.line - b->name.position.line;
    return a->name.position.column - b->name.position.column;
}
static void print_binding_type(Binding *binding, bool local) {
    TypePrinter printer = {0};
    printer.local = local;
    printer.quantified = binding->scheme.quantified;
    char *type = type_print(&printer, binding->scheme.type);
    if (local)
        fprintf(types_output, "  %s (%d:%d) : %s", binding->name.spelling,
                binding->name.position.line, binding->name.position.column, type);
    else
        fprintf(types_output, "%s : %s", binding->name.spelling, type);
    if (binding->classification)
        fprintf(types_output, " (%s)", binding->classification);
    fputc('\n', types_output);
}
typedef struct {
    Item **items;
    int count, capacity;
} ItemList;
int main(void) {
    sources[0].name = "prelude.ml";
    sources[1].name = "program.ml";
    for (int i = 0; i < 2; ++i) {
        FILE *input = fopen(ml_format("input/%s", sources[i].name), "r");
        if (input) {
            char line[122];
            while (fgets(line, sizeof(line), input)) {
                size_t length = strlen(line);
                if (length && line[length - 1] == '\n')
                    --length;
                char *text = ml_text(line, length);
                PUSH(sources[i].lines, text);
            }
            fclose(input);
        }
    }
    mkdir("output", 0777);
    types_output = fopen("output/types.txt", "w");
    values_output = fopen("output/values.txt", "w");
    errors_output = fopen("output/errors.txt", "w");
    formatted_output = fopen("output/formatted.ml", "w");
    if (!types_output || !values_output || !errors_output || !formatted_output) {
        ml_cleanup();
        return 1;
    }
    TypeEnv *type_env = NULL;
    ValueEnv *value_env = NULL;
    builtins(&type_env, &value_env);
    for (int file_index = 0; file_index < 2; ++file_index) {
        Source *source = &sources[file_index];
        Parser *parser = ml_alloc(sizeof(*parser));
        parser->tokens = lex(source->name, source->lines);
        Evaluator *evaluator = ml_alloc(sizeof(*evaluator));
        ItemList *pending = ml_alloc(sizeof(*pending));
        fprintf(types_output, "== %s ==\n", source->name);
        fprintf(values_output, "== %s ==\n", source->name);
        fprintf(formatted_output, "(* %s *)\n", source->name);
        while (!equal(parser_peek(parser).kind, "EOF")) {
            ++source->counts.items;
            if (setjmp(parser->jump)) {
                Token token = parser->error;
                const char *message = equal(token.kind, "invalid") ? token.value
                                      : equal(token.kind, "EOF")
                                          ? "unexpected end of file"
                                          : ml_format("unexpected '%s'", token.spelling);
                report(source, token.position, "syntax error", message);
                parser_recover(parser);
                continue;
            }
            Item *item = parser_item(parser);
            fprintf(formatted_output, "%s\n", format_item(item));
            if (equal(item->kind, "signature")) {
                int previous = -1;
                for (int i = 0; i < pending->count; ++i)
                    if (pending->items[i] &&
                        equal(pending->items[i]->name.spelling, item->name.spelling)) {
                        previous = i;
                        break;
                    }
                if (previous >= 0) {
                    report(source, pending->items[previous]->name.position, "warning",
                           ml_format("signature for '%s' is never used", item->name.spelling));
                    pending->items[previous] = item;
                } else
                    PUSH(*pending, item);
                continue;
            }
            Item **signatures = NULL;
            if (equal(item->kind, "declaration")) {
                signatures = ml_alloc((size_t)item->group->bindings.count * sizeof(*signatures));
                for (int i = 0; i < item->group->bindings.count; ++i)
                    for (int j = 0; j < pending->count; ++j)
                        if (pending->items[j] &&
                            equal(pending->items[j]->name.spelling,
                                  item->group->bindings.items[i]->name.spelling)) {
                            signatures[i] = pending->items[j];
                            pending->items[j] = NULL;
                            break;
                        }
            }
            Inferencer *inference = ml_alloc(sizeof(*inference));
            if (setjmp(inference->jump)) {
                report(source, inference->error.position, "type error",
                       type_error_message(&inference->error));
                continue;
            }
            Type *expression_type = NULL;
            if (equal(item->kind, "declaration")) {
                infer_group(inference, item->group, type_env, false);
                check_signatures(inference, item->group, signatures);
            } else
                expression_type = infer_expression(inference, item->expr, type_env);
            WarningList warnings = static_warnings(item, type_env);
            if (equal(item->kind, "declaration"))
                for (int i = 0; i < item->group->bindings.count; ++i)
                    print_binding_type(item->group->bindings.items[i], false);
            else {
                TypePrinter printer = {0};
                fprintf(types_output, "- : %s\n", type_print(&printer, expression_type));
            }
            if (inference->locals.count > 1)
                qsort(inference->locals.items, (size_t)inference->locals.count, sizeof(Binding *),
                      binding_position_compare);
            for (int i = 0; i < inference->locals.count; ++i)
                print_binding_type(inference->locals.items[i], true);
            for (int i = 0; i < warnings.count; ++i)
                report(source, warnings.items[i].position, "warning", warnings.items[i].message);
            if (setjmp(evaluator->jump)) {
                report(source, evaluator->error_position, "runtime error",
                       evaluator->error_message);
                continue;
            }
            if (equal(item->kind, "declaration")) {
                ValueEnv *next = eval_group(evaluator, item->group, value_env);
                for (int i = 0; i < item->group->bindings.count; ++i) {
                    Binding *binding = item->group->bindings.items[i];
                    fprintf(values_output, "%s = %s\n", binding->name.spelling,
                            print_value(value_lookup(next, binding->name.spelling)));
                    type_env = type_add(type_env, binding->name.spelling, binding->scheme);
                    ++source->counts.bindings;
                }
                value_env = next;
            } else {
                Value *value = eval_expression(evaluator, item->expr, value_env);
                fprintf(values_output, "- = %s\n", print_value(value));
            }
        }
        ItemList remaining = {0};
        for (int i = 0; i < pending->count; ++i)
            if (pending->items[i])
                PUSH(remaining, pending->items[i]);
        if (remaining.count > 1)
            qsort(remaining.items, (size_t)remaining.count, sizeof(Item *), item_position_compare);
        for (int i = 0; i < remaining.count; ++i)
            report(
                source, remaining.items[i]->name.position, "warning",
                ml_format("signature for '%s' is never used", remaining.items[i]->name.spelling));
        source->counts.calls = evaluator->calls;
    }
    fputs("== summary ==\n", errors_output);
    for (int i = 0; i < 2; ++i) {
        Counts c = sources[i].counts;
        fprintf(errors_output,
                "%s: items=%d bindings=%d syntax=%d type=%d runtime=%d warnings=%d calls=%lld\n",
                sources[i].name, c.items, c.bindings, c.syntax, c.type, c.runtime, c.warnings,
                (long long)c.calls);
    }
    fclose(types_output);
    fclose(values_output);
    fclose(errors_output);
    fclose(formatted_output);
    ml_cleanup();
    return 0;
}
