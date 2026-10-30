#include "planner.h"
static const char *heuristic_names[] = {"goalcount", "hmax", "hadd", "ff", "lmcount"};
static void append_owned(TextLines *lines, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(lines, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
static char *heading(const char *name, const TextLines *items) {
    char *joined = items->count ? join_texts(items, " ") : copy_text("-");
    char *out = format_text("%s %s", name, joined);
    free(joined);
    return out;
}
static char *number_list(State state) {
    TextLines items = {0};
    for (int i = 0; i < 256; ++i)
        if (state_has(state, i))
            lines_push(&items, format_text("%d", i));
    char *out = items.count ? join_texts(&items, ",") : copy_text("-");
    lines_free(&items);
    return out;
}
static char *step_text(const Step *step) {
    return atom_text(intern_atom(step->name, &step->arguments));
}
static char *action_text(const GroundProblem *ground, int index) {
    const GroundAction *action = &ground->actions[index];
    return atom_text(intern_atom(ground->domain->actions[action->schema].name, &action->arguments));
}
static TextLines action_texts(const GroundProblem *ground, const IntList *plan) {
    TextLines out = {0};
    for (int i = 0; i < plan->count; ++i)
        lines_push(&out, action_text(ground, plan->data[i]));
    return out;
}
static Settings read_settings(void) {
    Settings out = {0};
    TextLines lines = read_lines("input/params.txt");
    for (int i = 0; i < lines.count; ++i) {
        if (!lines.data[i][0] || lines.data[i][0] == '#')
            continue;
        IntList words = split_words(lines.data[i]);
        const char *kind = symbol_name(words.data[0]);
        if (!strcmp(kind, "budget"))
            out.budget = atoi(symbol_name(words.data[1]));
        else if (!strcmp(kind, "weight"))
            out.weight = atoi(symbol_name(words.data[1]));
        else if (!strcmp(kind, "graphplan"))
            out.level_limit = atoi(symbol_name(words.data[1]));
        else {
            SearchSettings settings = {symbol_name(words.data[1]), symbol_name(words.data[2])};
            if (!strcmp(kind, "run"))
                out.runs[out.run_count++] = settings;
            else
                out.repair = settings;
        }
        int_free(&words);
    }
    lines_free(&lines);
    return out;
}
static void steps_push(StepList *list, Step step) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = step;
}
static CandidatePlan *read_candidates(int *count) {
    CandidatePlan *out = allocate(20 * sizeof *out);
    *count = 0;
    TextLines lines = read_lines("input/candidates.txt");
    for (int i = 0; i < lines.count; ++i) {
        char *line = lines.data[i];
        if (!line[0] || line[0] == '#')
            continue;
        if (!strncmp(line, "plan ", 5)) {
            IntList words = split_words(line);
            out[*count].problem = words.data[1];
            out[(*count)++].label = words.data[2];
            int_free(&words);
        } else if (strcmp(line, "end")) {
            line[strlen(line) - 1] = 0;
            IntList words = split_words(line + 1);
            Step step = {words.data[0], {0}};
            for (int j = 1; j < words.count; ++j)
                int_push(&step.arguments, words.data[j]);
            steps_push(&out[*count - 1].steps, step);
            int_free(&words);
        }
    }
    lines_free(&lines);
    return out;
}
static char *argument_check(const Domain *domain, const IntList *arguments, const IntList *expected,
                            const TypedList *types, const char *noun) {
    if (arguments->count != expected->count)
        return format_text("expected %d arguments, got %d", expected->count, arguments->count);
    for (int i = 0; i < arguments->count; ++i) {
        int argument = arguments->data[i], type = typed_find(types, argument);
        if (type < 0)
            return format_text("unknown %s %s", noun, symbol_name(argument));
        if (!subtype(domain, type, expected->data[i]))
            return format_text("argument %d (%s) is not of type %s", i + 1, symbol_name(argument),
                               symbol_name(expected->data[i]));
    }
    return NULL;
}
static void validate_domain(Domain *domain) {
    int kept = 0;
    for (int i = 0; i < domain->action_count; ++i) {
        Schema schema = domain->actions[i];
        char *reason = NULL;
        for (int j = 0; j < schema.parameters.count; ++j)
            if (!reason && !int_has(&domain->types, schema.parameters.data[j].type))
                reason =
                    format_text("unknown type %s", symbol_name(schema.parameters.data[j].type));
        for (int side = 0; side < 2 && !reason; ++side) {
            LiteralList *literals = side ? &schema.effects : &schema.conditions;
            for (int j = 0; j < literals->count; ++j) {
                int id = literals->data[j].atom;
                const Atom *atom = get_atom(id);
                IntList expected = {0};
                int equality[2] = {symbol("object"), symbol("object")};
                if (!strcmp(symbol_name(atom->predicate), "="))
                    expected = (IntList){equality, 2, 2};
                else {
                    int predicate = predicate_index(domain, atom->predicate);
                    if (predicate < 0) {
                        char *notation = atom_text(id);
                        reason = format_text("%s: unknown predicate %s", notation,
                                             symbol_name(atom->predicate));
                        free(notation);
                        break;
                    }
                    expected = domain->predicates[predicate].types;
                }
                char *error =
                    argument_check(domain, &atom->terms, &expected, &schema.parameters, "variable");
                if (error) {
                    char *notation = atom_text(id);
                    reason = format_text("%s: %s", notation, error);
                    free(notation);
                    free(error);
                    break;
                }
            }
        }
        if (reason) {
            lines_push(&domain->diagnostics,
                       format_text("error: action %s: %s", symbol_name(schema.name), reason));
            free(reason);
            free(schema.parameters.data);
            free(schema.conditions.data);
            free(schema.effects.data);
        } else
            domain->actions[kept++] = schema;
    }
    domain->action_count = kept;
    IntList used = {0};
    for (int i = 0; i < kept; ++i) {
        const Schema *schema = &domain->actions[i];
        for (int j = 0; j < schema->conditions.count; ++j)
            int_add(&used, get_atom(schema->conditions.data[j].atom)->predicate);
        for (int j = 0; j < schema->effects.count; ++j)
            int_add(&used, get_atom(schema->effects.data[j].atom)->predicate);
    }
    for (int i = 0; i < domain->predicate_count; ++i)
        if (!int_has(&used, domain->predicates[i].name))
            lines_push(&domain->diagnostics,
                       format_text("warning: predicate %s is not used by any action",
                                   symbol_name(domain->predicates[i].name)));
    int_free(&used);
    classify(domain);
}
static void validate_atoms(const Domain *domain, Problem *problem, IntList *atoms,
                           const char *side) {
    IntList kept = {0};
    for (int i = 0; i < atoms->count; ++i) {
        int id = atoms->data[i];
        const Atom *atom = get_atom(id);
        int predicate = predicate_index(domain, atom->predicate);
        char *reason = NULL;
        if (predicate < 0)
            reason = format_text("unknown predicate %s", symbol_name(atom->predicate));
        else
            reason = argument_check(domain, &atom->terms, &domain->predicates[predicate].types,
                                    &problem->objects, "object");
        if (!reason && int_has(&kept, id))
            reason = copy_text("duplicate");
        if (reason) {
            char *notation = atom_text(id);
            lines_push(&problem->diagnostics,
                       format_text("warning: %s %s: %s", side, notation, reason));
            free(notation);
            free(reason);
        } else
            int_push(&kept, id);
    }
    int_free(atoms);
    *atoms = kept;
}
static void validate_problem(const Domain *domain, Problem *problem) {
    validate_atoms(domain, problem, &problem->initial, "init");
    validate_atoms(domain, problem, &problem->goals, "goal");
}
static TextLines domain_lines(const Domain *domain) {
    TextLines out = {0};
    lines_push(&out, format_text("== domain %s ==", symbol_name(domain->name)));
    lines_append(&out, &domain->diagnostics);
    int object = symbol("object");
    for (int i = 0; i < domain->types.count; ++i) {
        int type = domain->types.data[i];
        IntList chain = {0};
        int_push(&chain, type);
        while (type != object) {
            type = typed_find(&domain->parents, type);
            int_push(&chain, type);
        }
        char *joined = join_words(&chain, " < ");
        lines_push(&out, format_text("type %s", joined));
        free(joined);
        int_free(&chain);
    }
    for (int i = 0; i < domain->predicate_count; ++i)
        lines_push(&out, format_text("predicate %s/%d %s", symbol_name(domain->predicates[i].name),
                                     domain->predicates[i].types.count,
                                     domain->fluent[i] ? "fluent" : "static"));
    for (int i = 0; i < domain->action_count; ++i) {
        const Schema *schema = &domain->actions[i];
        int adds = 0, deletes = 0;
        for (int j = 0; j < schema->effects.count; ++j) {
            if (schema->effects.data[j].negative)
                ++deletes;
            else
                ++adds;
        }
        lines_push(&out, format_text("action %s/%d cost=%lld pre=%d add=%d del=%d",
                                     symbol_name(schema->name), schema->parameters.count,
                                     schema->cost, schema->conditions.count, adds, deletes));
    }
    return out;
}
static TextLines grounding_lines(const GroundProblem *ground) {
    const Domain *domain = ground->domain;
    const Problem *problem = ground->problem;
    TextLines out = {0};
    lines_push(&out, format_text("== problem %s ==", symbol_name(problem->name)));
    lines_append(&out, &problem->diagnostics);
    lines_push(&out, format_text("objects: %d", problem->objects.count));
    for (int i = 0; i < domain->types.count; ++i) {
        IntList objects = objects_of_type(domain, problem, domain->types.data[i]);
        TextLines names = {0};
        for (int j = 0; j < objects.count; ++j)
            lines_add(&names, symbol_name(objects.data[j]));
        char *name = format_text("  %s:", symbol_name(domain->types.data[i]));
        lines_push(&out, heading(name, &names));
        free(name);
        lines_free(&names);
        int_free(&objects);
    }
    lines_push(&out, format_text("static facts: %d", ground->static_facts));
    for (int i = 0; i < domain->action_count; ++i) {
        const SchemaCount *count = &ground->counts[i];
        lines_push(&out, format_text("schema %s: assignments=%d candidates=%d reachable=%d",
                                     symbol_name(domain->actions[i].name), count->assignments,
                                     count->candidates, count->reachable));
    }
    lines_push(&out, format_text("candidates: %d reachable: %d", ground->candidate_count,
                                 ground->action_count));
    lines_push(&out, format_text("facts: %d init: %d goals: %d", ground->facts.count,
                                 state_count(ground->initial), state_count(ground->goal)));
    for (int i = 0; i < ground->unreachable.count; ++i) {
        char *atom = atom_text(ground->unreachable.data[i]);
        lines_push(&out, format_text("unreachable goal: %s", atom));
        free(atom);
    }
    int counts[15] = {0};
    for (int i = 0; i < ground->facts.count; ++i)
        ++counts[predicate_index(domain, get_atom(ground->facts.data[i])->predicate)];
    TextLines items = {0};
    for (int i = 0; i < domain->predicate_count; ++i)
        if (domain->fluent[i])
            lines_push(&items,
                       format_text("%s=%d", symbol_name(domain->predicates[i].name), counts[i]));
    lines_push(&out, heading("facts by predicate:", &items));
    lines_free(&items);
    lines_add(&out, "facts:");
    for (int i = 0; i < ground->facts.count; ++i) {
        char *atom = atom_text(ground->facts.data[i]);
        lines_push(&out, format_text("  %d %s", i, atom));
        free(atom);
    }
    lines_add(&out, "actions:");
    for (int i = 0; i < ground->action_count; ++i) {
        const GroundAction *action = &ground->actions[i];
        char *notation = action_text(ground, i), *pre = number_list(action->pre),
             *neg = number_list(action->neg), *add = number_list(action->add),
             *del = number_list(action->del);
        lines_push(&out, format_text("  %d %s cost=%lld pre=%s neg=%s add=%s del=%s", i, notation,
                                     action->cost, pre, neg, add, del));
        free(notation);
        free(pre);
        free(neg);
        free(add);
        free(del);
    }
    return out;
}
typedef struct {
    const char *status;
    TextLines messages;
    int correct;
} Validation;
static char *verdict(const Validation *validation) {
    return format_text("%s%s%s", validation->status,
                       !strcmp(validation->status, "valid") ? " " : ": ",
                       validation->messages.data[0]);
}
static Validation validate_steps(const Domain *domain, const Problem *problem,
                                 const StepList *steps) {
    Validation out = {0};
    IntList world = int_copy(&problem->initial);
    Value cost = 0;
    for (int i = 0; i < steps->count; ++i) {
        const Step *step = &steps->data[i];
        char *notation = step_text(step), *prefix = format_text("step %d %s: ", i + 1, notation);
        free(notation);
        const Schema *schema = NULL;
        for (int j = 0; j < domain->action_count; ++j)
            if (domain->actions[j].name == step->name) {
                schema = &domain->actions[j];
                break;
            }
        char *reason = NULL;
        if (!schema)
            reason = format_text("unknown action %s", symbol_name(step->name));
        else {
            IntList expected = {0};
            for (int j = 0; j < schema->parameters.count; ++j)
                int_push(&expected, schema->parameters.data[j].type);
            reason =
                argument_check(domain, &step->arguments, &expected, &problem->objects, "object");
            int_free(&expected);
        }
        TypedList assignment = {0};
        if (!reason) {
            assignment.count = assignment.capacity = schema->parameters.count;
            assignment.data = allocate((size_t)assignment.count * sizeof *assignment.data);
            for (int j = 0; j < assignment.count; ++j)
                assignment.data[j] =
                    (Typed){schema->parameters.data[j].name, step->arguments.data[j]};
            for (int j = 0; j < schema->conditions.count; ++j) {
                Literal literal = schema->conditions.data[j];
                literal.atom = substitute_atom(literal.atom, &assignment);
                const Atom *atom = get_atom(literal.atom);
                bool truth = !strcmp(symbol_name(atom->predicate), "=")
                                 ? atom->terms.data[0] == atom->terms.data[1]
                                 : int_has(&world, literal.atom);
                if (truth == literal.negative) {
                    char *literal_notation = literal_text(literal);
                    reason = format_text("precondition %s is false", literal_notation);
                    free(literal_notation);
                    break;
                }
            }
        }
        if (reason) {
            out.status = "invalid";
            out.correct = i;
            lines_push(&out.messages, format_text("%s%s", prefix, reason));
            free(prefix);
            free(reason);
            free(assignment.data);
            int_free(&world);
            return out;
        }
        for (int j = 0; j < schema->effects.count; ++j)
            if (schema->effects.data[j].negative) {
                int id = substitute_atom(schema->effects.data[j].atom, &assignment), kept = 0;
                for (int k = 0; k < world.count; ++k)
                    if (world.data[k] != id)
                        world.data[kept++] = world.data[k];
                world.count = kept;
            }
        for (int j = 0; j < schema->effects.count; ++j)
            if (!schema->effects.data[j].negative)
                int_add(&world, substitute_atom(schema->effects.data[j].atom, &assignment));
        cost += schema->cost;
        free(assignment.data);
        free(prefix);
    }
    out.correct = steps->count;
    for (int i = 0; i < problem->goals.count; ++i)
        if (!int_has(&world, problem->goals.data[i])) {
            char *atom = atom_text(problem->goals.data[i]);
            lines_push(&out.messages, format_text("unsatisfied goal %s", atom));
            free(atom);
        }
    int_free(&world);
    if (out.messages.count)
        out.status = "goal not reached";
    else {
        out.status = "valid";
        lines_push(&out.messages, format_text("length=%d cost=%lld", steps->count, cost));
    }
    return out;
}
static Validation validate_plan(const GroundProblem *ground, const IntList *plan) {
    StepList steps = {0};
    for (int i = 0; i < plan->count; ++i) {
        const GroundAction *action = &ground->actions[plan->data[i]];
        steps_push(&steps, (Step){ground->domain->actions[action->schema].name, action->arguments});
    }
    Validation out = validate_steps(ground->domain, ground->problem, &steps);
    free(steps.data);
    return out;
}
static IntList map_steps(const GroundProblem *ground, const StepList *steps, int count) {
    IntList out = {0};
    for (int i = 0; i < count; ++i) {
        for (int j = 0; j < ground->action_count; ++j) {
            const GroundAction *action = &ground->actions[j];
            const Step *step = &steps->data[i];
            if (ground->domain->actions[action->schema].name == step->name &&
                action->arguments.count == step->arguments.count &&
                (!step->arguments.count ||
                 !memcmp(action->arguments.data, step->arguments.data,
                         (size_t)step->arguments.count * sizeof *step->arguments.data))) {
                int_push(&out, j);
                break;
            }
        }
    }
    return out;
}
static Value plan_cost(const GroundProblem *ground, const IntList *plan) {
    Value cost = 0;
    for (int i = 0; i < plan->count; ++i)
        cost += ground->actions[plan->data[i]].cost;
    return cost;
}
static IntList improve(const GroundProblem *ground, const IntList *source) {
    IntList plan = int_copy(source);
    for (int at = 0; at < plan.count;) {
        State state = ground->initial;
        IntList kept = {0};
        for (int i = 0; i < at; ++i) {
            state = apply(&ground->actions[plan.data[i]], state);
            int_push(&kept, plan.data[i]);
        }
        for (int i = at + 1; i < plan.count; ++i)
            if (applicable(&ground->actions[plan.data[i]], state)) {
                state = apply(&ground->actions[plan.data[i]], state);
                int_push(&kept, plan.data[i]);
            }
        if (state_contains(state, ground->goal)) {
            int_free(&plan);
            plan = kept;
        } else {
            int_free(&kept);
            ++at;
        }
    }
    return plan;
}
static bool interfere(const GroundAction *a, const GroundAction *b) {
    return state_intersects(a->del, state_union(b->pre, b->add)) ||
           state_intersects(b->del, state_union(a->pre, a->add)) ||
           state_intersects(a->add, b->neg) || state_intersects(b->add, a->neg);
}
static Layers parallelize(const GroundProblem *ground, const IntList *plan) {
    int *layer = allocate((size_t)plan->count * sizeof *layer), count = 0;
    for (int j = 0; j < plan->count; ++j) {
        layer[j] = 1;
        const GroundAction *action = &ground->actions[plan->data[j]];
        for (int i = 0; i < j; ++i) {
            const GroundAction *previous = &ground->actions[plan->data[i]];
            if ((state_intersects(previous->add, action->pre) ||
                 state_intersects(previous->del, action->neg) || interfere(previous, action)) &&
                layer[i] + 1 > layer[j])
                layer[j] = layer[i] + 1;
        }
        if (layer[j] > count)
            count = layer[j];
    }
    Layers out = {0};
    for (int i = 0; i < count; ++i)
        layers_push(&out, (IntList){0});
    for (int i = 0; i < plan->count; ++i)
        int_push(&out.data[layer[i] - 1], plan->data[i]);
    free(layer);
    return out;
}
static char *parallel_validation(const GroundProblem *ground, const Layers *layers) {
    State state = ground->initial;
    for (int k = 0; k < layers->count; ++k) {
        const IntList *layer = &layers->data[k];
        State adds = {0}, deletes = {0};
        for (int i = 0; i < layer->count; ++i) {
            const GroundAction *action = &ground->actions[layer->data[i]];
            if (!applicable(action, state))
                return format_text("invalid at layer %d", k + 1);
            for (int j = i + 1; j < layer->count; ++j)
                if (interfere(action, &ground->actions[layer->data[j]]))
                    return format_text("invalid at layer %d", k + 1);
            adds = state_union(adds, action->add);
            deletes = state_union(deletes, action->del);
        }
        state = state_union(state_without(state, deletes), adds);
    }
    return copy_text(state_contains(state, ground->goal) ? "valid" : "goal not reached");
}
static int transformed_graph(const GroundProblem *ground, GraphElement *actions, State *initial) {
    State negative = {0};
    for (int i = 0; i < ground->action_count; ++i)
        negative = state_union(negative, ground->actions[i].neg);
    int complement[100], count = 0;
    for (int fact = 0; fact < ground->facts.count; ++fact)
        complement[fact] = state_has(negative, fact) ? ground->facts.count + count++ : -1;
    *initial = ground->initial;
    for (int fact = 0; fact < ground->facts.count; ++fact)
        if (complement[fact] >= 0 && !state_has(*initial, fact))
            state_put(initial, complement[fact]);
    for (int i = 0; i < ground->action_count; ++i) {
        const GroundAction *action = &ground->actions[i];
        actions[i] = (GraphElement){i, -1, action->pre, action->add, action->del};
        for (int fact = 0; fact < ground->facts.count; ++fact) {
            if (state_has(action->neg, fact))
                state_put(&actions[i].pre, complement[fact]);
            if (complement[fact] >= 0) {
                if (state_has(action->del, fact))
                    state_put(&actions[i].add, complement[fact]);
                if (state_has(action->add, fact))
                    state_put(&actions[i].del, complement[fact]);
            }
        }
    }
    return count;
}
static char *heuristic_text(Value value) {
    return value == INFINITY_VALUE ? copy_text("inf") : format_text("%lld", value);
}
static char *heuristic_values(const Heuristic *heuristic) {
    TextLines items = {0};
    for (int i = 0; i < 5; ++i) {
        char *value = heuristic_text(heuristic_value(heuristic, heuristic_names[i]));
        lines_push(&items, format_text("%s=%s", heuristic_names[i], value));
        free(value);
    }
    char *out = join_texts(&items, " ");
    lines_free(&items);
    return out;
}
typedef struct {
    SearchSettings settings;
    char *tag;
    SearchResult result;
} RunRecord;
typedef struct {
    GroundProblem *ground;
    RunRecord runs[13];
    int run_count, proof, solved;
    GraphPlanResult graph;
    Value best;
    char *optimal;
} ProblemResult;
typedef struct {
    TextLines plans, graph, validation, comparison;
    int validated, valid_plans;
} Output;
typedef struct {
    const IntList *plan;
    const char *tag;
} SeenPlan;
static bool same_plan(const IntList *a, const IntList *b) {
    return a->count == b->count &&
           (!a->count || !memcmp(a->data, b->data, (size_t)a->count * sizeof *a->data));
}
static void plan_block(GroundProblem *ground, const char *tag, const IntList *plan, SeenPlan *seen,
                       int *seen_count, Output *output) {
    const char *earlier = NULL;
    for (int i = 0; i < *seen_count; ++i)
        if (same_plan(seen[i].plan, plan)) {
            earlier = seen[i].tag;
            break;
        }
    if (earlier)
        lines_push(&output->plans, format_text("plan: length=%d cost=%lld (same as %s)",
                                               plan->count, plan_cost(ground, plan), earlier));
    else {
        lines_push(&output->plans,
                   format_text("plan: length=%d cost=%lld", plan->count, plan_cost(ground, plan)));
        seen[(*seen_count)++] = (SeenPlan){plan, tag};
    }
    int counts[10] = {0};
    for (int i = 0; i < plan->count; ++i) {
        ++counts[ground->actions[plan->data[i]].schema];
        char *action = action_text(ground, plan->data[i]);
        lines_push(&output->plans, format_text("  %d %s", i + 1, action));
        free(action);
    }
    TextLines items = {0};
    for (int i = 0; i < ground->domain->action_count; ++i)
        if (counts[i])
            lines_push(&items, format_text("%s=%d", symbol_name(ground->domain->actions[i].name),
                                           counts[i]));
    lines_push(&output->plans, heading("schemas:", &items));
    lines_free(&items);
    Layers layers = parallelize(ground, plan);
    lines_push(&output->plans, format_text("parallel: layers=%d", layers.count));
    for (int i = 0; i < layers.count; ++i) {
        items = action_texts(ground, &layers.data[i]);
        char *name = format_text("  %d:", i + 1);
        lines_push(&output->plans, heading(name, &items));
        free(name);
        lines_free(&items);
    }
    IntList improved = improve(ground, plan);
    int removed = plan->count - improved.count;
    lines_push(&output->plans, format_text("improved: length=%d cost=%lld removed=%d",
                                           improved.count, plan_cost(ground, &improved), removed));
    if (removed)
        for (int i = 0; i < improved.count; ++i) {
            char *action = action_text(ground, improved.data[i]);
            lines_push(&output->plans, format_text("  %d %s", i + 1, action));
            free(action);
        }
    State landmarks = heuristics(ground, ground->initial)->landmarks, reached = {0},
          state = ground->initial;
    for (int i = 0; i < plan->count; ++i) {
        state = apply(&ground->actions[plan->data[i]], state);
        reached = state_union(reached, state_intersection(state, landmarks));
    }
    lines_push(&output->plans, format_text("landmarks reached: %d/%d", state_count(reached),
                                           state_count(landmarks)));
    for (int i = 0; i < ground->facts.count; ++i)
        if (state_has(landmarks, i) && !state_has(reached, i)) {
            char *atom = atom_text(ground->facts.data[i]);
            lines_push(&output->plans, format_text("  missed %s", atom));
            free(atom);
        }
    Validation original = validate_plan(ground, plan), better = validate_plan(ground, &improved);
    char *original_verdict = verdict(&original), *better_verdict = verdict(&better),
         *parallel = parallel_validation(ground, &layers);
    ++output->validated;
    if (!strcmp(original.status, "valid"))
        ++output->valid_plans;
    lines_push(&output->validation, format_text("%s: %s", tag, original_verdict));
    lines_push(&output->validation, format_text("  parallel: %s", parallel));
    lines_push(&output->validation, format_text("  improved: %s", better_verdict));
    free(original_verdict);
    free(better_verdict);
    free(parallel);
    lines_free(&original.messages);
    lines_free(&better.messages);
    int_free(&improved);
    layers_free(&layers);
}
static TextLines profile(GroundProblem *ground, const RunRecord *proof) {
    const IntList *plan = &proof->result.plan;
    TextLines out = {0};
    lines_push(&out, format_text("-- profile (%s) --", proof->tag));
    Value remaining = plan_cost(ground, plan);
    State state = ground->initial;
    int overestimates[5] = {0};
    for (int i = 0; i <= plan->count; ++i) {
        Heuristic *estimate = heuristics(ground, state);
        char *values = heuristic_values(estimate);
        lines_push(&out, format_text("  %d: h*=%lld %s", i, remaining, values));
        free(values);
        for (int j = 0; j < 5; ++j)
            if (heuristic_value(estimate, heuristic_names[j]) > remaining)
                ++overestimates[j];
        if (i < plan->count) {
            remaining -= ground->actions[plan->data[i]].cost;
            state = apply(&ground->actions[plan->data[i]], state);
        }
    }
    TextLines counts = {0};
    for (int i = 0; i < 5; ++i)
        lines_push(&counts, format_text("%s=%d", heuristic_names[i], overestimates[i]));
    char *joined = join_texts(&counts, " ");
    lines_push(&out, format_text("overestimates: %s", joined));
    free(joined);
    lines_free(&counts);
    lines_push(&out, format_text("-- causal links (%s) --", proof->tag));
    int supplier[100] = {0};
    for (int i = 0; i < plan->count; ++i) {
        const GroundAction *action = &ground->actions[plan->data[i]];
        TextLines items = {0};
        for (int fact = 0; fact < ground->facts.count; ++fact)
            if (state_has(action->pre, fact)) {
                char *atom = atom_text(ground->facts.data[fact]);
                lines_push(&items, format_text("%s<-%d", atom, supplier[fact]));
                free(atom);
            }
        char *notation = action_text(ground, plan->data[i]),
             *name = format_text("  %d %s:", i + 1, notation);
        lines_push(&out, heading(name, &items));
        free(notation);
        free(name);
        lines_free(&items);
        for (int fact = 0; fact < ground->facts.count; ++fact)
            if (state_has(action->add, fact))
                supplier[fact] = i + 1;
    }
    TextLines items = {0};
    for (int fact = 0; fact < ground->facts.count; ++fact)
        if (state_has(ground->goal, fact)) {
            char *atom = atom_text(ground->facts.data[fact]);
            lines_push(&items, format_text("%s<-%d", atom, supplier[fact]));
            free(atom);
        }
    lines_push(&out, heading("  goal:", &items));
    lines_free(&items);
    return out;
}
static char *result_line(const SearchResult *result) {
    if (!strcmp(result->status, "unreachable goal"))
        return copy_text("result: FAIL (unreachable goal)");
    if (!strcmp(result->status, "solved"))
        return format_text("result: solved expanded=%lld generated=%lld", result->expanded,
                           result->generated);
    return format_text("result: FAIL (%s) expanded=%lld generated=%lld", result->status,
                       result->expanded, result->generated);
}
static ProblemResult process_problem(GroundProblem *ground, const Settings *settings,
                                     Output *output) {
    ProblemResult out = {0};
    out.ground = ground;
    out.best = -1;
    out.proof = -1;
    out.optimal = copy_text("unknown");
    char *title = format_text("== problem %s ==", symbol_name(ground->problem->name));
    lines_add(&output->plans, title);
    lines_add(&output->graph, title);
    lines_push(&output->validation, title);
    bool unreachable = ground->unreachable.count != 0;
    if (unreachable)
        lines_add(&output->plans, "initial h: unreachable goal");
    else {
        Heuristic *estimate = heuristics(ground, ground->initial);
        char *values = heuristic_values(estimate);
        lines_push(&output->plans, format_text("initial h: %s", values));
        free(values);
        lines_push(&output->plans, format_text("landmarks: %d", state_count(estimate->landmarks)));
        for (int fact = 0; fact < ground->facts.count; ++fact)
            if (state_has(estimate->landmarks, fact)) {
                char *atom = atom_text(ground->facts.data[fact]);
                lines_push(&output->plans, format_text("  %s", atom));
                free(atom);
            }
        char *ff = heuristic_text(estimate->ff);
        lines_push(&output->plans,
                   format_text("relaxed plan: length=%d cost=%s", estimate->relaxed.count, ff));
        free(ff);
        for (int i = 0; i < estimate->relaxed.count; ++i) {
            char *action = action_text(ground, estimate->relaxed.data[i]);
            lines_push(&output->plans, format_text("  %s", action));
            free(action);
        }
        TextLines helpful = action_texts(ground, &estimate->helpful);
        lines_push(&output->plans, heading("helpful:", &helpful));
        lines_free(&helpful);
    }
    for (int i = 0; i < settings->run_count; ++i) {
        SearchSettings run = settings->runs[i];
        SearchResult result = {0};
        if (unreachable)
            result.status = "unreachable goal";
        else
            result = search(ground, ground->initial, run, settings->budget, settings->weight);
        char *tag = format_text("%s %s", run.algorithm, run.heuristic);
        if (out.proof < 0 && !strcmp(result.status, "solved") &&
            (!strcmp(tag, "ucs none") || !strcmp(tag, "astar hmax")))
            out.proof = out.run_count;
        out.runs[out.run_count++] = (RunRecord){run, tag, result};
    }
    if (unreachable) {
        out.graph.status = "unreachable goal";
        lines_add(&output->graph, "result: FAIL (unreachable goal)");
    } else {
        GraphElement actions[300];
        State initial;
        int count = transformed_graph(ground, actions, &initial);
        out.graph =
            graph_plan(actions, ground->action_count, initial, ground->goal, settings->level_limit);
        const GraphPlanResult *result = &out.graph;
        lines_push(&output->graph, format_text("complementary facts: %d", count));
        lines_append(&output->graph, &result->logs);
        if (!strcmp(result->status, "solved")) {
            lines_push(
                &output->graph,
                format_text(
                    "result: solved levels=%d length=%d cost=%lld searched=%lld memo_hits=%lld tried=%lld",
                    result->layers.count, result->plan.count, plan_cost(ground, &result->plan),
                    result->searched, result->memo_hits, result->tried));
            for (int i = 0; i < result->layers.count; ++i) {
                TextLines items = action_texts(ground, &result->layers.data[i]);
                char *name = format_text("layer %d:", i + 1);
                lines_push(&output->graph, heading(name, &items));
                free(name);
                lines_free(&items);
            }
        } else
            lines_push(&output->graph,
                       format_text("result: FAIL (%s) searched=%lld memo_hits=%lld tried=%lld",
                                   result->status, result->searched, result->memo_hits,
                                   result->tried));
    }
    out.runs[out.run_count++] =
        (RunRecord){{"graphplan", "none"},
                    copy_text("graphplan"),
                    (SearchResult){out.graph.status, int_copy(&out.graph.plan), out.graph.searched,
                                   out.graph.tried}};
    SeenPlan seen[13];
    int seen_count = 0;
    for (int i = 0; i < out.run_count; ++i) {
        const RunRecord *record = &out.runs[i];
        const SearchResult *result = &record->result;
        lines_push(&output->plans, format_text("-- %s --", record->tag));
        lines_push(&output->plans, result_line(result));
        char *length = copy_text("-"), *cost = copy_text("-");
        if (!strcmp(result->status, "solved")) {
            ++out.solved;
            Value value = plan_cost(ground, &result->plan);
            if (out.best < 0 || value < out.best)
                out.best = value;
            free(length);
            free(cost);
            length = format_text("%d", result->plan.count);
            cost = format_text("%lld", value);
            plan_block(ground, record->tag, &result->plan, seen, &seen_count, output);
        }
        lines_push(&output->comparison,
                   format_text("%s,%s,%s,%s,%s,%lld,%lld", symbol_name(ground->problem->name),
                               record->settings.algorithm, record->settings.heuristic, length, cost,
                               result->expanded, result->generated));
        free(length);
        free(cost);
    }
    if (out.proof >= 0) {
        free(out.optimal);
        out.optimal = format_text("%lld", plan_cost(ground, &out.runs[out.proof].result.plan));
        TextLines details = profile(ground, &out.runs[out.proof]);
        append_owned(&output->plans, &details);
    } else
        for (int i = 0; i < out.run_count; ++i) {
            const char *status = out.runs[i].result.status;
            if (!strcmp(status, "unreachable goal") || !strcmp(status, "dead end") ||
                !strcmp(status, "exhausted") || !strcmp(status, "unreachable")) {
                free(out.optimal);
                out.optimal = copy_text("none");
                break;
            }
        }
    lines_add(&output->plans, "");
    lines_add(&output->graph, "");
    lines_add(&output->validation, "");
    return out;
}
static char *best_text(Value value) {
    return value < 0 ? copy_text("-") : format_text("%lld", value);
}
static int candidate_lines(const Domain *domain, const CandidatePlan *candidates, int count,
                           ProblemResult *problems, int problem_count, const Settings *settings,
                           TextLines *out) {
    lines_add(out, "== candidates ==");
    int valid = 0;
    for (int i = 0; i < count; ++i) {
        const CandidatePlan *candidate = &candidates[i];
        ProblemResult *problem = NULL;
        for (int j = 0; j < problem_count; ++j)
            if (problems[j].ground->problem->name == candidate->problem) {
                problem = &problems[j];
                break;
            }
        GroundProblem *ground = problem->ground;
        Validation validation = validate_steps(domain, ground->problem, &candidate->steps);
        char *prefix = format_text("candidate %d %s %s: ", i + 1, symbol_name(candidate->problem),
                                   symbol_name(candidate->label));
        if (!strcmp(validation.status, "valid")) {
            ++valid;
            IntList plan = map_steps(ground, &candidate->steps, candidate->steps.count),
                    improved = improve(ground, &plan);
            char *result = verdict(&validation), *best = best_text(problem->best);
            lines_push(out, format_text("%s%s", prefix, result));
            lines_push(out, format_text("  improved: length=%d cost=%lld removed=%d best known=%s",
                                        improved.count, plan_cost(ground, &improved),
                                        candidate->steps.count - improved.count, best));
            free(prefix);
            free(result);
            free(best);
            int_free(&plan);
            int_free(&improved);
            lines_free(&validation.messages);
            continue;
        }
        lines_push(out, format_text("%s%s", prefix, validation.status));
        free(prefix);
        for (int j = 0; j < validation.messages.count; ++j)
            lines_push(out, format_text("  %s", validation.messages.data[j]));
        int correct = validation.correct;
        lines_free(&validation.messages);
        if (ground->unreachable.count) {
            lines_add(out, "  repair: FAIL (unreachable goal)");
            continue;
        }
        IntList plan = map_steps(ground, &candidate->steps, correct);
        State state = ground->initial;
        for (int j = 0; j < plan.count; ++j)
            state = apply(&ground->actions[plan.data[j]], state);
        SearchResult repair =
            search(ground, state, settings->repair, settings->budget, settings->weight);
        if (strcmp(repair.status, "solved")) {
            lines_push(out, format_text("  repair: FAIL (%s)", repair.status));
            int_free(&plan);
            int_free(&repair.plan);
            continue;
        }
        for (int j = 0; j < repair.plan.count; ++j)
            int_push(&plan, repair.plan.data[j]);
        Validation repaired = validate_plan(ground, &plan);
        char *result = verdict(&repaired);
        lines_push(
            out, format_text("  repair: kept=%d added=%d %s", correct, repair.plan.count, result));
        free(result);
        for (int j = 0; j < plan.count; ++j) {
            char *action = action_text(ground, plan.data[j]);
            lines_push(out, format_text("    %d %s", j + 1, action));
            free(action);
        }
        lines_free(&repaired.messages);
        int_free(&plan);
        int_free(&repair.plan);
    }
    return valid;
}
static void write_lines(const char *name, const TextLines *lines) {
    char *path = format_text("output/%s", name);
    FILE *output = fopen(path, "wb");
    free(path);
    if (!output)
        exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i) {
        if (fputs(lines->data[i], output) == EOF || fputc('\n', output) == EOF)
            exit(EXIT_FAILURE);
    }
    if (fclose(output))
        exit(EXIT_FAILURE);
}
int main(void) {
    Domain domain = read_domain();
    validate_domain(&domain);
    int problem_count, candidate_count;
    Problem *raw = read_problems(&problem_count);
    Settings settings = read_settings();
    CandidatePlan *candidates = read_candidates(&candidate_count);
    TextLines grounding = domain_lines(&domain);
    Output output = {0};
    lines_add(&output.comparison, "problem,algorithm,heuristic,length,cost,expanded,generated");
    GroundProblem *grounds = allocate((size_t)problem_count * sizeof *grounds);
    ProblemResult *problems = allocate((size_t)problem_count * sizeof *problems);
    for (int i = 0; i < problem_count; ++i) {
        validate_problem(&domain, &raw[i]);
        grounds[i] = ground(&domain, &raw[i]);
        lines_add(&grounding, "");
        TextLines details = grounding_lines(&grounds[i]);
        append_owned(&grounding, &details);
        problems[i] = process_problem(&grounds[i], &settings, &output);
    }
    lines_add(&output.plans, "== summary ==");
    for (int i = 0; i < problem_count; ++i) {
        char *best = best_text(problems[i].best);
        lines_push(&output.plans, format_text("%s: solved=%d/%d best=%s optimal=%s",
                                              symbol_name(raw[i].name), problems[i].solved,
                                              problems[i].run_count, best, problems[i].optimal));
        free(best);
    }
    for (int i = 0; i < problems[0].run_count; ++i) {
        int solved = 0, best = 0;
        Value expanded = 0, generated = 0;
        for (int j = 0; j < problem_count; ++j) {
            const SearchResult *result = &problems[j].runs[i].result;
            expanded += result->expanded;
            generated += result->generated;
            if (!strcmp(result->status, "solved")) {
                ++solved;
                if (plan_cost(problems[j].ground, &result->plan) == problems[j].best)
                    ++best;
            }
        }
        lines_push(&output.plans,
                   format_text("%s: solved=%d best=%d expanded=%lld generated=%lld",
                               problems[0].runs[i].tag, solved, best, expanded, generated));
    }
    int valid_candidates = candidate_lines(&domain, candidates, candidate_count, problems,
                                           problem_count, &settings, &output.validation);
    lines_add(&output.validation, "");
    lines_add(&output.validation, "== summary ==");
    lines_push(&output.validation,
               format_text("plans: %d valid: %d", output.validated, output.valid_plans));
    lines_push(&output.validation,
               format_text("candidates: %d valid: %d", candidate_count, valid_candidates));
    mkdir("output", 0755);
    write_lines("grounding.txt", &grounding);
    write_lines("plans.txt", &output.plans);
    write_lines("graphplan.txt", &output.graph);
    write_lines("validation.txt", &output.validation);
    write_lines("comparison.csv", &output.comparison);
    for (int i = 0; i < candidate_count; ++i) {
        for (int j = 0; j < candidates[i].steps.count; ++j)
            int_free(&candidates[i].steps.data[j].arguments);
        free(candidates[i].steps.data);
    }
    free(candidates);
    for (int i = 0; i < problem_count; ++i) {
        for (int j = 0; j < problems[i].run_count; ++j) {
            free(problems[i].runs[j].tag);
            int_free(&problems[i].runs[j].result.plan);
        }
        graph_result_free(&problems[i].graph);
        free(problems[i].optimal);
        ground_free(&grounds[i]);
        problem_free(&raw[i]);
    }
    free(problems);
    free(grounds);
    free(raw);
    domain_free(&domain);
    lines_free(&grounding);
    lines_free(&output.plans);
    lines_free(&output.graph);
    lines_free(&output.validation);
    lines_free(&output.comparison);
    symbols_destroy();
    return 0;
}
