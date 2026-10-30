#include "ml.h"
Type *construct(TypeKind kind, Type *first, Type *second) {
    Type *result = ml_alloc(sizeof(*result));
    result->kind = kind;
    result->first = first;
    result->second = second;
    return result;
}
Type *fresh(void) { return construct(TYPE_VAR, NULL, NULL); }
Type *primitive(TypeKind kind) {
    static Type *types[7];
    if (!types[kind])
        types[kind] = construct(kind, NULL, NULL);
    return types[kind];
}
Type *resolve(Type *type) {
    if (type->kind == TYPE_VAR && type->binding) {
        type->binding = resolve(type->binding);
        return type->binding;
    }
    return type;
}
static bool occurs(Type *variable, Type *type) {
    type = resolve(type);
    return type == variable || (type->first && occurs(variable, type->first)) ||
           (type->second && occurs(variable, type->second));
}
UnificationFailure unify(Type *expected, Type *found, bool nested) {
    expected = resolve(expected);
    found = resolve(found);
    UnificationFailure success = {0};
    if (expected == found)
        return success;
    if (expected->kind == TYPE_VAR) {
        if (occurs(expected, found))
            return (UnificationFailure){expected, found, true, nested, true};
        expected->binding = found;
        return success;
    }
    if (found->kind == TYPE_VAR) {
        if (occurs(found, expected))
            return (UnificationFailure){expected, found, true, nested, true};
        found->binding = expected;
        return success;
    }
    if (expected->kind != found->kind)
        return (UnificationFailure){expected, found, false, nested, true};
    if (expected->first) {
        UnificationFailure failure = unify(expected->first, found->first, true);
        if (failure.failed)
            return failure;
    }
    if (expected->second)
        return unify(expected->second, found->second, true);
    return success;
}
bool type_member(TypeList variables, Type *type) {
    for (int i = 0; i < variables.count; ++i)
        if (variables.items[i] == type)
            return true;
    return false;
}
static void free_walk(Type *type, TypeList *result) {
    type = resolve(type);
    if (type->kind == TYPE_VAR) {
        if (!type_member(*result, type))
            PUSH(*result, type);
        return;
    }
    if (type->first)
        free_walk(type->first, result);
    if (type->second)
        free_walk(type->second, result);
}
TypeList free_variables(Type *type) {
    TypeList result = {0};
    free_walk(type, &result);
    return result;
}
TypeEnv *type_add(TypeEnv *env, const char *name, Scheme scheme) {
    TypeEnv *entry = ml_alloc(sizeof(*entry));
    entry->name = name;
    entry->scheme = scheme;
    entry->next = env;
    return entry;
}
TypeEnv *type_lookup(TypeEnv *env, const char *name) {
    for (; env; env = env->next)
        if (equal(env->name, name))
            return env;
    return NULL;
}
Scheme generalize(Type *type, TypeEnv *env) {
    Scheme result = {type, free_variables(type)};
    StringList seen = {0};
    for (; env; env = env->next) {
        bool hidden = false;
        for (int i = 0; i < seen.count; ++i)
            if (equal(seen.items[i], env->name))
                hidden = true;
        if (hidden)
            continue;
        PUSH(seen, (char *)env->name);
        TypeList variables = free_variables(env->scheme.type);
        for (int i = 0; i < variables.count; ++i)
            if (!type_member(env->scheme.quantified, variables.items[i]))
                for (int j = 0; j < result.quantified.count; ++j)
                    if (result.quantified.items[j] == variables.items[i]) {
                        memmove(result.quantified.items + j, result.quantified.items + j + 1,
                                (size_t)(result.quantified.count - j - 1) * sizeof(Type *));
                        --result.quantified.count;
                        break;
                    }
    }
    return result;
}
static Type *instantiate_copy(Type *type, Scheme scheme, TypeList *original,
                              TypeList *replacement) {
    type = resolve(type);
    if (type->kind == TYPE_VAR) {
        if (!type_member(scheme.quantified, type))
            return type;
        for (int i = 0; i < original->count; ++i)
            if (original->items[i] == type)
                return replacement->items[i];
        Type *next = fresh();
        PUSH(*original, type);
        PUSH(*replacement, next);
        return next;
    }
    Type *first = type->first ? instantiate_copy(type->first, scheme, original, replacement) : NULL;
    Type *second =
        type->second ? instantiate_copy(type->second, scheme, original, replacement) : NULL;
    return construct(type->kind, first, second);
}
Type *instantiate(Scheme scheme) {
    TypeList original = {0}, replacement = {0};
    return instantiate_copy(scheme.type, scheme, &original, &replacement);
}
