#include "planner.hpp"
static const Lines heuristicNames{"goalcount", "hmax", "hadd", "ff", "lmcount"};
template <class... Parts> static std::string text(const Parts &...parts) {
    std::ostringstream out;
    (out << ... << parts);
    return out.str();
}
static void append(Lines &to, const Lines &from) { to.insert(to.end(), from.begin(), from.end()); }
static std::string heading(const std::string &name, const Lines &items) {
    return name + " " + (items.empty() ? "-" : join(items, " "));
}
static std::string numberList(State state) {
    Plan numbers = state.numbers();
    return numbers.empty() ? "-" : intList(numbers, ",");
}
static Settings readSettings() {
    Settings out;
    for (const std::string &line : readLines("input/params.txt")) {
        if (line.empty() || line[0] == '#')
            continue;
        Lines words = splitWords(line);
        if (words[0] == "budget")
            out.budget = std::stoi(words[1]);
        else if (words[0] == "weight")
            out.weight = std::stoi(words[1]);
        else if (words[0] == "graphplan")
            out.levelLimit = std::stoi(words[1]);
        else if (words[0] == "run")
            out.runs.push_back({words[1], words[2]});
        else
            out.repair = {words[1], words[2]};
    }
    return out;
}
static std::vector<CandidatePlan> readCandidates() {
    std::vector<CandidatePlan> out;
    for (const std::string &line : readLines("input/candidates.txt")) {
        if (line.empty() || line[0] == '#')
            continue;
        if (line.compare(0, 5, "plan ") == 0) {
            Lines words = splitWords(line);
            out.push_back({words[1], words[2], {}});
        } else if (line != "end") {
            Lines words = splitWords(line.substr(1, line.size() - 2));
            out.back().steps.push_back({words[0], Lines(words.begin() + 1, words.end())});
        }
    }
    return out;
}
static std::string argumentCheck(const Domain &domain, const Lines &arguments,
                                 const Lines &expected,
                                 const std::map<std::string, std::string> &types,
                                 const std::string &noun) {
    if (arguments.size() != expected.size())
        return text("expected ", expected.size(), " arguments, got ", arguments.size());
    for (std::size_t i = 0; i < arguments.size(); ++i) {
        auto found = types.find(arguments[i]);
        if (found == types.end())
            return "unknown " + noun + " " + arguments[i];
        if (!domain.subtype(found->second, expected[i]))
            return text("argument ", i + 1, " (", arguments[i], ") is not of type ", expected[i]);
    }
    return "";
}
static void validateDomain(Domain &domain) {
    std::vector<Schema> kept;
    for (const Schema &schema : domain.actions) {
        std::string reason;
        std::map<std::string, std::string> types;
        for (const Typed &parameter : schema.parameters) {
            types[parameter.name] = parameter.type;
            if (reason.empty() && std::find(domain.types.begin(), domain.types.end(),
                                            parameter.type) == domain.types.end())
                reason = "unknown type " + parameter.type;
        }
        if (reason.empty()) {
            std::vector<Literal> literals = schema.conditions;
            literals.insert(literals.end(), schema.effects.begin(), schema.effects.end());
            for (const Literal &literal : literals) {
                const Atom &atom = literal.atom;
                Lines expected;
                if (atom.predicate == "=")
                    expected = {"object", "object"};
                else {
                    auto found = domain.predicateIndex.find(atom.predicate);
                    if (found == domain.predicateIndex.end()) {
                        reason = atom.text() + ": unknown predicate " + atom.predicate;
                        break;
                    }
                    expected = domain.predicates[found->second].types;
                }
                std::string error = argumentCheck(domain, atom.terms, expected, types, "variable");
                if (!error.empty()) {
                    reason = atom.text() + ": " + error;
                    break;
                }
            }
        }
        if (reason.empty())
            kept.push_back(schema);
        else
            domain.diagnostics.push_back("error: action " + schema.name + ": " + reason);
    }
    domain.actions = std::move(kept);
    std::set<std::string> used;
    for (const Schema &schema : domain.actions) {
        for (const Literal &literal : schema.conditions)
            used.insert(literal.atom.predicate);
        for (const Literal &literal : schema.effects)
            used.insert(literal.atom.predicate);
    }
    for (const Predicate &predicate : domain.predicates)
        if (!used.count(predicate.name))
            domain.diagnostics.push_back("warning: predicate " + predicate.name +
                                         " is not used by any action");
    domain.classify();
}
static void validateProblem(const Domain &domain, Problem &problem) {
    const std::map<std::string, std::string> types = objectTypes(problem);
    const auto check = [&](std::vector<Atom> &atoms, const std::string &side) {
        std::vector<Atom> kept;
        std::set<std::string> seen;
        for (const Atom &atom : atoms) {
            std::string reason;
            auto found = domain.predicateIndex.find(atom.predicate);
            if (found == domain.predicateIndex.end())
                reason = "unknown predicate " + atom.predicate;
            else
                reason = argumentCheck(domain, atom.terms, domain.predicates[found->second].types,
                                       types, "object");
            if (reason.empty() && seen.count(atom.text()))
                reason = "duplicate";
            if (reason.empty()) {
                seen.insert(atom.text());
                kept.push_back(atom);
            } else
                problem.diagnostics.push_back("warning: " + side + " " + atom.text() + ": " +
                                              reason);
        }
        atoms = std::move(kept);
    };
    check(problem.initial, "init");
    check(problem.goals, "goal");
}
static Lines domainLines(const Domain &domain) {
    Lines out{"== domain " + domain.name + " =="};
    append(out, domain.diagnostics);
    for (std::string type : domain.types) {
        Lines chain{type};
        while (type != "object") {
            type = domain.parents.at(type);
            chain.push_back(type);
        }
        out.push_back("type " + join(chain, " < "));
    }
    for (const Predicate &predicate : domain.predicates)
        out.push_back(text("predicate ", predicate.name, "/", predicate.types.size(),
                           domain.fluent.count(predicate.name) ? " fluent" : " static"));
    for (const Schema &schema : domain.actions) {
        int add = 0, del = 0;
        for (const Literal &effect : schema.effects)
            (effect.negative ? del : add)++;
        out.push_back(text("action ", schema.name, "/", schema.parameters.size(),
                           " cost=", schema.cost, " pre=", schema.conditions.size(), " add=", add,
                           " del=", del));
    }
    return out;
}
static Lines groundingLines(const GroundProblem &ground) {
    const Domain &domain = *ground.domain;
    const Problem &problem = *ground.problem;
    Lines out{"== problem " + problem.name + " =="};
    append(out, problem.diagnostics);
    out.push_back(text("objects: ", problem.objects.size()));
    for (const std::string &type : domain.types)
        out.push_back(heading("  " + type + ":", objectsOfType(domain, problem, type)));
    out.push_back(text("static facts: ", ground.staticFacts));
    for (std::size_t i = 0; i < domain.actions.size(); ++i) {
        const SchemaCount &count = ground.counts[i];
        out.push_back(text("schema ", domain.actions[i].name, ": assignments=", count.assignments,
                           " candidates=", count.candidates, " reachable=", count.reachable));
    }
    out.push_back(
        text("candidates: ", ground.candidateCount, " reachable: ", ground.actions.size()));
    out.push_back(text("facts: ", ground.facts.size(), " init: ", ground.initial.numbers().size(),
                       " goals: ", ground.goal.numbers().size()));
    for (const Atom &atom : ground.unreachable)
        out.push_back("unreachable goal: " + atom.text());
    std::map<std::string, int> counts;
    for (const Atom &atom : ground.facts)
        ++counts[atom.predicate];
    Lines items;
    for (const Predicate &predicate : domain.predicates)
        if (domain.fluent.count(predicate.name))
            items.push_back(text(predicate.name, "=", counts[predicate.name]));
    out.push_back(heading("facts by predicate:", items));
    out.push_back("facts:");
    for (std::size_t i = 0; i < ground.facts.size(); ++i)
        out.push_back(text("  ", i, " ", ground.facts[i].text()));
    out.push_back("actions:");
    for (std::size_t i = 0; i < ground.actions.size(); ++i) {
        const GroundAction &action = ground.actions[i];
        out.push_back(text("  ", i, " ", action.text(domain), " cost=", action.cost,
                           " pre=", numberList(action.pre), " neg=", numberList(action.neg),
                           " add=", numberList(action.add), " del=", numberList(action.del)));
    }
    return out;
}
struct Validation {
    std::string status;
    Lines messages;
    std::size_t correct = 0;
    std::string verdict() const { return status + (status == "valid" ? " " : ": ") + messages[0]; }
};
static Validation validateSteps(const Domain &domain, const Problem &problem,
                                const std::vector<Step> &steps) {
    std::set<std::string> world;
    for (const Atom &atom : problem.initial)
        world.insert(atom.text());
    std::map<std::string, const Schema *> schemas;
    for (const Schema &schema : domain.actions)
        schemas[schema.name] = &schema;
    const std::map<std::string, std::string> types = objectTypes(problem);
    Value cost = 0;
    for (std::size_t i = 0; i < steps.size(); ++i) {
        const Step &step = steps[i];
        std::string prefix = text("step ", i + 1, " ", step.text(), ": ");
        auto found = schemas.find(step.name);
        if (found == schemas.end())
            return {"invalid", {prefix + "unknown action " + step.name}, i};
        const Schema &schema = *found->second;
        Lines expected;
        for (const Typed &parameter : schema.parameters)
            expected.push_back(parameter.type);
        std::string reason = argumentCheck(domain, step.arguments, expected, types, "object");
        if (!reason.empty())
            return {"invalid", {prefix + reason}, i};
        std::map<std::string, std::string> assignment;
        for (std::size_t j = 0; j < schema.parameters.size(); ++j)
            assignment[schema.parameters[j].name] = step.arguments[j];
        for (const Literal &literal : schema.conditions) {
            Atom atom = substitute(literal.atom, assignment);
            bool truth = atom.predicate == "=" ? atom.terms[0] == atom.terms[1]
                                               : world.count(atom.text()) != 0;
            if (truth == literal.negative)
                return {"invalid",
                        {prefix + "precondition " + Literal{atom, literal.negative}.text() +
                         " is false"},
                        i};
        }
        for (const Literal &literal : schema.effects)
            if (literal.negative)
                world.erase(substitute(literal.atom, assignment).text());
        for (const Literal &literal : schema.effects)
            if (!literal.negative)
                world.insert(substitute(literal.atom, assignment).text());
        cost += schema.cost;
    }
    Lines missing;
    for (const Atom &atom : problem.goals)
        if (!world.count(atom.text()))
            missing.push_back("unsatisfied goal " + atom.text());
    if (!missing.empty())
        return {"goal not reached", missing, steps.size()};
    return {"valid", {text("length=", steps.size(), " cost=", cost)}, steps.size()};
}
static std::vector<Step> planSteps(const GroundProblem &ground, const Plan &plan) {
    std::vector<Step> out;
    for (int index : plan) {
        const GroundAction &action = ground.actions[index];
        out.push_back({ground.domain->actions[action.schema].name, action.arguments});
    }
    return out;
}
static Plan mapSteps(const GroundProblem &ground, const std::vector<Step> &steps,
                     std::size_t count) {
    std::map<std::string, int> index;
    for (std::size_t i = 0; i < ground.actions.size(); ++i)
        index[ground.actions[i].text(*ground.domain)] = static_cast<int>(i);
    Plan out;
    for (std::size_t i = 0; i < count; ++i)
        out.push_back(index.at(steps[i].text()));
    return out;
}
static Value planCost(const GroundProblem &ground, const Plan &plan) {
    Value cost = 0;
    for (int index : plan)
        cost += ground.actions[index].cost;
    return cost;
}
static Plan improve(const GroundProblem &ground, Plan plan) {
    for (std::size_t at = 0; at < plan.size();) {
        State state = ground.initial;
        for (std::size_t i = 0; i < at; ++i)
            state = apply(ground.actions[plan[i]], state);
        Plan kept(plan.begin(), plan.begin() + static_cast<std::ptrdiff_t>(at));
        for (std::size_t i = at + 1; i < plan.size(); ++i)
            if (applicable(ground.actions[plan[i]], state)) {
                state = apply(ground.actions[plan[i]], state);
                kept.push_back(plan[i]);
            }
        if (state.contains(ground.goal))
            plan = std::move(kept);
        else
            ++at;
    }
    return plan;
}
static bool interfere(const GroundAction &a, const GroundAction &b) {
    return a.del.intersects(b.pre.united(b.add)) || b.del.intersects(a.pre.united(a.add)) ||
           a.add.intersects(b.neg) || b.add.intersects(a.neg);
}
static Layers parallelize(const GroundProblem &ground, const Plan &plan) {
    Plan layer(plan.size(), 1);
    int count = 0;
    for (std::size_t j = 0; j < plan.size(); ++j) {
        const GroundAction &action = ground.actions[plan[j]];
        for (std::size_t i = 0; i < j; ++i) {
            const GroundAction &previous = ground.actions[plan[i]];
            if (previous.add.intersects(action.pre) || previous.del.intersects(action.neg) ||
                interfere(previous, action))
                layer[j] = std::max(layer[j], layer[i] + 1);
        }
        count = std::max(count, layer[j]);
    }
    Layers out(count);
    for (std::size_t i = 0; i < plan.size(); ++i)
        out[layer[i] - 1].push_back(plan[i]);
    return out;
}
static std::string parallelValidation(const GroundProblem &ground, const Layers &layers) {
    State state = ground.initial;
    for (std::size_t k = 0; k < layers.size(); ++k) {
        const Plan &layer = layers[k];
        State adds, deletes;
        for (std::size_t i = 0; i < layer.size(); ++i) {
            const GroundAction &action = ground.actions[layer[i]];
            if (!applicable(action, state))
                return text("invalid at layer ", k + 1);
            for (std::size_t j = i + 1; j < layer.size(); ++j)
                if (interfere(action, ground.actions[layer[j]]))
                    return text("invalid at layer ", k + 1);
            adds = adds.united(action.add);
            deletes = deletes.united(action.del);
        }
        state = state.without(deletes).united(adds);
    }
    return state.contains(ground.goal) ? "valid" : "goal not reached";
}
static std::tuple<std::vector<GraphElement>, State, int>
transformedGraph(const GroundProblem &ground) {
    State negative;
    for (const GroundAction &action : ground.actions)
        negative = negative.united(action.neg);
    std::map<int, int> complement;
    int next = static_cast<int>(ground.facts.size());
    for (int fact : negative.numbers())
        complement[fact] = next++;
    State initial = ground.initial;
    for (const auto &entry : complement)
        if (!initial.has(entry.first))
            initial.put(entry.second);
    std::vector<GraphElement> out;
    for (std::size_t i = 0; i < ground.actions.size(); ++i) {
        const GroundAction &action = ground.actions[i];
        GraphElement entry{static_cast<int>(i), -1, action.pre, action.add, action.del};
        for (int fact : action.neg.numbers())
            entry.pre.put(complement.at(fact));
        for (int fact : action.del.numbers())
            if (complement.count(fact))
                entry.add.put(complement.at(fact));
        for (int fact : action.add.numbers())
            if (complement.count(fact))
                entry.del.put(complement.at(fact));
        out.push_back(entry);
    }
    return {out, initial, static_cast<int>(complement.size())};
}
static std::string heuristicText(Value value) {
    return value == infinity ? "inf" : std::to_string(value);
}
static std::string heuristicValues(const Heuristic &heuristic) {
    Lines out;
    for (const std::string &name : heuristicNames)
        out.push_back(name + "=" + heuristicText(heuristic.value(name)));
    return join(out, " ");
}
static Lines actionTexts(const GroundProblem &ground, const Plan &plan) {
    Lines out;
    for (int action : plan)
        out.push_back(ground.actions[action].text(*ground.domain));
    return out;
}
struct RunRecord {
    SearchSettings settings;
    std::string tag;
    SearchResult result;
};
struct ProblemResult {
    GroundProblem *ground = nullptr;
    std::vector<RunRecord> runs;
    GraphPlanResult graph;
    int proof = -1, solved = 0;
    Value best = -1;
    std::string optimal = "unknown";
};
struct Output {
    Lines plans, graph, validation,
        comparison{"problem,algorithm,heuristic,length,cost,expanded,generated"};
    int validated = 0, validPlans = 0;
};
static std::pair<Lines, Lines> planBlock(GroundProblem &ground, const std::string &tag,
                                         const Plan &plan, std::map<Plan, std::string> &seen,
                                         Output &output) {
    std::string first = text("plan: length=", plan.size(), " cost=", planCost(ground, plan));
    auto previous = seen.find(plan);
    if (previous == seen.end())
        seen[plan] = tag;
    else
        first += " (same as " + previous->second + ")";
    Lines out{first};
    std::vector<int> counts(ground.domain->actions.size());
    for (std::size_t i = 0; i < plan.size(); ++i) {
        const GroundAction &action = ground.actions[plan[i]];
        ++counts[action.schema];
        out.push_back(text("  ", i + 1, " ", action.text(*ground.domain)));
    }
    Lines items;
    for (std::size_t i = 0; i < counts.size(); ++i)
        if (counts[i])
            items.push_back(text(ground.domain->actions[i].name, "=", counts[i]));
    out.push_back(heading("schemas:", items));
    Layers layers = parallelize(ground, plan);
    out.push_back(text("parallel: layers=", layers.size()));
    for (std::size_t i = 0; i < layers.size(); ++i)
        out.push_back(heading(text("  ", i + 1, ":"), actionTexts(ground, layers[i])));
    Plan improved = improve(ground, plan);
    std::size_t removed = plan.size() - improved.size();
    out.push_back(text("improved: length=", improved.size(), " cost=", planCost(ground, improved),
                       " removed=", removed));
    if (removed)
        for (std::size_t i = 0; i < improved.size(); ++i)
            out.push_back(text("  ", i + 1, " ", ground.actions[improved[i]].text(*ground.domain)));
    State landmarks = ground.heuristics(ground.initial).landmarks, reached, state = ground.initial;
    for (int index : plan) {
        state = apply(ground.actions[index], state);
        reached = reached.united(state.intersected(landmarks));
    }
    out.push_back(
        text("landmarks reached: ", reached.numbers().size(), "/", landmarks.numbers().size()));
    for (int fact : landmarks.without(reached).numbers())
        out.push_back("  missed " + ground.facts[fact].text());
    Validation original = validateSteps(*ground.domain, *ground.problem, planSteps(ground, plan));
    Validation better = validateSteps(*ground.domain, *ground.problem, planSteps(ground, improved));
    ++output.validated;
    if (original.status == "valid")
        ++output.validPlans;
    return {out,
            {tag + ": " + original.verdict(), "  parallel: " + parallelValidation(ground, layers),
             "  improved: " + better.verdict()}};
}
static Lines profile(GroundProblem &ground, const RunRecord &proof) {
    const Plan &plan = proof.result.plan;
    Lines out{"-- profile (" + proof.tag + ") --"};
    Value remaining = planCost(ground, plan);
    State state = ground.initial;
    std::array<int, 5> overestimates{};
    for (std::size_t i = 0; i <= plan.size(); ++i) {
        const Heuristic &heuristic = ground.heuristics(state);
        out.push_back(text("  ", i, ": h*=", remaining, " ", heuristicValues(heuristic)));
        for (std::size_t j = 0; j < heuristicNames.size(); ++j)
            if (heuristic.value(heuristicNames[j]) > remaining)
                ++overestimates[j];
        if (i < plan.size()) {
            remaining -= ground.actions[plan[i]].cost;
            state = apply(ground.actions[plan[i]], state);
        }
    }
    Lines counts;
    for (std::size_t i = 0; i < heuristicNames.size(); ++i)
        counts.push_back(text(heuristicNames[i], "=", overestimates[i]));
    out.push_back("overestimates: " + join(counts, " "));
    out.push_back("-- causal links (" + proof.tag + ") --");
    Plan supplier(ground.facts.size());
    for (std::size_t i = 0; i < plan.size(); ++i) {
        const GroundAction &action = ground.actions[plan[i]];
        Lines items;
        for (int fact : action.pre.numbers())
            items.push_back(text(ground.facts[fact].text(), "<-", supplier[fact]));
        out.push_back(heading(text("  ", i + 1, " ", action.text(*ground.domain), ":"), items));
        for (int fact : action.add.numbers())
            supplier[fact] = static_cast<int>(i + 1);
    }
    Lines items;
    for (int fact : ground.goal.numbers())
        items.push_back(text(ground.facts[fact].text(), "<-", supplier[fact]));
    out.push_back(heading("  goal:", items));
    return out;
}
static std::string resultLine(const SearchResult &result) {
    if (result.status == "unreachable goal")
        return "result: FAIL (unreachable goal)";
    std::string prefix =
        result.status == "solved" ? "result: solved" : "result: FAIL (" + result.status + ")";
    return text(prefix, " expanded=", result.expanded, " generated=", result.generated);
}
static ProblemResult processProblem(GroundProblem &ground, const Settings &settings,
                                    Output &output) {
    ProblemResult out;
    out.ground = &ground;
    std::string title = "== problem " + ground.problem->name + " ==";
    output.plans.push_back(title);
    output.graph.push_back(title);
    output.validation.push_back(title);
    bool unreachable = !ground.unreachable.empty();
    if (unreachable)
        output.plans.push_back("initial h: unreachable goal");
    else {
        const Heuristic &heuristic = ground.heuristics(ground.initial);
        output.plans.push_back("initial h: " + heuristicValues(heuristic));
        output.plans.push_back(text("landmarks: ", heuristic.landmarks.numbers().size()));
        for (int fact : heuristic.landmarks.numbers())
            output.plans.push_back("  " + ground.facts[fact].text());
        output.plans.push_back(text("relaxed plan: length=", heuristic.relaxed.size(),
                                    " cost=", heuristicText(heuristic.ff)));
        for (int action : heuristic.relaxed)
            output.plans.push_back("  " + ground.actions[action].text(*ground.domain));
        output.plans.push_back(heading("helpful:", actionTexts(ground, heuristic.helpful)));
    }
    for (const SearchSettings &run : settings.runs) {
        SearchResult result;
        if (unreachable)
            result.status = "unreachable goal";
        else
            result = search(ground, ground.initial, run, settings.budget, settings.weight);
        if (out.proof < 0 && result.status == "solved" &&
            (run.tag() == "ucs none" || run.tag() == "astar hmax"))
            out.proof = static_cast<int>(out.runs.size());
        out.runs.push_back({run, run.tag(), std::move(result)});
    }
    if (unreachable) {
        out.graph.status = "unreachable goal";
        output.graph.push_back("result: FAIL (unreachable goal)");
    } else {
        auto [actions, initial, count] = transformedGraph(ground);
        out.graph = graphPlan(actions, initial, ground.goal, settings.levelLimit);
        const GraphPlanResult &result = out.graph;
        output.graph.push_back(text("complementary facts: ", count));
        append(output.graph, result.logs);
        if (result.status == "solved") {
            output.graph.push_back(
                text("result: solved levels=", result.layers.size(), " length=", result.plan.size(),
                     " cost=", planCost(ground, result.plan), " searched=", result.searched,
                     " memo_hits=", result.memoHits, " tried=", result.tried));
            for (std::size_t i = 0; i < result.layers.size(); ++i)
                output.graph.push_back(
                    heading(text("layer ", i + 1, ":"), actionTexts(ground, result.layers[i])));
        } else
            output.graph.push_back(text("result: FAIL (", result.status,
                                        ") searched=", result.searched,
                                        " memo_hits=", result.memoHits, " tried=", result.tried));
    }
    out.runs.push_back({{"graphplan", "none"},
                        "graphplan",
                        {out.graph.status, out.graph.plan, out.graph.searched, out.graph.tried}});
    std::map<Plan, std::string> seen;
    for (const RunRecord &record : out.runs) {
        const SearchResult &result = record.result;
        output.plans.push_back("-- " + record.tag + " --");
        output.plans.push_back(resultLine(result));
        std::string length = "-", cost = "-";
        if (result.status == "solved") {
            ++out.solved;
            Value value = planCost(ground, result.plan);
            if (out.best < 0 || value < out.best)
                out.best = value;
            length = std::to_string(result.plan.size());
            cost = std::to_string(value);
            auto block = planBlock(ground, record.tag, result.plan, seen, output);
            append(output.plans, block.first);
            append(output.validation, block.second);
        }
        output.comparison.push_back(text(ground.problem->name, ",", record.settings.algorithm, ",",
                                         record.settings.heuristic, ",", length, ",", cost, ",",
                                         result.expanded, ",", result.generated));
    }
    if (out.proof >= 0) {
        out.optimal = std::to_string(planCost(ground, out.runs[out.proof].result.plan));
        append(output.plans, profile(ground, out.runs[out.proof]));
    } else
        for (const RunRecord &record : out.runs) {
            const std::string &status = record.result.status;
            if (status == "unreachable goal" || status == "dead end" || status == "exhausted" ||
                status == "unreachable") {
                out.optimal = "none";
                break;
            }
        }
    output.plans.push_back("");
    output.graph.push_back("");
    output.validation.push_back("");
    return out;
}
static std::string bestText(Value best) { return best < 0 ? "-" : std::to_string(best); }
static int candidateLines(const Domain &domain, const std::vector<CandidatePlan> &candidates,
                          std::vector<ProblemResult> &problems, const Settings &settings,
                          Lines &out) {
    out.push_back("== candidates ==");
    int valid = 0;
    std::map<std::string, ProblemResult *> byName;
    for (ProblemResult &problem : problems)
        byName[problem.ground->problem->name] = &problem;
    for (std::size_t i = 0; i < candidates.size(); ++i) {
        const CandidatePlan &candidate = candidates[i];
        ProblemResult &problem = *byName.at(candidate.problem);
        GroundProblem &ground = *problem.ground;
        Validation validation = validateSteps(domain, *ground.problem, candidate.steps);
        std::string prefix =
            text("candidate ", i + 1, " ", candidate.problem, " ", candidate.label, ": ");
        if (validation.status == "valid") {
            ++valid;
            Plan plan = mapSteps(ground, candidate.steps, candidate.steps.size()),
                 improved = improve(ground, plan);
            out.push_back(prefix + validation.verdict());
            out.push_back(text("  improved: length=", improved.size(),
                               " cost=", planCost(ground, improved),
                               " removed=", candidate.steps.size() - improved.size(),
                               " best known=", bestText(problem.best)));
            continue;
        }
        out.push_back(prefix + validation.status);
        for (const std::string &message : validation.messages)
            out.push_back("  " + message);
        if (!ground.unreachable.empty()) {
            out.push_back("  repair: FAIL (unreachable goal)");
            continue;
        }
        Plan prefixPlan = mapSteps(ground, candidate.steps, validation.correct);
        State state = ground.initial;
        for (int action : prefixPlan)
            state = apply(ground.actions[action], state);
        SearchResult repair =
            search(ground, state, settings.repair, settings.budget, settings.weight);
        if (repair.status != "solved") {
            out.push_back("  repair: FAIL (" + repair.status + ")");
            continue;
        }
        Plan plan = prefixPlan;
        plan.insert(plan.end(), repair.plan.begin(), repair.plan.end());
        Validation repaired = validateSteps(domain, *ground.problem, planSteps(ground, plan));
        out.push_back(text("  repair: kept=", prefixPlan.size(), " added=", repair.plan.size(), " ",
                           repaired.verdict()));
        for (std::size_t j = 0; j < plan.size(); ++j)
            out.push_back(text("    ", j + 1, " ", ground.actions[plan[j]].text(domain)));
    }
    return valid;
}
static void writeLines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    if (!output)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        output << line << '\n';
    if (!output)
        throw std::runtime_error("cannot write " + name);
}
int main() {
    Domain domain = readDomain();
    validateDomain(domain);
    std::vector<Problem> raw = readProblems();
    Settings settings = readSettings();
    const std::vector<CandidatePlan> candidates = readCandidates();
    Lines grounding = domainLines(domain);
    Output output;
    std::vector<GroundProblem> grounds;
    grounds.reserve(raw.size());
    std::vector<ProblemResult> problems;
    for (Problem &problem : raw) {
        validateProblem(domain, problem);
        grounds.push_back(ground(domain, problem));
        GroundProblem &current = grounds.back();
        grounding.push_back("");
        append(grounding, groundingLines(current));
        problems.push_back(processProblem(current, settings, output));
    }
    output.plans.push_back("== summary ==");
    for (const ProblemResult &problem : problems)
        output.plans.push_back(text(problem.ground->problem->name, ": solved=", problem.solved, "/",
                                    problem.runs.size(), " best=", bestText(problem.best),
                                    " optimal=", problem.optimal));
    for (std::size_t i = 0; i < problems[0].runs.size(); ++i) {
        int solved = 0, best = 0;
        Value expanded = 0, generated = 0;
        for (const ProblemResult &problem : problems) {
            const SearchResult &result = problem.runs[i].result;
            expanded += result.expanded;
            generated += result.generated;
            if (result.status == "solved") {
                ++solved;
                if (planCost(*problem.ground, result.plan) == problem.best)
                    ++best;
            }
        }
        output.plans.push_back(text(problems[0].runs[i].tag, ": solved=", solved, " best=", best,
                                    " expanded=", expanded, " generated=", generated));
    }
    int validCandidates = candidateLines(domain, candidates, problems, settings, output.validation);
    output.validation.push_back("");
    output.validation.push_back("== summary ==");
    output.validation.push_back(text("plans: ", output.validated, " valid: ", output.validPlans));
    output.validation.push_back(
        text("candidates: ", candidates.size(), " valid: ", validCandidates));
    std::filesystem::create_directories("output");
    writeLines("grounding.txt", grounding);
    writeLines("plans.txt", output.plans);
    writeLines("graphplan.txt", output.graph);
    writeLines("validation.txt", output.validation);
    writeLines("comparison.csv", output.comparison);
}
