#include "ml.hpp"
namespace {
std::vector<std::unique_ptr<Value>> values;
}
Value *make_value(const std::string &kind) {
    values.push_back(std::make_unique<Value>());
    Value *result = values.back().get();
    result->kind = kind;
    return result;
}
Value *lookup(Environment env, const std::string &name) {
    while (env) {
        auto found = env->bindings.find(name);
        if (found != env->bindings.end())
            return found->second;
        env = env->parent;
    }
    return nullptr;
}
Environment extend(Environment parent, std::map<std::string, Value *> bindings) {
    auto result = std::make_shared<ValueEnv>();
    result->parent = std::move(parent);
    result->bindings = std::move(bindings);
    return result;
}
Value *Evaluator::integer(int64_t value, const Position &position) {
    if (value < -2147483648LL || value > 2147483647LL)
        throw RuntimeError{position, "integer overflow"};
    Value *result = make_value("integer");
    result->integer = value;
    return result;
}
Value *Evaluator::apply(Value *function, Value *argument, const Position &position) {
    ++calls;
    if (!function->builtin.empty())
        return apply_builtin(function->builtin, argument, position);
    std::map<std::string, Value *> binding;
    if (function->parameter.spelling != "_")
        binding[function->parameter.spelling] = argument;
    return expression(function->body, extend(function->environment, std::move(binding)));
}
int Evaluator::compare(Value *left, Value *right, const Position &position) {
    if (left->kind == "function")
        throw RuntimeError{position, "functional value compared"};
    if (left->kind == "integer")
        return (left->integer > right->integer) - (left->integer < right->integer);
    if (left->kind == "boolean")
        return static_cast<int>(left->boolean) - static_cast<int>(right->boolean);
    if (left->kind == "string")
        return (left->text > right->text) - (left->text < right->text);
    for (size_t i = 0; i < std::min(left->items.size(), right->items.size()); ++i) {
        int order = compare(left->items[i], right->items[i], position);
        if (order)
            return order;
    }
    return (left->items.size() > right->items.size()) - (left->items.size() < right->items.size());
}
bool Evaluator::pattern(Expr *p, Value *value, std::map<std::string, Value *> &bindings) {
    if (p->kind == "wildcard")
        return true;
    if (p->kind == "name") {
        bindings[p->value] = value;
        return true;
    }
    if (p->kind == "integer")
        return p->integer == value->integer;
    if (p->kind == "boolean")
        return (p->value == "true") == value->boolean;
    if (p->kind == "string")
        return p->value == value->text;
    if (p->kind == "cons") {
        if (value->items.empty())
            return false;
        if (!pattern(p->children[0], value->items[0], bindings))
            return false;
        Value *tail = make_value("list");
        tail->items.assign(value->items.begin() + 1, value->items.end());
        return pattern(p->children[1], tail, bindings);
    }
    if (p->children.size() != value->items.size())
        return false;
    for (size_t i = 0; i < p->children.size(); ++i)
        if (!pattern(p->children[i], value->items[i], bindings))
            return false;
    return true;
}
Environment Evaluator::group(Group *group, Environment env) {
    auto result = std::make_shared<ValueEnv>();
    result->parent = env;
    for (Binding *binding : group->bindings) {
        Value *value;
        if (group->rec) {
            value = make_value("function");
            value->parameter = binding->expr->token;
            value->body = binding->expr->children[0];
            value->environment = result;
        } else
            value = expression(binding->expr, env);
        result->bindings[binding->name.spelling] = value;
    }
    return result;
}
Value *Evaluator::expression(Expr *e, Environment env) {
    if (e->kind == "integer")
        return integer(e->integer, e->position);
    if (e->kind == "string") {
        Value *value = make_value("string");
        value->text = e->value;
        return value;
    }
    if (e->kind == "boolean") {
        Value *value = make_value("boolean");
        value->boolean = e->value == "true";
        return value;
    }
    if (e->kind == "name")
        return lookup(env, e->value);
    if (e->kind == "fun") {
        Value *value = make_value("function");
        value->parameter = e->token;
        value->body = e->children[0];
        value->environment = env;
        return value;
    }
    if (e->kind == "apply") {
        Value *function = expression(e->children[0], env);
        Value *argument = expression(e->children[1], env);
        return apply(function, argument, e->position);
    }
    if (e->kind == "negate") {
        Value *value = expression(e->children[0], env);
        return integer(-value->integer, e->token.position);
    }
    if (e->kind == "if") {
        Value *condition = expression(e->children[0], env);
        return expression(e->children[condition->boolean ? 1 : 2], env);
    }
    if (e->kind == "let") {
        Environment inner = group(e->group, env);
        return expression(e->children[0], inner);
    }
    if (e->kind == "pair" || e->kind == "list") {
        Value *value = make_value(e->kind);
        for (Expr *child : e->children)
            value->items.push_back(expression(child, env));
        return value;
    }
    if (e->kind == "match") {
        Value *matched = expression(e->children[0], env);
        for (const Arm &arm : e->arms) {
            std::map<std::string, Value *> bindings;
            if (pattern(arm.pattern, matched, bindings))
                return expression(arm.body, extend(env, std::move(bindings)));
        }
        throw RuntimeError{e->position, "match failure"};
    }
    Value *left = expression(e->children[0], env);
    const std::string &op = e->token.kind;
    const Position &position = e->token.position;
    if (op == "&&") {
        if (!left->boolean)
            return left;
        return expression(e->children[1], env);
    }
    if (op == "||") {
        if (left->boolean)
            return left;
        return expression(e->children[1], env);
    }
    Value *right = expression(e->children[1], env);
    if (op == "+")
        return integer(left->integer + right->integer, position);
    if (op == "-")
        return integer(left->integer - right->integer, position);
    if (op == "*")
        return integer(left->integer * right->integer, position);
    if (op == "/" || op == "mod") {
        if (right->integer == 0)
            throw RuntimeError{position, "division by zero"};
        int64_t quotient = left->integer / right->integer;
        return integer(op == "/" ? quotient : left->integer - right->integer * quotient, position);
    }
    if (op == "^") {
        Value *value = make_value("string");
        value->text = left->text + right->text;
        return value;
    }
    if (op == "::") {
        Value *value = make_value("list");
        value->items.push_back(left);
        value->items.insert(value->items.end(), right->items.begin(), right->items.end());
        return value;
    }
    int order = compare(left, right, position);
    Value *value = make_value("boolean");
    if (op == "=")
        value->boolean = order == 0;
    else if (op == "<>")
        value->boolean = order != 0;
    else if (op == "<")
        value->boolean = order < 0;
    else if (op == ">")
        value->boolean = order > 0;
    else if (op == "<=")
        value->boolean = order <= 0;
    else
        value->boolean = order >= 0;
    return value;
}
