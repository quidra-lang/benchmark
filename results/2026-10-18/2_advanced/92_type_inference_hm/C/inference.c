#include "ml.h"
void type_fail(Inferencer *inference, const char *kind, const char *name, Position position,
               Type *expected, Type *found) {
    inference->error.kind = kind;
    inference->error.name = name;
    inference->error.position = position;
    inference->error.expected = expected;
    inference->error.found = found;
    longjmp(inference->jump, 1);
}
void infer_check(Inferencer *inference, Type *expected, Type *found, Position position) {
    UnificationFailure failure = unify(expected, found, false);
    if (failure.failed) {
        inference->error.failure = failure;
        type_fail(inference, "check", NULL, position, expected, found);
    }
}
static Type *infer_pattern(Inferencer *inference, Expr *p, TypeEnv **names) {
    if (equal(p->kind, "wildcard"))
        return fresh();
    if (equal(p->kind, "name")) {
        if (type_lookup(*names, p->value))
            type_fail(inference, "duplicate_pattern", p->value, p->position, NULL, NULL);
        Type *alpha = fresh();
        *names = type_add(*names, p->value, (Scheme){alpha, {0}});
        return alpha;
    }
    if (equal(p->kind, "integer"))
        return primitive(TYPE_INT);
    if (equal(p->kind, "boolean"))
        return primitive(TYPE_BOOL);
    if (equal(p->kind, "string"))
        return primitive(TYPE_STRING);
    if (equal(p->kind, "pair")) {
        Type *first = infer_pattern(inference, p->children.items[0], names);
        Type *second = infer_pattern(inference, p->children.items[1], names);
        return construct(TYPE_PAIR, first, second);
    }
    Type *alpha = fresh();
    Type *list = construct(TYPE_LIST, alpha, NULL);
    if (equal(p->kind, "cons")) {
        Type *first = infer_pattern(inference, p->children.items[0], names);
        infer_check(inference, alpha, first, p->children.items[0]->position);
        Type *second = infer_pattern(inference, p->children.items[1], names);
        infer_check(inference, list, second, p->children.items[1]->position);
    } else
        for (int i = 0; i < p->children.count; ++i) {
            Expr *child = p->children.items[i];
            Type *value = infer_pattern(inference, child, names);
            infer_check(inference, alpha, value, child->position);
        }
    return list;
}
Type *infer_expression(Inferencer *inference, Expr *e, TypeEnv *env) {
    Type *result = NULL;
    if (equal(e->kind, "integer"))
        result = primitive(TYPE_INT);
    else if (equal(e->kind, "string"))
        result = primitive(TYPE_STRING);
    else if (equal(e->kind, "boolean"))
        result = primitive(TYPE_BOOL);
    else if (equal(e->kind, "name")) {
        TypeEnv *found = type_lookup(env, e->value);
        if (!found) {
            for (TypeEnv *at = env; at; at = at->next)
                PUSH(inference->error.candidates, (char *)at->name);
            type_fail(inference, "unbound", e->value, e->position, NULL, NULL);
        }
        result = instantiate(found->scheme);
    } else if (equal(e->kind, "fun")) {
        Type *alpha = fresh();
        TypeEnv *inner = env;
        if (!equal(e->token.spelling, "_"))
            inner = type_add(inner, e->token.spelling, (Scheme){alpha, {0}});
        Type *body = infer_expression(inference, e->children.items[0], inner);
        result = construct(TYPE_FUNCTION, alpha, body);
    } else if (equal(e->kind, "apply")) {
        Type *function = resolve(infer_expression(inference, e->children.items[0], env));
        if (function->kind == TYPE_VAR) {
            Type *alpha = fresh();
            Type *beta = fresh();
            function->binding = construct(TYPE_FUNCTION, alpha, beta);
            function = resolve(function);
        }
        if (function->kind != TYPE_FUNCTION)
            type_fail(inference, "not_function", NULL, e->children.items[0]->position, NULL,
                      function);
        Type *argument = infer_expression(inference, e->children.items[1], env);
        infer_check(inference, function->first, argument, e->children.items[1]->position);
        result = function->second;
    } else if (equal(e->kind, "binary")) {
        Type *left, *right, *value;
        const char *op = e->token.kind;
        if (word_in("+ - * / mod", op))
            left = right = value = primitive(TYPE_INT);
        else if (equal(op, "^"))
            left = right = value = primitive(TYPE_STRING);
        else if (equal(op, "&&") || equal(op, "||"))
            left = right = value = primitive(TYPE_BOOL);
        else if (equal(op, "::")) {
            left = fresh();
            right = value = construct(TYPE_LIST, left, NULL);
        } else {
            left = right = fresh();
            value = primitive(TYPE_BOOL);
        }
        Type *first = infer_expression(inference, e->children.items[0], env);
        infer_check(inference, left, first, e->children.items[0]->position);
        Type *second = infer_expression(inference, e->children.items[1], env);
        infer_check(inference, right, second, e->children.items[1]->position);
        result = value;
    } else if (equal(e->kind, "negate")) {
        Type *value = infer_expression(inference, e->children.items[0], env);
        infer_check(inference, primitive(TYPE_INT), value, e->children.items[0]->position);
        result = primitive(TYPE_INT);
    } else if (equal(e->kind, "if")) {
        Type *condition = infer_expression(inference, e->children.items[0], env);
        infer_check(inference, primitive(TYPE_BOOL), condition, e->children.items[0]->position);
        Type *yes = infer_expression(inference, e->children.items[1], env);
        Type *no = infer_expression(inference, e->children.items[2], env);
        infer_check(inference, yes, no, e->children.items[2]->position);
        result = yes;
    } else if (equal(e->kind, "pair")) {
        Type *first = infer_expression(inference, e->children.items[0], env);
        Type *second = infer_expression(inference, e->children.items[1], env);
        result = construct(TYPE_PAIR, first, second);
    } else if (equal(e->kind, "list")) {
        Type *alpha = fresh();
        for (int i = 0; i < e->children.count; ++i) {
            Expr *child = e->children.items[i];
            Type *value = infer_expression(inference, child, env);
            infer_check(inference, alpha, value, child->position);
        }
        result = construct(TYPE_LIST, alpha, NULL);
    } else if (equal(e->kind, "match")) {
        Type *matched = infer_expression(inference, e->children.items[0], env);
        Type *rho = fresh();
        for (int i = 0; i < e->arms.count; ++i) {
            Arm arm = e->arms.items[i];
            TypeEnv *names = NULL;
            Type *pat = infer_pattern(inference, arm.pattern, &names);
            infer_check(inference, matched, pat, arm.pattern->position);
            TypeEnv *inner = env;
            for (TypeEnv *at = names; at; at = at->next)
                inner = type_add(inner, at->name, at->scheme);
            Type *body = infer_expression(inference, arm.body, inner);
            infer_check(inference, rho, body, arm.body->position);
        }
        result = rho;
    } else if (equal(e->kind, "let")) {
        TypeEnv *inner = infer_group(inference, e->group, env, true);
        result = infer_expression(inference, e->children.items[0], inner);
    }
    e->inferred = result;
    return result;
}
TypeEnv *infer_group(Inferencer *inference, Group *group, TypeEnv *env, bool local) {
    for (int i = 0; i < group->bindings.count; ++i) {
        Binding *binding = group->bindings.items[i];
        for (int j = 0; j < i; ++j)
            if (equal(binding->name.spelling, group->bindings.items[j]->name.spelling))
                type_fail(inference, "duplicate_let", binding->name.spelling,
                          binding->name.position, NULL, NULL);
        if (group->recursive && !equal(binding->expr->kind, "fun"))
            type_fail(inference, "recursive_function", binding->name.spelling,
                      binding->name.position, NULL, NULL);
    }
    TypeEnv *inner = env;
    TypeList types = {0};
    if (group->recursive)
        for (int i = 0; i < group->bindings.count; ++i) {
            Type *alpha = fresh();
            PUSH(types, alpha);
            inner = type_add(inner, group->bindings.items[i]->name.spelling, (Scheme){alpha, {0}});
        }
    for (int i = 0; i < group->bindings.count; ++i) {
        Binding *binding = group->bindings.items[i];
        Type *type = infer_expression(inference, binding->expr, inner);
        if (group->recursive)
            infer_check(inference, types.items[i], type, binding->name.position);
        else
            PUSH(types, type);
    }
    TypeEnv *result = env;
    for (int i = 0; i < group->bindings.count; ++i) {
        Binding *binding = group->bindings.items[i];
        binding->scheme = generalize(types.items[i], env);
        result = type_add(result, binding->name.spelling, binding->scheme);
    }
    if (local)
        for (int i = 0; i < group->bindings.count; ++i)
            PUSH(inference->locals, group->bindings.items[i]);
    return result;
}
