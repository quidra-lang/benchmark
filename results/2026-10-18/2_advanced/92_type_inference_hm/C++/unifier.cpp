#include "ml.hpp"
namespace {
std::vector<std::unique_ptr<Type>> types;
}
Type *construct(const std::string &kind, std::vector<Type *> children) {
    types.push_back(std::make_unique<Type>());
    Type *result = types.back().get();
    result->kind = kind;
    result->children = std::move(children);
    return result;
}
Type *fresh() { return construct("var"); }
Type *primitive(const std::string &kind) {
    static std::map<std::string, Type *> primitives;
    if (!primitives.count(kind))
        primitives[kind] = construct(kind);
    return primitives[kind];
}
Type *resolve(Type *type) {
    if (type->kind == "var" && type->binding) {
        type->binding = resolve(type->binding);
        return type->binding;
    }
    return type;
}
static bool occurs(Type *variable, Type *type) {
    type = resolve(type);
    if (type == variable)
        return true;
    for (Type *child : type->children)
        if (occurs(variable, child))
            return true;
    return false;
}
std::optional<UnificationFailure> unify(Type *expected, Type *found, bool nested) {
    expected = resolve(expected);
    found = resolve(found);
    if (expected == found)
        return std::nullopt;
    if (expected->kind == "var") {
        if (occurs(expected, found))
            return UnificationFailure{expected, found, true, nested};
        expected->binding = found;
        return std::nullopt;
    }
    if (found->kind == "var") {
        if (occurs(found, expected))
            return UnificationFailure{expected, found, true, nested};
        found->binding = expected;
        return std::nullopt;
    }
    if (expected->kind != found->kind)
        return UnificationFailure{expected, found, false, nested};
    for (size_t i = 0; i < expected->children.size(); ++i) {
        std::optional<UnificationFailure> failure =
            unify(expected->children[i], found->children[i], true);
        if (failure)
            return failure;
    }
    return std::nullopt;
}
std::set<Type *> free_variables(Type *type) {
    type = resolve(type);
    if (type->kind == "var")
        return {type};
    std::set<Type *> result;
    for (Type *child : type->children) {
        std::set<Type *> vars = free_variables(child);
        result.insert(vars.begin(), vars.end());
    }
    return result;
}
Scheme generalize(Type *type, const TypeEnv &env) {
    Scheme result{type, free_variables(type)};
    for (const auto &entry : env)
        for (Type *variable : free_variables(entry.second.type))
            if (!entry.second.quantified.count(variable))
                result.quantified.erase(variable);
    return result;
}
Type *instantiate(const Scheme &scheme) {
    std::map<Type *, Type *> replacements;
    std::function<Type *(Type *)> copy = [&](Type *type) -> Type * {
        type = resolve(type);
        if (type->kind == "var") {
            if (!scheme.quantified.count(type))
                return type;
            if (!replacements.count(type))
                replacements[type] = fresh();
            return replacements[type];
        }
        std::vector<Type *> children;
        for (Type *child : type->children)
            children.push_back(copy(child));
        return construct(type->kind, std::move(children));
    };
    return copy(scheme.type);
}
