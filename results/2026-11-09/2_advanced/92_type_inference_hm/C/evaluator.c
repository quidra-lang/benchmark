#include "ml.h"
Value *make_value(const char *kind) {
    Value *value = ml_alloc(sizeof(*value));
    value->kind = kind;
    return value;
}
ValueEnv *value_add(ValueEnv *env, const char *name, Value *value) {
    ValueEnv *entry = ml_alloc(sizeof(*entry));
    entry->name = name;
    entry->value = value;
    entry->next = env;
    return entry;
}
Value *value_lookup(ValueEnv *env, const char *name) {
    for (; env; env = env->next)
        if (equal(env->name, name))
            return env->value;
    return NULL;
}
void runtime_fail(Evaluator *evaluator, Position position, const char *message) {
    evaluator->error_position = position;
    evaluator->error_message = (char *)message;
    longjmp(evaluator->jump, 1);
}
static Value *integer(Evaluator *evaluator, int64_t number, Position position) {
    if (number < -2147483648LL || number > 2147483647LL)
        runtime_fail(evaluator, position, "integer overflow");
    Value *value = make_value("integer");
    value->integer = number;
    return value;
}
static Value *apply(Evaluator *evaluator, Value *function, Value *argument, Position position) {
    ++evaluator->calls;
    if (function->builtin)
        return apply_builtin(evaluator, function->builtin, argument, position);
    ValueEnv *inner = function->environment;
    if (!equal(function->parameter.spelling, "_"))
        inner = value_add(inner, function->parameter.spelling, argument);
    return eval_expression(evaluator, function->body, inner);
}
static int compare(Evaluator *evaluator, Value *left, Value *right, Position position) {
    if (equal(left->kind, "function"))
        runtime_fail(evaluator, position, "functional value compared");
    if (equal(left->kind, "integer"))
        return (left->integer > right->integer) - (left->integer < right->integer);
    if (equal(left->kind, "boolean"))
        return (int)left->boolean - (int)right->boolean;
    if (equal(left->kind, "string")) {
        int order = strcmp(left->text, right->text);
        return (order > 0) - (order < 0);
    }
    int count = left->items.count < right->items.count ? left->items.count : right->items.count;
    for (int i = 0; i < count; ++i) {
        int order = compare(evaluator, left->items.items[i], right->items.items[i], position);
        if (order)
            return order;
    }
    return (left->items.count > right->items.count) - (left->items.count < right->items.count);
}
static bool pattern(Expr *p, Value *value, ValueEnv **bindings) {
    if (equal(p->kind, "wildcard"))
        return true;
    if (equal(p->kind, "name")) {
        *bindings = value_add(*bindings, p->value, value);
        return true;
    }
    if (equal(p->kind, "integer"))
        return p->integer == value->integer;
    if (equal(p->kind, "boolean"))
        return equal(p->value, "true") == value->boolean;
    if (equal(p->kind, "string"))
        return equal(p->value, value->text);
    if (equal(p->kind, "cons")) {
        if (!value->items.count)
            return false;
        if (!pattern(p->children.items[0], value->items.items[0], bindings))
            return false;
        Value *tail = make_value("list");
        for (int i = 1; i < value->items.count; ++i)
            PUSH(tail->items, value->items.items[i]);
        return pattern(p->children.items[1], tail, bindings);
    }
    if (p->children.count != value->items.count)
        return false;
    for (int i = 0; i < p->children.count; ++i)
        if (!pattern(p->children.items[i], value->items.items[i], bindings))
            return false;
    return true;
}
ValueEnv *eval_group(Evaluator *evaluator, Group *group, ValueEnv *env) {
    ValueEnv *result = env;
    ValueList closures = {0};
    for (int i = 0; i < group->bindings.count; ++i) {
        Binding *binding = group->bindings.items[i];
        Value *value;
        if (group->recursive) {
            value = make_value("function");
            value->parameter = binding->expr->token;
            value->body = binding->expr->children.items[0];
            PUSH(closures, value);
        } else
            value = eval_expression(evaluator, binding->expr, env);
        result = value_add(result, binding->name.spelling, value);
    }
    for (int i = 0; i < closures.count; ++i)
        closures.items[i]->environment = result;
    return result;
}
Value *eval_expression(Evaluator *evaluator, Expr *e, ValueEnv *env) {
    if (equal(e->kind, "integer"))
        return integer(evaluator, e->integer, e->position);
    if (equal(e->kind, "string")) {
        Value *value = make_value("string");
        value->text = e->value;
        return value;
    }
    if (equal(e->kind, "boolean")) {
        Value *value = make_value("boolean");
        value->boolean = equal(e->value, "true");
        return value;
    }
    if (equal(e->kind, "name"))
        return value_lookup(env, e->value);
    if (equal(e->kind, "fun")) {
        Value *value = make_value("function");
        value->parameter = e->token;
        value->body = e->children.items[0];
        value->environment = env;
        return value;
    }
    if (equal(e->kind, "apply")) {
        Value *function = eval_expression(evaluator, e->children.items[0], env);
        Value *argument = eval_expression(evaluator, e->children.items[1], env);
        return apply(evaluator, function, argument, e->position);
    }
    if (equal(e->kind, "negate")) {
        Value *value = eval_expression(evaluator, e->children.items[0], env);
        return integer(evaluator, -value->integer, e->token.position);
    }
    if (equal(e->kind, "if")) {
        Value *condition = eval_expression(evaluator, e->children.items[0], env);
        return eval_expression(evaluator, e->children.items[condition->boolean ? 1 : 2], env);
    }
    if (equal(e->kind, "let")) {
        ValueEnv *inner = eval_group(evaluator, e->group, env);
        return eval_expression(evaluator, e->children.items[0], inner);
    }
    if (equal(e->kind, "pair") || equal(e->kind, "list")) {
        Value *value = make_value(e->kind);
        for (int i = 0; i < e->children.count; ++i) {
            Value *child = eval_expression(evaluator, e->children.items[i], env);
            PUSH(value->items, child);
        }
        return value;
    }
    if (equal(e->kind, "match")) {
        Value *value = eval_expression(evaluator, e->children.items[0], env);
        for (int i = 0; i < e->arms.count; ++i) {
            Arm arm = e->arms.items[i];
            ValueEnv *bindings = NULL;
            if (pattern(arm.pattern, value, &bindings)) {
                ValueEnv *inner = env;
                for (ValueEnv *at = bindings; at; at = at->next)
                    inner = value_add(inner, at->name, at->value);
                return eval_expression(evaluator, arm.body, inner);
            }
        }
        runtime_fail(evaluator, e->position, "match failure");
    }
    Value *left = eval_expression(evaluator, e->children.items[0], env);
    const char *op = e->token.kind;
    Position position = e->token.position;
    if (equal(op, "&&"))
        return !left->boolean ? left : eval_expression(evaluator, e->children.items[1], env);
    if (equal(op, "||"))
        return left->boolean ? left : eval_expression(evaluator, e->children.items[1], env);
    Value *right = eval_expression(evaluator, e->children.items[1], env);
    if (equal(op, "+"))
        return integer(evaluator, left->integer + right->integer, position);
    if (equal(op, "-"))
        return integer(evaluator, left->integer - right->integer, position);
    if (equal(op, "*"))
        return integer(evaluator, left->integer * right->integer, position);
    if (equal(op, "/") || equal(op, "mod")) {
        if (!right->integer)
            runtime_fail(evaluator, position, "division by zero");
        int64_t quotient = left->integer / right->integer;
        return integer(evaluator,
                       equal(op, "/") ? quotient : left->integer - right->integer * quotient,
                       position);
    }
    if (equal(op, "^")) {
        Value *value = make_value("string");
        value->text = ml_format("%s%s", left->text, right->text);
        return value;
    }
    if (equal(op, "::")) {
        Value *value = make_value("list");
        PUSH(value->items, left);
        for (int i = 0; i < right->items.count; ++i)
            PUSH(value->items, right->items.items[i]);
        return value;
    }
    int order = compare(evaluator, left, right, position);
    Value *value = make_value("boolean");
    if (equal(op, "="))
        value->boolean = order == 0;
    else if (equal(op, "<>"))
        value->boolean = order != 0;
    else if (equal(op, "<"))
        value->boolean = order < 0;
    else if (equal(op, ">"))
        value->boolean = order > 0;
    else if (equal(op, "<="))
        value->boolean = order <= 0;
    else
        value->boolean = order >= 0;
    return value;
}
