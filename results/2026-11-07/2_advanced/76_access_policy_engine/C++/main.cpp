#include "policy.hpp"
Names split(const std::string &source, const std::string &separator) {
    Names result;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = source.find(separator, start);
        result.push_back(source.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            return result;
        start = end + separator.size();
    }
}
std::string join(const Names &values, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += separator;
        out += values[i];
    }
    return out;
}
std::string trim(std::string source) {
    std::size_t first = source.find_first_not_of(' ');
    if (first == std::string::npos)
        return "";
    return source.substr(first, source.find_last_not_of(' ') - first + 1);
}
Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines lines;
    std::string source;
    while (std::getline(file, source))
        lines.push_back(source);
    return lines;
}
static Value input_value(const std::string &source) {
    if (source == "true" || source == "false")
        return Value::truth(source == "true");
    if (source[0] == '[')
        return Value::collection(source == "[]" ? Names{}
                                                : split(source.substr(1, source.size() - 2), ","));
    if (source[0] == '-' || (source[0] >= '0' && source[0] <= '9'))
        return Value::number(std::stoi(source));
    return Value::word(source);
}
static Attributes attributes(const Names &fields, std::size_t start) {
    Attributes out;
    for (std::size_t i = start; i < fields.size(); ++i) {
        std::size_t equal = fields[i].find('=');
        out[fields[i].substr(0, equal)] = input_value(fields[i].substr(equal + 1));
    }
    return out;
}
static std::string value_notation(const Value &value) {
    switch (value.kind) {
    case Value::Kind::Integer:
        return std::to_string(value.integer);
    case Value::Kind::String:
        return "\"" + value.string + "\"";
    case Value::Kind::Boolean:
        return value.boolean ? "true" : "false";
    case Value::Kind::Bag: {
        Names items;
        for (const std::string &item : value.bag)
            items.push_back("\"" + item + "\"");
        return "[" + join(items, ",") + "]";
    }
    case Value::Kind::Error:
        return "";
    }
    return "";
}
static Value boolean_result(const std::vector<Value> &values, bool veto, const std::string &name) {
    bool found = false;
    std::string error;
    for (const Value &v : values) {
        if (v.kind == Value::Kind::Boolean)
            found |= v.boolean == veto;
        else if (error.empty())
            error = v.kind == Value::Kind::Error ? v.string : "type " + name;
    }
    if (found)
        return Value::truth(veto);
    if (!error.empty())
        return Value::error(error);
    return Value::truth(!veto);
}
static Value operation(const std::string &name, const std::vector<Value> &values) {
    for (const Value &v : values)
        if (v.kind == Value::Kind::Error)
            return v;
    const Value &a = values[0];
    const Value &b = values.size() > 1 ? values[1] : values[0];
    bool integers = a.kind == Value::Kind::Integer && b.kind == Value::Kind::Integer;
    if (integers) {
        if (name == "+")
            return Value::number(a.integer + b.integer);
        if (name == "-")
            return Value::number(values.size() == 1 ? -a.integer : a.integer - b.integer);
        if (name == "*")
            return Value::number(a.integer * b.integer);
        if (name == "<")
            return Value::truth(a.integer < b.integer);
        if (name == "<=")
            return Value::truth(a.integer <= b.integer);
        if (name == ">")
            return Value::truth(a.integer > b.integer);
        if (name == ">=")
            return Value::truth(a.integer >= b.integer);
    }
    if ((name == "==" || name == "!=") && a.kind == b.kind &&
        (integers || a.kind == Value::Kind::String || a.kind == Value::Kind::Boolean)) {
        bool equal = integers                        ? a.integer == b.integer
                     : a.kind == Value::Kind::String ? a.string == b.string
                                                     : a.boolean == b.boolean;
        return Value::truth(name == "==" ? equal : !equal);
    }
    if (name == "in" && a.kind == Value::Kind::String && b.kind == Value::Kind::Bag)
        return Value::truth(std::find(b.bag.begin(), b.bag.end(), a.string) != b.bag.end());
    if (name == "not" && a.kind == Value::Kind::Boolean)
        return Value::truth(!a.boolean);
    if ((name == "starts_with" || name == "^=") && a.kind == Value::Kind::String &&
        b.kind == Value::Kind::String)
        return Value::truth(a.string.rfind(b.string, 0) == 0);
    if (name == "size" && a.kind == Value::Kind::Bag)
        return Value::number(int(a.bag.size()));
    return Value::error("type " + name);
}
static Value expression(const Expr &tree, const Attributes &values,
                        const std::string &current = "") {
    const std::string &name = tree->operation;
    const std::vector<Expr> &arguments = tree->arguments;
    if (name == "literal")
        return tree->literal;
    if (name == "attribute") {
        auto found = values.find(tree->literal.string);
        return found == values.end() ? Value::error("missing " + tree->literal.string)
                                     : found->second;
    }
    if (name == "it")
        return Value::word(current);
    if (name == "present")
        return Value::truth(values.count(arguments[0]->literal.string) != 0);
    if (name == "any_of" || name == "all_of") {
        Value bag = expression(arguments[0], values, current);
        if (bag.kind == Value::Kind::Error)
            return bag;
        if (bag.kind != Value::Kind::Bag)
            return Value::error("type " + name);
        std::vector<Value> checked;
        for (const std::string &item : bag.bag)
            checked.push_back(expression(arguments[1], values, item));
        return boolean_result(checked, name == "any_of", name);
    }
    std::vector<Value> operands;
    for (const Expr &argument : arguments)
        operands.push_back(expression(argument, values, current));
    if (name == "and" || name == "or")
        return boolean_result(operands, name == "or", name);
    return operation(name, operands);
}
static TargetResult target_group(const std::vector<TargetResult> &values, bool conjunction) {
    bool all = true;
    for (const TargetResult &value : values) {
        if (conjunction && value.kind == TargetKind::NoMatch)
            return {TargetKind::NoMatch, ""};
        if (!conjunction && value.kind == TargetKind::Match)
            return {};
        all &= value.kind == TargetKind::Match;
    }
    if (conjunction && all)
        return {};
    for (const TargetResult &value : values)
        if (value.kind == TargetKind::Indeterminate)
            return value;
    return {TargetKind::NoMatch, ""};
}
static TargetResult match_clause(const Clause &clause, const Attributes &values) {
    auto found = values.find(clause.reference);
    if (found == values.end())
        return clause.mandatory
                   ? TargetResult{TargetKind::Indeterminate, "missing " + clause.reference}
                   : TargetResult{TargetKind::NoMatch, ""};
    std::vector<Value> items;
    const Value &source = found->second;
    if (source.kind == Value::Kind::Bag)
        for (const std::string &item : source.bag)
            items.push_back(Value::word(item));
    else
        items.push_back(source);
    Value literal = expression(clause.literal, values);
    std::string error;
    bool matches = false;
    for (const Value &item : items) {
        Value result = operation(clause.operation, {item, literal});
        if (result.kind == Value::Kind::Boolean && result.boolean)
            matches = true;
        else if (result.kind == Value::Kind::Error && error.empty())
            error = result.string;
    }
    if (matches)
        return {};
    if (!error.empty())
        return {TargetKind::Indeterminate, error};
    return {TargetKind::NoMatch, ""};
}
class Evaluator {
    const Attributes &values;
    std::array<char, 100> *coverage;
    void attachments(Eval result, const std::vector<Eval> &supporters) {
        for (const Eval &supporter : supporters) {
            result->obligations.insert(result->obligations.end(), supporter->obligations.begin(),
                                       supporter->obligations.end());
            result->advice.insert(result->advice.end(), supporter->advice.begin(),
                                  supporter->advice.end());
        }
        std::string effect = decision_name(result->decision);
        for (int obligatory = 1; obligatory >= 0; --obligatory) {
            const std::vector<Attachment> &definitions =
                obligatory ? result->element->obligations : result->element->advice;
            for (const Attachment &definition : definitions)
                if (definition.effect == effect) {
                    std::string error, item = definition.identifier;
                    for (const auto &argument : definition.arguments) {
                        Value v = expression(argument.second, values);
                        if (v.kind == Value::Kind::Error) {
                            if (error.empty())
                                error = v.string;
                        } else
                            item += " " + argument.first + "=" + value_notation(v);
                    }
                    if (!error.empty()) {
                        if (obligatory) {
                            result->decision = effect == "DENY" ? Decision::ID : Decision::IP;
                            result->reason = "obligation " + definition.identifier + ": " + error;
                            result->decisive = nullptr;
                            result->obligations.clear();
                            result->advice.clear();
                            return;
                        }
                        continue;
                    }
                    (obligatory ? result->obligations : result->advice)
                        .push_back({definition.identifier, item});
                }
        }
    }

  public:
    explicit Evaluator(const Attributes &values, std::array<char, 100> *coverage = nullptr)
        : values(values), coverage(coverage) {}
    TargetResult target(Element *element) const {
        std::vector<TargetResult> lines;
        for (const TargetLine &line : element->targets) {
            std::vector<TargetResult> alternatives;
            for (const Alternative &alternative : line) {
                std::vector<TargetResult> clauses;
                for (const Clause &clause : alternative)
                    clauses.push_back(match_clause(clause, values));
                alternatives.push_back(target_group(clauses, true));
            }
            lines.push_back(target_group(alternatives, false));
        }
        return target_group(lines, true);
    }
    Eval rule(Element *element, bool with_obligations = true) {
        Eval result = std::make_shared<Evaluation>();
        result->element = element;
        result->target = target(element);
        Decision error = element->behavior == "DENY" ? Decision::ID : Decision::IP;
        if (result->target.kind == TargetKind::Indeterminate) {
            result->decision = error;
            result->reason = result->target.reason;
        } else if (result->target.kind == TargetKind::Match) {
            result->condition =
                element->condition ? expression(element->condition, values) : Value::truth(true);
            Value &condition = result->condition;
            if (condition.kind != Value::Kind::Boolean && condition.kind != Value::Kind::Error)
                condition = Value::error("type condition");
            if (condition.kind == Value::Kind::Error) {
                result->decision = error;
                result->reason = condition.string;
            } else if (condition.boolean) {
                result->decision = element->behavior == "DENY" ? Decision::Deny : Decision::Permit;
                result->decisive = element;
                if (with_obligations)
                    attachments(result, {});
            }
        }
        if (coverage)
            (*coverage)[element->index] = result->decision == Decision::Permit ? 'P'
                                          : result->decision == Decision::Deny ? 'D'
                                          : result->decision == Decision::NA   ? '-'
                                                                               : 'I';
        return result;
    }
    Eval evaluate(Element *element) {
        if (element->kind == "rule")
            return rule(element);
        Eval result = std::make_shared<Evaluation>();
        result->element = element;
        result->target = target(element);
        if (result->target.kind == TargetKind::NoMatch)
            return result;
        Combined combined = combine(
            *element, [&](Element *e) { return evaluate(e); },
            [&](Element *e) { return target(e); });
        result->decision = combined.decision;
        result->reason = combined.reason;
        result->children = std::move(combined.children);
        if (result->target.kind == TargetKind::Indeterminate) {
            if (definite(result->decision))
                result->decision =
                    result->decision == Decision::Permit ? Decision::IP : Decision::ID;
            if (indeterminate(result->decision))
                result->reason = result->target.reason;
        }
        if (definite(result->decision)) {
            std::vector<Eval> supporters;
            for (const ChildState &state : result->children)
                if (state.kind == ChildState::Kind::Evaluated &&
                    state.evaluation->decision == result->decision)
                    supporters.push_back(state.evaluation);
            result->decisive = supporters.empty() ? element : supporters[0]->decisive;
            attachments(result, supporters);
        }
        return result;
    }
};
static std::string final_notation(const Eval &result) {
    return notation(result->decision, result->reason) +
           (definite(result->decision) ? " by " + result->decisive->identifier : "");
}
static void tree_lines(const Eval &result, Lines &lines, int depth = 0) {
    Element *e = result->element;
    std::string prefix(2 + 2 * depth, ' '),
        source = text(prefix, e->kind, " ", e->identifier, " ", e->behavior, " target ",
                      target_name(result->target.kind));
    if (e->kind == "rule" && result->target.kind == TargetKind::Match)
        source += " condition " + std::string(result->condition.kind == Value::Kind::Error
                                                  ? "INDETERMINATE"
                                              : result->condition.boolean ? "TRUE"
                                                                          : "FALSE");
    lines.push_back(source + " -> " + notation(result->decision, result->reason));
    if (e->kind != "rule" && result->target.kind != TargetKind::NoMatch)
        for (std::size_t i = 0; i < e->children.size(); ++i) {
            Element *child = e->children[i];
            const ChildState &state = result->children[i];
            if (state.kind == ChildState::Kind::Evaluated)
                tree_lines(state.evaluation, lines, depth + 1);
            else if (state.kind == ChildState::Kind::Skipped)
                line(lines, prefix, "  ", child->kind, " ", child->identifier, " skipped");
            else
                line(lines, prefix, "  ", child->kind, " ", child->identifier, " ", child->behavior,
                     " target ", target_name(state.checked.kind),
                     state.checked.kind == TargetKind::Indeterminate
                         ? " (" + state.checked.reason + ")"
                         : "");
        }
}
struct Request {
    std::string identifier, user, roles, action, resource;
    Attributes environment;
    bool explain;
};
struct Resource {
    std::string type;
    Attributes attributes;
};
struct Activation {
    std::string role, reason;
};
struct Prepared {
    std::vector<Activation> activations;
    Roles roles;
    int grant = -1;
    Attributes values;
};
class Engine {
    RBAC rbac;
    Policies policies;
    std::vector<Element *> rules;
    std::map<std::string, Attributes> subjects;
    std::map<std::string, Resource> resources;
    std::vector<Domain> domains;
    Attributes reference;
    std::vector<Request> requests;
    std::array<std::string, 100> coverage{};
    std::array<int, 100> decisive{};
    std::array<int, 5> decisions{};
    std::map<std::tuple<int, std::string, std::string>, int> grant_counts;
    std::map<std::string, int> obligations, advice;
    int refused = 0;
    void read() {
        rbac.read();
        policies = read_policies();
        for (const auto &e : policies.elements)
            if (e->kind == "rule")
                rules.push_back(e.get());
        for (const std::string &source : read_lines("input/attributes.txt")) {
            Names f = split(source);
            if (f[0] == "SUBJECT")
                subjects[f[1]] = attributes(f, 2);
            else if (f[0] == "RESOURCE")
                resources[f[1]] = {f[2], attributes(f, 3)};
            else if (f[0] == "DOMAIN") {
                Domain d{f[1], {}};
                for (std::size_t i = 2; i < f.size(); ++i)
                    d.candidates.push_back(input_value(f[i]));
                domains.push_back(d);
            } else
                reference = attributes(f, 1);
        }
        for (const std::string &source : read_lines("input/requests.txt")) {
            Names f = split(source);
            bool explain = f.back() == "EXPLAIN";
            if (explain)
                f.pop_back();
            requests.push_back({f[0], f[1], f[2], f[3], f[4], attributes(f, 5), explain});
        }
    }
    std::string check(const Request &request) const {
        if (!subjects.count(request.user))
            return "unknown user " + request.user;
        if (!resources.count(request.resource))
            return "unknown resource " + request.resource;
        auto day = request.environment.find("day");
        if (day == request.environment.end() || day->second.kind != Value::Kind::Integer ||
            day->second.integer < 1 || day->second.integer > 365)
            return "bad day";
        return "";
    }
    Prepared prepare(const Request &request) const {
        Prepared out;
        int day = request.environment.at("day").integer;
        Roles authorized = rbac.authorized(request.user, day), active = 0;
        Names candidates = request.roles == "-"   ? Names{}
                           : request.roles == "*" ? rbac.names(authorized)
                                                  : split(request.roles, ",");
        std::set<std::string> seen;
        for (const std::string &candidate : candidates) {
            int role = rbac.find(candidate);
            std::string reason;
            if (role < 0)
                reason = "unknown";
            else if (seen.count(candidate))
                reason = "duplicate";
            else if (!(authorized & bit(role)))
                reason = "unauthorized";
            else
                for (const Constraint &c : rbac.dsd)
                    if (cardinality(c.roles & rbac.closure(active | bit(role))) >= c.cardinality) {
                        reason = "dsd " + c.name;
                        break;
                    }
            seen.insert(candidate);
            if (reason.empty())
                active |= bit(role);
            out.activations.push_back({candidate, reason});
        }
        out.roles = rbac.closure(active);
        const Resource &resource = resources.at(request.resource);
        for (int role : rbac.ordered(out.roles))
            if (rbac.permits(role, request.action, resource.type)) {
                out.grant = role;
                break;
            }
        for (const auto &a : subjects.at(request.user))
            out.values["subject." + a.first] = a.second;
        out.values["subject.id"] = Value::word(request.user);
        out.values["subject.role"] = Value::collection(rbac.names(out.roles));
        out.values["subject.rbac"] = Value::truth(out.grant >= 0);
        for (const auto &a : resource.attributes)
            out.values["resource." + a.first] = a.second;
        out.values["resource.id"] = Value::word(request.resource);
        out.values["resource.type"] = Value::word(resource.type);
        out.values["action.id"] = Value::word(request.action);
        for (const auto &a : request.environment)
            out.values["environment." + a.first] = a.second;
        return out;
    }
    std::pair<Lines, Lines> process_requests() {
        Lines output, traces;
        for (const Request &request : requests) {
            std::array<char, 100> symbols;
            symbols.fill('.');
            std::string error = check(request);
            Lines block;
            if (request.explain)
                line(block, "request ", request.identifier);
            if (!error.empty()) {
                line(output, request.identifier, " ERROR ", error);
                ++decisions[4];
                if (request.explain)
                    line(block, "  error ", error);
            } else {
                Prepared prepared = prepare(request);
                Eval result = Evaluator(prepared.values, &symbols).evaluate(policies.root);
                line(output, request.identifier, " ", final_notation(result));
                for (const Activation &a : prepared.activations)
                    if (!a.reason.empty()) {
                        line(output, "  refused ", a.role, " ", a.reason);
                        ++refused;
                    }
                for (const auto &item : result->obligations) {
                    line(output, "  obligation ", item.second);
                    ++obligations[item.first];
                }
                for (const auto &item : result->advice) {
                    line(output, "  advice ", item.second);
                    ++advice[item.first];
                }
                if (prepared.grant >= 0)
                    ++grant_counts[{prepared.grant, request.action,
                                    resources.at(request.resource).type}];
                ++decisions[indeterminate(result->decision) ? 3 : int(result->decision)];
                if (definite(result->decision))
                    ++decisive[result->decisive->index];
                if (request.explain) {
                    line(block, "  user ", request.user, " resource ", request.resource, " type ",
                         resources.at(request.resource).type, " action ", request.action, " day ",
                         request.environment.at("day").integer);
                    for (const Activation &a : prepared.activations)
                        line(block, "  activate ", a.role,
                             a.reason.empty() ? " ok" : " refused " + a.reason);
                    line(block, "  roles ",
                         prepared.roles ? join(rbac.names(prepared.roles), ",") : "-");
                    line(block, "  rbac ",
                         prepared.grant >= 0 ? "yes " + rbac.roles[prepared.grant] : "no");
                    tree_lines(result, block);
                    line(block, "  decision ", final_notation(result));
                }
            }
            if (!block.empty()) {
                if (!traces.empty())
                    traces.push_back("");
                traces.insert(traces.end(), block.begin(), block.end());
            }
            for (Element *rule : rules)
                coverage[rule->index] += symbols[rule->index];
        }
        return {output, traces};
    }
    Lines permission_report() const {
        Lines out;
        std::set<std::string> users;
        for (const Assignment &a : rbac.assignments)
            users.insert(a.user);
        for (const std::string &user : users) {
            if (!out.empty())
                out.push_back("");
            line(out, "user ", user);
            std::array<Days, 40> assigned{}, authorized{};
            Roles present = 0;
            for (const Assignment &a : rbac.assignments)
                if (a.user == user) {
                    present |= bit(a.role);
                    for (int day = a.first; day <= a.last; ++day)
                        assigned[a.role][day] = true;
                }
            Roles all = rbac.closure(present);
            for (int role : rbac.ordered(present))
                for (int inherited : rbac.ordered(rbac.closure(bit(role))))
                    for (int day = 1; day <= 365; ++day)
                        authorized[inherited][day] |= assigned[role][day];
            for (int role : rbac.ordered(present))
                line(out, "  assigned ", rbac.roles[role], " ", day_notation(assigned[role]));
            for (int role : rbac.ordered(all))
                line(out, "  authorized ", rbac.roles[role], " ", day_notation(authorized[role]));
            std::map<std::pair<std::string, std::string>, Roles> via;
            for (int role : rbac.ordered(all))
                for (const Grant &g : rbac.grants)
                    if (g.role == role)
                        via[{g.action, g.type}] |= bit(role);
            for (const auto &permission : via) {
                const std::string &action = permission.first.first, &type = permission.first.second;
                Days days{};
                for (int role : rbac.ordered(permission.second))
                    for (int day = 1; day <= 365; ++day)
                        days[day] |= authorized[role][day];
                std::string effective = "-";
                if (subjects.count(user)) {
                    int permitted = 0, total = 0;
                    for (const auto &resource : resources)
                        if (resource.second.type == type) {
                            ++total;
                            Request hypothetical{"",        user, "*", action, resource.first,
                                                 reference, false};
                            Prepared prepared = prepare(hypothetical);
                            permitted +=
                                Evaluator(prepared.values).evaluate(policies.root)->decision ==
                                Decision::Permit;
                        }
                    effective = text(permitted, "/", total);
                }
                line(out, "  permission ", action, " ", type, " ", day_notation(days), " via ",
                     join(rbac.names(permission.second), ","), " effective ", effective);
            }
        }
        return out;
    }
    Lines domain_analysis() const {
        std::array<int, 100> counts{};
        std::array<std::string, 100> examples{};
        std::array<bool, 100> shadowed{};
        std::array<std::set<int>, 100> blockers;
        std::array<std::array<int, 100>, 100> conflict_counts{};
        struct Pair {
            Element *policy, *earlier, *later;
        };
        std::vector<Pair> pairs;
        for (Element *rule : rules)
            shadowed[rule->index] = rule->parent->behavior == "first-applicable";
        for (const auto &e : policies.elements)
            if (e->kind == "policy")
                for (std::size_t i = 0; i < e->children.size(); ++i)
                    for (std::size_t j = i + 1; j < e->children.size(); ++j)
                        if (e->children[i]->behavior != e->children[j]->behavior)
                            pairs.push_back({e.get(), e->children[i], e->children[j]});
        int point_count = 0;
        for (const Attributes &values : points(domains)) {
            ++point_count;
            Evaluator evaluator(values);
            std::array<TargetKind, 100> targets{};
            std::array<Decision, 100> standalone{};
            std::array<bool, 100> applies{};
            for (const auto &e : policies.elements)
                if (e->kind != "rule")
                    targets[e->index] = evaluator.target(e.get()).kind;
            for (Element *rule : rules)
                standalone[rule->index] = evaluator.rule(rule, false)->decision;
            for (Element *rule : rules) {
                bool applicable = definite(standalone[rule->index]);
                for (Element *parent = rule->parent; parent; parent = parent->parent)
                    applicable &= targets[parent->index] == TargetKind::Match;
                if (!applicable)
                    continue;
                applies[rule->index] = true;
                ++counts[rule->index];
                if (examples[rule->index].empty()) {
                    Names items;
                    for (const Domain &d : domains)
                        if (d.candidates.size() >= 2)
                            items.push_back(d.reference + "=" +
                                            value_notation(values.at(d.reference)));
                    examples[rule->index] = join(items, " ");
                }
                if (shadowed[rule->index]) {
                    Element *earlier = blocker(rule, standalone);
                    if (!earlier)
                        shadowed[rule->index] = false;
                    else
                        blockers[rule->index].insert(earlier->index);
                }
            }
            for (const Pair &pair : pairs)
                if (applies[pair.earlier->index] && applies[pair.later->index])
                    ++conflict_counts[pair.earlier->index][pair.later->index];
        }
        Lines out;
        line(out, "applicability ", point_count);
        for (Element *rule : rules)
            line(out, "  ", rule->identifier, " ", counts[rule->index], " ",
                 counts[rule->index] ? examples[rule->index] : "-");
        int dead = 0, shadows = 0, conflicts = 0;
        for (Element *rule : rules) {
            if (!counts[rule->index]) {
                ++dead;
                shadowed[rule->index] = false;
            }
            shadows += shadowed[rule->index];
        }
        line(out, "dead ", dead);
        for (Element *rule : rules)
            if (!counts[rule->index])
                line(out, "  ", rule->identifier);
        line(out, "shadowed ", shadows);
        for (Element *rule : rules)
            if (shadowed[rule->index]) {
                Names names;
                for (Element *earlier : rules)
                    if (blockers[rule->index].count(earlier->index))
                        names.push_back(earlier->identifier);
                line(out, "  ", rule->identifier, " by ", join(names, ","));
            }
        for (const Pair &pair : pairs)
            conflicts += conflict_counts[pair.earlier->index][pair.later->index] > 0;
        line(out, "conflicts ", conflicts);
        for (const Pair &pair : pairs)
            if (int count = conflict_counts[pair.earlier->index][pair.later->index])
                line(out, "  ", pair.policy->identifier, " ", pair.earlier->identifier, " ",
                     pair.later->identifier, " ", count, " ",
                     conflict_winner(pair.policy, pair.earlier, pair.later)->identifier);
        return out;
    }
    Lines analysis_report() {
        Lines out;
        line(out, "rbac ", rbac.diagnostics.size());
        for (const Diagnostic &d : rbac.diagnostics)
            line(out, "  line ", d.number, " ", d.keyword, " ", d.message);
        std::vector<Grant> grants = rbac.grants;
        std::sort(grants.begin(), grants.end(), [&](const Grant &a, const Grant &b) {
            return std::tie(rbac.roles[a.role], a.action, a.type) <
                   std::tie(rbac.roles[b.role], b.action, b.type);
        });
        line(out, "grants ", grants.size());
        for (const Grant &g : grants)
            line(out, "  ", rbac.roles[g.role], " ", g.action, " ", g.type, " ",
                 grant_counts[{g.role, g.action, g.type}]);
        Lines domain = domain_analysis();
        out.insert(out.end(), domain.begin(), domain.end());
        line(out, "coverage ", requests.size());
        std::vector<Element *> uncovered;
        for (Element *rule : rules) {
            const std::string &symbols = coverage[rule->index];
            int count = int(std::count(symbols.begin(), symbols.end(), 'P') +
                            std::count(symbols.begin(), symbols.end(), 'D'));
            line(out, "  ", rule->identifier, " ", symbols, " ", count);
            if (!count)
                uncovered.push_back(rule);
        }
        line(out, "uncovered ", uncovered.size());
        for (Element *rule : uncovered)
            line(out, "  ", rule->identifier);
        out.push_back("summary");
        const Names names{"PERMIT", "DENY", "NOT_APPLICABLE", "INDETERMINATE", "ERROR"};
        for (int i = 0; i < 5; ++i)
            line(out, "  decision ", names[i], " ", decisions[i]);
        line(out, "  refused ", refused);
        for (const auto &e : policies.elements)
            if (decisive[e->index])
                line(out, "  decisive ", e->identifier, " ", decisive[e->index]);
        for (const auto &entry : obligations)
            line(out, "  obligation ", entry.first, " ", entry.second);
        for (const auto &entry : advice)
            line(out, "  advice ", entry.first, " ", entry.second);
        return out;
    }
    static void write(const std::string &name, const Lines &lines) {
        std::ofstream file("output/" + name);
        for (const std::string &source : lines)
            file << source << '\n';
    }

  public:
    void run() {
        read();
        auto reports = process_requests();
        std::filesystem::create_directories("output");
        write("decisions.txt", reports.first);
        write("traces.txt", reports.second);
        write("permissions.txt", permission_report());
        write("analysis.txt", analysis_report());
    }
};
int main() { Engine().run(); }
