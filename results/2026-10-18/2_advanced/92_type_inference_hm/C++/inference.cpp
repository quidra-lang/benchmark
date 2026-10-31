#include "ml.hpp"
void Inferencer::check(Type *expected, Type *found, const Position &position) {
    std::optional<UnificationFailure> failure = unify(expected, found);
    if (failure)
        throw TypeError{"check", "", position, expected, found, failure, {}};
}
Type *Inferencer::expression(Expr *e, const TypeEnv &env) {
    Type *result = nullptr;
    if (e->kind == "integer")
        result = primitive("int");
    else if (e->kind == "string")
        result = primitive("string");
    else if (e->kind == "boolean")
        result = primitive("bool");
    else if (e->kind == "name") {
        auto found = env.find(e->value);
        if (found == env.end()) {
            TypeError error;
            error.kind = "unbound";
            error.name = e->value;
            error.position = e->position;
            for (const auto &entry : env)
                error.candidates.push_back(entry.first);
            throw error;
        }
        result = instantiate(found->second);
    } else if (e->kind == "fun") {
        Type *alpha = fresh();
        TypeEnv inner = env;
        if (e->token.spelling != "_")
            inner[e->token.spelling] = {alpha, {}};
        Type *body = expression(e->children[0], inner);
        result = construct("function", {alpha, body});
    } else if (e->kind == "apply") {
        Type *function = resolve(expression(e->children[0], env));
        if (function->kind == "var") {
            Type *argument = fresh();
            Type *value = fresh();
            function->binding = construct("function", {argument, value});
            function = resolve(function);
        }
        if (function->kind != "function")
            throw TypeError{"not_function", "", e->children[0]->position, nullptr, function,
                            std::nullopt,   {}};
        Type *argument = expression(e->children[1], env);
        check(function->children[0], argument, e->children[1]->position);
        result = function->children[1];
    } else if (e->kind == "binary") {
        Type *left = nullptr, *right = nullptr, *value = nullptr;
        const std::string &op = e->token.kind;
        if (word_in("+ - * / mod", op))
            left = right = value = primitive("int");
        else if (op == "^")
            left = right = value = primitive("string");
        else if (op == "&&" || op == "||")
            left = right = value = primitive("bool");
        else if (op == "::") {
            left = fresh();
            right = value = construct("list", {left});
        } else {
            left = right = fresh();
            value = primitive("bool");
        }
        Type *first = expression(e->children[0], env);
        check(left, first, e->children[0]->position);
        Type *second = expression(e->children[1], env);
        check(right, second, e->children[1]->position);
        result = value;
    } else if (e->kind == "negate") {
        Type *value = expression(e->children[0], env);
        check(primitive("int"), value, e->children[0]->position);
        result = primitive("int");
    } else if (e->kind == "if") {
        Type *condition = expression(e->children[0], env);
        check(primitive("bool"), condition, e->children[0]->position);
        Type *yes = expression(e->children[1], env);
        Type *no = expression(e->children[2], env);
        check(yes, no, e->children[2]->position);
        result = yes;
    } else if (e->kind == "pair") {
        Type *first = expression(e->children[0], env);
        Type *second = expression(e->children[1], env);
        result = construct("pair", {first, second});
    } else if (e->kind == "list") {
        Type *alpha = fresh();
        for (Expr *child : e->children) {
            Type *value = expression(child, env);
            check(alpha, value, child->position);
        }
        result = construct("list", {alpha});
    } else if (e->kind == "match") {
        Type *matched = expression(e->children[0], env);
        Type *rho = fresh();
        for (const Arm &arm : e->arms) {
            std::map<std::string, Type *> names;
            Type *pat = pattern(arm.pattern, names);
            check(matched, pat, arm.pattern->position);
            TypeEnv inner = env;
            for (const auto &name : names)
                inner[name.first] = {name.second, {}};
            Type *body = expression(arm.body, inner);
            check(rho, body, arm.body->position);
        }
        result = rho;
    } else if (e->kind == "let") {
        TypeEnv inner = group(e->group, env, true);
        result = expression(e->children[0], inner);
    }
    e->inferred = result;
    return result;
}
Type *Inferencer::pattern(Expr *p, std::map<std::string, Type *> &names) {
    if (p->kind == "wildcard")
        return fresh();
    if (p->kind == "name") {
        if (names.count(p->value))
            throw TypeError{"duplicate_pattern", p->value, p->position};
        Type *type = fresh();
        names[p->value] = type;
        return type;
    }
    if (p->kind == "integer")
        return primitive("int");
    if (p->kind == "boolean")
        return primitive("bool");
    if (p->kind == "string")
        return primitive("string");
    if (p->kind == "pair") {
        Type *first = pattern(p->children[0], names);
        Type *second = pattern(p->children[1], names);
        return construct("pair", {first, second});
    }
    Type *alpha = fresh();
    Type *list = construct("list", {alpha});
    if (p->kind == "cons") {
        Type *first = pattern(p->children[0], names);
        check(alpha, first, p->children[0]->position);
        Type *second = pattern(p->children[1], names);
        check(list, second, p->children[1]->position);
    } else
        for (Expr *child : p->children) {
            Type *type = pattern(child, names);
            check(alpha, type, child->position);
        }
    return list;
}
TypeEnv Inferencer::group(Group *group, const TypeEnv &env, bool local) {
    std::set<std::string> seen;
    for (Binding *binding : group->bindings) {
        const std::string &name = binding->name.spelling;
        if (!seen.insert(name).second)
            throw TypeError{"duplicate_let", name, binding->name.position};
        if (group->rec && binding->expr->kind != "fun")
            throw TypeError{"recursive_function", name, binding->name.position};
    }
    TypeEnv inference_env = env;
    std::vector<Type *> types;
    if (group->rec)
        for (Binding *binding : group->bindings) {
            Type *alpha = fresh();
            types.push_back(alpha);
            inference_env[binding->name.spelling] = {alpha, {}};
        }
    for (size_t i = 0; i < group->bindings.size(); ++i) {
        Binding *binding = group->bindings[i];
        Type *type = expression(binding->expr, inference_env);
        if (group->rec)
            check(types[i], type, binding->name.position);
        else
            types.push_back(type);
    }
    TypeEnv result = env;
    for (size_t i = 0; i < types.size(); ++i) {
        Binding *binding = group->bindings[i];
        binding->scheme = generalize(types[i], env);
        result[binding->name.spelling] = binding->scheme;
    }
    if (local)
        locals.insert(locals.end(), group->bindings.begin(), group->bindings.end());
    return result;
}
