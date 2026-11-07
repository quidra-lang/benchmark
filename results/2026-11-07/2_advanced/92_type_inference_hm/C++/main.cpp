#include "ml.hpp"
struct TypePrinter {
    std::map<Type *, std::string> names;
    std::set<Type *> quantified;
    bool local = false;
    std::string print(Type *type) {
        type = resolve(type);
        if (type->kind == "var") {
            auto found = names.find(type);
            if (found != names.end())
                return found->second;
            size_t index = names.size();
            std::string name = local && !quantified.count(type) ? "'_" : "'";
            name += static_cast<char>('a' + index % 26);
            if (index >= 26)
                name += std::to_string(index / 26);
            names[type] = name;
            return name;
        }
        if (word_in("int bool string", type->kind))
            return type->kind;
        Type *first = resolve(type->children[0]);
        std::string left = print(first);
        if (type->kind == "list") {
            if (first->kind == "pair" || first->kind == "function")
                left = "(" + left + ")";
            return left + " list";
        }
        Type *second = resolve(type->children[1]);
        std::string right = print(second);
        if (type->kind == "pair") {
            if (first->kind == "pair" || first->kind == "function")
                left = "(" + left + ")";
            if (second->kind == "pair" || second->kind == "function")
                right = "(" + right + ")";
            return left + " * " + right;
        }
        if (first->kind == "function")
            left = "(" + left + ")";
        return left + " -> " + right;
    }
};
static Type *signature_type(Expr *e, std::map<std::string, Type *> &variables) {
    if (e->kind == "type_variable") {
        if (!variables.count(e->value))
            variables[e->value] = fresh();
        return variables[e->value];
    }
    std::vector<Type *> children;
    for (Expr *child : e->children)
        children.push_back(signature_type(child, variables));
    return construct(e->kind, std::move(children));
}
static bool identical_types(Type *left, Type *right) {
    left = resolve(left);
    right = resolve(right);
    if (left->kind == "var" || right->kind == "var")
        return left == right;
    if (left->kind != right->kind)
        return false;
    for (size_t i = 0; i < left->children.size(); ++i)
        if (!identical_types(left->children[i], right->children[i]))
            return false;
    return true;
}
static bool signature_matches(Type *inferred, Type *declared,
                              std::map<Type *, Type *> &assignments) {
    inferred = resolve(inferred);
    declared = resolve(declared);
    if (inferred->kind == "var") {
        auto found = assignments.find(inferred);
        if (found != assignments.end())
            return identical_types(found->second, declared);
        assignments[inferred] = declared;
        return true;
    }
    if (declared->kind == "var" || inferred->kind != declared->kind)
        return false;
    for (size_t i = 0; i < inferred->children.size(); ++i)
        if (!signature_matches(inferred->children[i], declared->children[i], assignments))
            return false;
    return true;
}
static void check_signatures(Group *group, const std::vector<std::optional<Item>> &signatures) {
    for (size_t i = 0; i < group->bindings.size(); ++i)
        if (signatures[i]) {
            Binding *binding = group->bindings[i];
            std::map<std::string, Type *> variables;
            Type *declared = signature_type(signatures[i]->declared, variables);
            std::map<Type *, Type *> assignments;
            if (!signature_matches(binding->scheme.type, declared, assignments))
                throw TypeError{"signature", binding->name.spelling, binding->name.position,
                                binding->scheme.type, declared};
            binding->scheme = {declared, free_variables(declared)};
        }
}
static int edit_distance(const std::string &left, const std::string &right) {
    std::vector<int> previous(right.size() + 1);
    for (size_t j = 0; j < previous.size(); ++j)
        previous[j] = static_cast<int>(j);
    for (size_t i = 0; i < left.size(); ++i) {
        std::vector<int> current(right.size() + 1);
        current[0] = static_cast<int>(i) + 1;
        for (size_t j = 0; j < right.size(); ++j)
            current[j + 1] = std::min(
                {current[j] + 1, previous[j + 1] + 1, previous[j] + (left[i] != right[j])});
        previous = std::move(current);
    }
    return previous.back();
}
static std::string type_error_message(const TypeError &error) {
    TypePrinter printer;
    if (error.kind == "unbound") {
        std::string message = "unbound variable '" + error.name + "'", best;
        int best_distance = 3;
        for (const std::string &candidate : error.candidates) {
            int distance = edit_distance(error.name, candidate);
            if (distance <= 2 && distance < static_cast<int>(error.name.size()) &&
                (distance < best_distance ||
                 (distance == best_distance && (best.empty() || candidate < best)))) {
                best = candidate;
                best_distance = distance;
            }
        }
        if (!best.empty())
            message += " (did you mean '" + best + "'?)";
        return message;
    }
    if (error.kind == "not_function")
        return "expected a function but found " + printer.print(error.found);
    if (error.kind == "duplicate_pattern")
        return "variable '" + error.name + "' is bound twice in this pattern";
    if (error.kind == "duplicate_let")
        return "variable '" + error.name + "' is bound twice in this let";
    if (error.kind == "recursive_function")
        return "'" + error.name + "' in let rec must be a function";
    std::string expected = printer.print(error.expected);
    std::string found = printer.print(error.found);
    if (error.kind == "signature")
        return "'" + error.name + "' has type " + expected + " but its signature is " + found;
    std::string message = "expected " + expected + " but found " + found;
    const UnificationFailure &failure = *error.failure;
    if (failure.infinite) {
        Type *variable = failure.expected;
        Type *value = failure.found;
        if (variable->kind != "var")
            std::swap(variable, value);
        std::string name = printer.print(variable);
        std::string type = printer.print(value);
        message += " (infinite type " + name + " = " + type + ")";
    } else if (failure.nested) {
        std::string left = printer.print(failure.expected);
        std::string right = printer.print(failure.found);
        message += " (" + left + " vs " + right + ")";
    }
    return message;
}
std::string quote_string(const std::string &text) {
    std::string result = "\"";
    for (char c : text) {
        if (c == '\\')
            result += "\\\\";
        else if (c == '"')
            result += "\\\"";
        else if (c == '\n')
            result += "\\n";
        else if (c == '\t')
            result += "\\t";
        else
            result += c;
    }
    return result + "\"";
}
std::string print_value(Value *value) {
    if (value->kind == "integer")
        return std::to_string(value->integer);
    if (value->kind == "boolean")
        return value->boolean ? "true" : "false";
    if (value->kind == "string")
        return quote_string(value->text);
    if (value->kind == "pair") {
        std::string first = print_value(value->items[0]);
        std::string second = print_value(value->items[1]);
        return "(" + first + ", " + second + ")";
    }
    if (value->kind == "list") {
        std::string result = "[";
        for (size_t i = 0; i < value->items.size(); ++i) {
            if (i)
                result += "; ";
            result += print_value(value->items[i]);
        }
        return result + "]";
    }
    return "<fun>";
}
Value *apply_builtin(const std::string &name, Value *argument, const Position &position) {
    if (name == "fst")
        return argument->items[0];
    if (name == "snd")
        return argument->items[1];
    if (name == "failwith")
        throw RuntimeError{position, "failure " + print_value(argument)};
    Value *result = make_value(name == "not" ? "boolean" : "string");
    if (name == "not")
        result->boolean = !argument->boolean;
    else
        result->text = std::to_string(argument->integer);
    return result;
}
static std::pair<TypeEnv, Environment> builtins() {
    TypeEnv types;
    std::map<std::string, Value *> values;
    for (const std::string &name : {std::string("fst"), std::string("snd")}) {
        Type *a = fresh();
        Type *b = fresh();
        types[name] = {construct("function", {construct("pair", {a, b}), name == "fst" ? a : b}),
                       {a, b}};
    }
    types["not"] = {construct("function", {primitive("bool"), primitive("bool")}), {}};
    types["string_of_int"] = {construct("function", {primitive("int"), primitive("string")}), {}};
    Type *a = fresh();
    types["failwith"] = {construct("function", {primitive("string"), a}), {a}};
    for (const auto &entry : types) {
        Value *value = make_value("function");
        value->builtin = entry.first;
        values[entry.first] = value;
    }
    return {types, extend(nullptr, std::move(values))};
}
static std::string declared_type(Expr *e) {
    if (e->kind == "type_variable")
        return e->value;
    if (word_in("int bool string", e->kind))
        return e->kind;
    Expr *first = e->children[0];
    std::string left = declared_type(first);
    if (e->kind == "list") {
        if (first->kind == "pair" || first->kind == "function")
            left = "(" + left + ")";
        return left + " list";
    }
    Expr *second = e->children[1];
    std::string right = declared_type(second);
    if (e->kind == "pair") {
        if (first->kind == "pair" || first->kind == "function")
            left = "(" + left + ")";
        if (second->kind == "pair" || second->kind == "function")
            right = "(" + right + ")";
        return left + " * " + right;
    }
    if (first->kind == "function")
        left = "(" + left + ")";
    return left + " -> " + right;
}
static std::string format_expression(Expr *, int = 0);
static std::pair<std::string, Expr *> parameters(Expr *e) {
    std::string result;
    while (e->kind == "fun") {
        if (!result.empty())
            result += " ";
        result += e->token.spelling;
        e = e->children[0];
    }
    return {result, e};
}
static std::string format_group(Group *group) {
    std::string result = group->rec ? "let rec " : "let ";
    for (size_t i = 0; i < group->bindings.size(); ++i) {
        if (i)
            result += " and ";
        Binding *binding = group->bindings[i];
        auto parts = parameters(binding->expr);
        result += binding->name.spelling;
        if (!parts.first.empty())
            result += " " + parts.first;
        result += " = " + format_expression(parts.second);
    }
    return result;
}
static bool ends_with_match(Expr *e) {
    if (e->kind == "match")
        return true;
    if (e->kind == "let" || e->kind == "fun")
        return ends_with_match(e->children[0]);
    if (e->kind == "if")
        return ends_with_match(e->children[2]);
    return false;
}
static std::string format_pattern(Expr *p) {
    if (p->kind == "integer")
        return std::to_string(p->integer);
    if (p->kind == "string")
        return quote_string(p->value);
    if (p->kind == "name" || p->kind == "wildcard" || p->kind == "boolean")
        return p->value;
    if (p->kind == "cons") {
        std::string left = format_pattern(p->children[0]);
        if (p->children[0]->kind == "cons")
            left = "(" + left + ")";
        return left + " :: " + format_pattern(p->children[1]);
    }
    if (p->kind == "pair")
        return "(" + format_pattern(p->children[0]) + ", " + format_pattern(p->children[1]) + ")";
    std::string result = "[";
    for (size_t i = 0; i < p->children.size(); ++i) {
        if (i)
            result += "; ";
        result += format_pattern(p->children[i]);
    }
    return result + "]";
}
static std::string format_expression(Expr *e, int required) {
    std::string text;
    int strength = 9;
    if (e->kind == "integer")
        text = std::to_string(e->integer);
    else if (e->kind == "string")
        text = quote_string(e->value);
    else if (e->kind == "name" || e->kind == "boolean")
        text = e->value;
    else if (e->kind == "pair")
        text = "(" + format_expression(e->children[0]) + ", " + format_expression(e->children[1]) +
               ")";
    else if (e->kind == "list") {
        text = "[";
        for (size_t i = 0; i < e->children.size(); ++i) {
            if (i)
                text += "; ";
            text += format_expression(e->children[i]);
        }
        text += "]";
    } else if (e->kind == "fun") {
        strength = 0;
        auto parts = parameters(e);
        text = "fun " + parts.first + " -> " + format_expression(parts.second);
    } else if (e->kind == "apply") {
        strength = 8;
        text = format_expression(e->children[0], 8) + " " + format_expression(e->children[1], 9);
    } else if (e->kind == "negate") {
        strength = 7;
        text = "-" + format_expression(e->children[0], 7);
    } else if (e->kind == "binary") {
        auto info = operator_info(e->token.kind);
        strength = info.first;
        text = format_expression(e->children[0], strength + (info.second ? 1 : 0)) + " " +
               e->token.kind + " " +
               format_expression(e->children[1], strength + (info.second ? 0 : 1));
    } else if (e->kind == "if") {
        strength = 0;
        text = "if " + format_expression(e->children[0]) + " then " +
               format_expression(e->children[1]) + " else " + format_expression(e->children[2]);
    } else if (e->kind == "let") {
        strength = 0;
        text = format_group(e->group) + " in " + format_expression(e->children[0]);
    } else if (e->kind == "match") {
        strength = 0;
        text = "match " + format_expression(e->children[0]) + " with ";
        for (size_t i = 0; i < e->arms.size(); ++i) {
            if (i)
                text += " | ";
            std::string body = format_expression(e->arms[i].body);
            if (i + 1 < e->arms.size() && ends_with_match(e->arms[i].body))
                body = "(" + body + ")";
            text += format_pattern(e->arms[i].pattern) + " -> " + body;
        }
    }
    return strength < required ? "(" + text + ")" : text;
}
static std::string format_item(const Item &item) {
    if (item.kind == "signature")
        return "val " + item.name.spelling + " : " + declared_type(item.declared) + ";;";
    if (item.kind == "declaration")
        return format_group(item.group) + ";;";
    return format_expression(item.expr) + ";;";
}
struct Cover {
    std::string tag;
    std::vector<std::shared_ptr<Cover>> children;
};
using CoveragePattern = std::shared_ptr<Cover>;
using PatternRow = std::vector<CoveragePattern>;
using PatternMatrix = std::vector<PatternRow>;
static CoveragePattern coverage_pattern(Expr *p) {
    if (p->kind == "name" || p->kind == "wildcard")
        return nullptr;
    auto result = std::make_shared<Cover>();
    if (p->kind == "integer")
        result->tag = "i:" + std::to_string(p->integer);
    else if (p->kind == "string")
        result->tag = "s:" + quote_string(p->value);
    else if (p->kind == "boolean")
        result->tag = "b:" + p->value;
    else if (p->kind == "list") {
        result->tag = "nil";
        for (auto it = p->children.rbegin(); it != p->children.rend(); ++it) {
            auto cons = std::make_shared<Cover>();
            cons->tag = "cons";
            cons->children = {coverage_pattern(*it), result};
            result = cons;
        }
    } else {
        result->tag = p->kind;
        for (Expr *child : p->children)
            result->children.push_back(coverage_pattern(child));
    }
    return result;
}
static std::vector<std::string> constructors(Type *type) {
    type = resolve(type);
    if (type->kind == "bool")
        return {"b:false", "b:true"};
    if (type->kind == "list")
        return {"nil", "cons"};
    if (type->kind == "pair")
        return {"pair"};
    return {};
}
static std::vector<Type *> constructor_types(const std::string &tag, Type *type) {
    type = resolve(type);
    if (tag == "pair")
        return type->children;
    if (tag == "cons")
        return {type->children[0], type};
    return {};
}
static PatternMatrix specialize(const PatternMatrix &matrix, const std::string &tag, size_t arity) {
    PatternMatrix result;
    for (const PatternRow &row : matrix) {
        PatternRow next;
        if (!row[0])
            next.resize(arity);
        else if (row[0]->tag == tag)
            next = row[0]->children;
        else
            continue;
        next.insert(next.end(), row.begin() + 1, row.end());
        result.push_back(std::move(next));
    }
    return result;
}
static std::string cover_code(const CoveragePattern &p) {
    if (!p)
        return "_";
    std::string result = std::to_string(p->tag.size()) + ":" + p->tag + "(";
    for (const auto &child : p->children)
        result += cover_code(child);
    return result + ")";
}
static std::string coverage_type_code(Type *type) {
    type = resolve(type);
    if (type->kind == "var" || type->kind == "function")
        return "opaque";
    std::string result = type->kind + "(";
    for (Type *child : type->children)
        result += coverage_type_code(child);
    return result + ")";
}
struct Coverage {
    std::map<std::string, bool> memo;
    bool useful(const PatternMatrix &matrix, const PatternRow &query,
                const std::vector<Type *> &types) {
        std::string key;
        for (const PatternRow &row : matrix) {
            key += "[";
            for (const auto &p : row)
                key += cover_code(p);
            key += "]";
        }
        key += "?";
        for (const auto &p : query)
            key += cover_code(p);
        key += ":";
        for (Type *type : types)
            key += coverage_type_code(type);
        auto found = memo.find(key);
        if (found != memo.end())
            return found->second;
        bool result = compute(matrix, query, types);
        memo[key] = result;
        return result;
    }
    bool compute(const PatternMatrix &matrix, const PatternRow &query,
                 const std::vector<Type *> &types) {
        if (query.empty())
            return matrix.empty();
        if (matrix.empty())
            return true;
        if (query[0]) {
            PatternRow next = query[0]->children;
            next.insert(next.end(), query.begin() + 1, query.end());
            std::vector<Type *> next_types = constructor_types(query[0]->tag, types[0]);
            next_types.insert(next_types.end(), types.begin() + 1, types.end());
            return useful(specialize(matrix, query[0]->tag, query[0]->children.size()), next,
                          next_types);
        }
        std::vector<std::string> possible = constructors(types[0]);
        std::set<std::string> present;
        for (const PatternRow &row : matrix)
            if (row[0])
                present.insert(row[0]->tag);
        bool complete = !possible.empty();
        for (const std::string &tag : possible)
            if (!present.count(tag))
                complete = false;
        if (complete) {
            for (const std::string &tag : possible) {
                std::vector<Type *> arguments = constructor_types(tag, types[0]);
                PatternRow next(arguments.size());
                next.insert(next.end(), query.begin() + 1, query.end());
                std::vector<Type *> next_types = arguments;
                next_types.insert(next_types.end(), types.begin() + 1, types.end());
                if (useful(specialize(matrix, tag, arguments.size()), next, next_types))
                    return true;
            }
            return false;
        }
        PatternMatrix defaults;
        for (const PatternRow &row : matrix)
            if (!row[0])
                defaults.emplace_back(row.begin() + 1, row.end());
        return useful(defaults, PatternRow(query.begin() + 1, query.end()),
                      std::vector<Type *>(types.begin() + 1, types.end()));
    }
};
struct Symbol {
    std::string name;
    Position position;
    bool top = false, used = false;
};
using SymbolEnv = std::map<std::string, Symbol *>;
struct Warning {
    Position position;
    int order;
    std::string message;
};
struct GroupSymbols {
    Group *group;
    std::set<Symbol *> targets;
};
struct StaticChecks {
    std::vector<std::unique_ptr<Symbol>> symbols;
    std::map<Expr *, Symbol *> references;
    std::vector<GroupSymbols> groups;
    std::vector<Warning> warnings;
    Symbol *symbol(const std::string &name, const Position &position, bool top) {
        symbols.push_back(std::make_unique<Symbol>());
        Symbol *result = symbols.back().get();
        result->name = name;
        result->position = position;
        result->top = top;
        return result;
    }
    void pattern(Expr *p, SymbolEnv &env) {
        if (p->kind == "name")
            env[p->value] = symbol(p->value, p->position, false);
        for (Expr *child : p->children)
            pattern(child, env);
    }
    SymbolEnv group(Group *group, const SymbolEnv &env, bool top) {
        SymbolEnv inner = env;
        GroupSymbols record{group, {}};
        for (Binding *binding : group->bindings) {
            Symbol *value = symbol(binding->name.spelling, binding->name.position, top);
            inner[value->name] = value;
            record.targets.insert(value);
        }
        groups.push_back(record);
        for (Binding *binding : group->bindings)
            expression(binding->expr, group->rec ? inner : env);
        return inner;
    }
    void expression(Expr *e, const SymbolEnv &env) {
        if (e->kind == "name") {
            auto found = env.find(e->value);
            Symbol *value = found == env.end() ? nullptr : found->second;
            references[e] = value;
            if (value)
                value->used = true;
            return;
        }
        if (e->kind == "fun") {
            SymbolEnv inner = env;
            if (e->token.spelling != "_")
                inner[e->token.spelling] = symbol(e->token.spelling, e->token.position, false);
            expression(e->children[0], inner);
            return;
        }
        if (e->kind == "let") {
            SymbolEnv inner = group(e->group, env, false);
            expression(e->children[0], inner);
            return;
        }
        if (e->kind == "match") {
            expression(e->children[0], env);
            Coverage coverage;
            PatternMatrix matrix;
            std::vector<Type *> types = {e->children[0]->inferred};
            for (size_t i = 0; i < e->arms.size(); ++i) {
                const Arm &arm = e->arms[i];
                PatternRow query = {coverage_pattern(arm.pattern)};
                if (i && !coverage.useful(matrix, query, types))
                    warnings.push_back({arm.pattern->position, 2, "this match case is unused"});
                matrix.push_back(query);
                SymbolEnv inner = env;
                pattern(arm.pattern, inner);
                expression(arm.body, inner);
            }
            if (coverage.useful(matrix, {nullptr}, types))
                warnings.push_back({e->position, 1, "this match is not exhaustive"});
            return;
        }
        for (Expr *child : e->children)
            expression(child, env);
    }
    void walk(Expr *e, const std::function<void(Expr *)> &visit) {
        visit(e);
        if (e->group)
            for (Binding *binding : e->group->bindings)
                walk(binding->expr, visit);
        for (Expr *child : e->children)
            walk(child, visit);
        for (const Arm &arm : e->arms)
            walk(arm.body, visit);
    }
    std::string classification(Expr *e, const std::set<Symbol *> &targets) {
        Expr *body = parameters(e).second;
        int count = 0;
        bool all_tail = true;
        auto target = [&](Expr *n) {
            auto found = references.find(n);
            return found != references.end() && targets.count(found->second);
        };
        std::function<void(Expr *, bool)> visit = [&](Expr *n, bool tail) {
            if (n->kind == "name") {
                if (target(n)) {
                    ++count;
                    all_tail = false;
                }
                return;
            }
            if (n->kind == "apply") {
                Expr *head = n;
                std::vector<Expr *> arguments;
                while (head->kind == "apply") {
                    arguments.push_back(head->children[1]);
                    head = head->children[0];
                }
                if (head->kind == "name" && target(head)) {
                    ++count;
                    if (!tail)
                        all_tail = false;
                } else
                    visit(head, false);
                for (auto it = arguments.rbegin(); it != arguments.rend(); ++it)
                    visit(*it, false);
                return;
            }
            if (n->kind == "if") {
                visit(n->children[0], false);
                visit(n->children[1], tail);
                visit(n->children[2], tail);
                return;
            }
            if (n->kind == "match") {
                visit(n->children[0], false);
                for (const Arm &arm : n->arms)
                    visit(arm.body, tail);
                return;
            }
            if (n->kind == "let") {
                for (Binding *binding : n->group->bindings)
                    visit(binding->expr, false);
                visit(n->children[0], tail);
                return;
            }
            if (n->kind == "binary" && (n->token.kind == "&&" || n->token.kind == "||")) {
                visit(n->children[0], false);
                visit(n->children[1], tail);
                return;
            }
            for (Expr *child : n->children)
                visit(child, false);
        };
        visit(body, true);
        return count == 0 ? "" : all_tail ? "tail recursive" : "recursive";
    }
    std::vector<Warning> run(const Item &item, const TypeEnv &env) {
        SymbolEnv names;
        for (const auto &entry : env)
            names[entry.first] = nullptr;
        if (item.kind == "declaration")
            group(item.group, names, true);
        else
            expression(item.expr, names);
        for (const GroupSymbols &record : groups)
            if (record.group->rec) {
                bool used = false;
                for (Binding *binding : record.group->bindings) {
                    walk(binding->expr, [&](Expr *n) {
                        auto found = references.find(n);
                        if (found != references.end() && record.targets.count(found->second))
                            used = true;
                    });
                    binding->classification = classification(binding->expr, record.targets);
                }
                if (!used)
                    warnings.push_back({*record.group->rec, 3, "unused rec flag"});
            }
        for (const auto &value : symbols)
            if (!value->top && !value->used && value->name[0] != '_')
                warnings.push_back({value->position, 4, "unused variable '" + value->name + "'"});
        std::stable_sort(warnings.begin(), warnings.end(), [](const Warning &a, const Warning &b) {
            return std::tie(a.position.line, a.position.column, a.order) <
                   std::tie(b.position.line, b.position.column, b.order);
        });
        return warnings;
    }
};
struct Counts {
    int items = 0, bindings = 0, syntax = 0, type = 0, runtime = 0, warnings = 0;
    int64_t calls = 0;
};
static std::string classification_suffix(const Binding *binding) {
    return binding->classification.empty() ? "" : " (" + binding->classification + ")";
}
int main() {
    const std::vector<std::string> files = {"prelude.ml", "program.ml"};
    std::map<std::string, std::vector<std::string>> sources;
    for (const std::string &file : files) {
        std::ifstream input("input/" + file);
        std::string line;
        while (std::getline(input, line))
            sources[file].push_back(line);
    }
    std::filesystem::create_directories("output");
    std::ofstream types("output/types.txt"), values("output/values.txt"),
        errors("output/errors.txt"), formatted("output/formatted.ml");
    auto initial = builtins();
    TypeEnv type_env = initial.first;
    Environment value_env = initial.second;
    std::map<std::string, Counts> counts;
    for (const std::string &file : files) {
        Counts &count = counts[file];
        Evaluator evaluator;
        Parser parser{lex(file, sources[file])};
        std::map<std::string, Item> pending;
        types << "== " << file << " ==\n";
        values << "== " << file << " ==\n";
        formatted << "(* " << file << " *)\n";
        auto report = [&](const Position &position, const std::string &kind,
                          const std::string &message) {
            errors << position.file << ":" << position.line << ":" << position.column << ": "
                   << kind << ": " << message << "\n";
            const auto &lines = sources[position.file];
            if (position.line <= static_cast<int>(lines.size()))
                errors << "    " << lines[position.line - 1] << "\n"
                       << std::string(position.column + 3, ' ') << "^\n";
            if (kind == "syntax error")
                ++count.syntax;
            else if (kind == "type error")
                ++count.type;
            else if (kind == "runtime error")
                ++count.runtime;
            else
                ++count.warnings;
        };
        while (parser.peek().kind != "EOF") {
            ++count.items;
            Item item;
            try {
                item = parser.item();
            } catch (const SyntaxError &failure) {
                const Token &token = failure.token;
                std::string message = token.kind == "invalid" ? token.value
                                      : token.kind == "EOF" ? "unexpected end of file"
                                                            : "unexpected '" + token.spelling + "'";
                report(token.position, "syntax error", message);
                parser.recover_item();
                continue;
            }
            formatted << format_item(item) << "\n";
            if (item.kind == "signature") {
                auto previous = pending.find(item.name.spelling);
                if (previous != pending.end())
                    report(previous->second.name.position, "warning",
                           "signature for '" + item.name.spelling + "' is never used");
                pending[item.name.spelling] = item;
                continue;
            }
            std::vector<std::optional<Item>> signatures;
            if (item.kind == "declaration")
                for (Binding *binding : item.group->bindings) {
                    auto found = pending.find(binding->name.spelling);
                    if (found == pending.end())
                        signatures.push_back(std::nullopt);
                    else {
                        signatures.push_back(found->second);
                        pending.erase(found);
                    }
                }
            Inferencer inference;
            Type *expression_type = nullptr;
            try {
                if (item.kind == "declaration") {
                    inference.group(item.group, type_env, false);
                    check_signatures(item.group, signatures);
                } else
                    expression_type = inference.expression(item.expr, type_env);
            } catch (const TypeError &failure) {
                report(failure.position, "type error", type_error_message(failure));
                continue;
            }
            StaticChecks checks;
            std::vector<Warning> warnings = checks.run(item, type_env);
            if (item.kind == "declaration")
                for (Binding *binding : item.group->bindings) {
                    TypePrinter printer;
                    types << binding->name.spelling << " : " << printer.print(binding->scheme.type)
                          << classification_suffix(binding) << "\n";
                }
            else {
                TypePrinter printer;
                types << "- : " << printer.print(expression_type) << "\n";
            }
            std::stable_sort(inference.locals.begin(), inference.locals.end(),
                             [](Binding *a, Binding *b) {
                                 return std::tie(a->name.position.line, a->name.position.column) <
                                        std::tie(b->name.position.line, b->name.position.column);
                             });
            for (Binding *binding : inference.locals) {
                TypePrinter printer;
                printer.local = true;
                printer.quantified = binding->scheme.quantified;
                types << "  " << binding->name.spelling << " (" << binding->name.position.line
                      << ":" << binding->name.position.column
                      << ") : " << printer.print(binding->scheme.type)
                      << classification_suffix(binding) << "\n";
            }
            for (const Warning &warning : warnings)
                report(warning.position, "warning", warning.message);
            try {
                if (item.kind == "declaration") {
                    Environment next = evaluator.group(item.group, value_env);
                    for (Binding *binding : item.group->bindings) {
                        values << binding->name.spelling << " = "
                               << print_value(lookup(next, binding->name.spelling)) << "\n";
                        type_env[binding->name.spelling] = binding->scheme;
                        ++count.bindings;
                    }
                    value_env = next;
                } else {
                    Value *result = evaluator.expression(item.expr, value_env);
                    values << "- = " << print_value(result) << "\n";
                }
            } catch (const RuntimeError &failure) {
                report(failure.position, "runtime error", failure.message);
            }
        }
        std::vector<Item> remaining;
        for (const auto &entry : pending)
            remaining.push_back(entry.second);
        std::sort(remaining.begin(), remaining.end(), [](const Item &a, const Item &b) {
            return std::tie(a.name.position.line, a.name.position.column) <
                   std::tie(b.name.position.line, b.name.position.column);
        });
        for (const Item &signature : remaining)
            report(signature.name.position, "warning",
                   "signature for '" + signature.name.spelling + "' is never used");
        count.calls = evaluator.calls;
    }
    errors << "== summary ==\n";
    for (const std::string &file : files) {
        const Counts &count = counts[file];
        errors << file << ": items=" << count.items << " bindings=" << count.bindings
               << " syntax=" << count.syntax << " type=" << count.type
               << " runtime=" << count.runtime << " warnings=" << count.warnings
               << " calls=" << count.calls << "\n";
    }
}
