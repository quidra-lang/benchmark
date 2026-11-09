#include "planner.h"
bool state_has(State state, int fact) {
    return (state.words[fact / 64] & (UINT64_C(1) << (fact % 64))) != 0;
}
void state_put(State *state, int fact) { state->words[fact / 64] |= UINT64_C(1) << (fact % 64); }
State state_union(State a, State b) {
    for (int i = 0; i < 4; ++i)
        a.words[i] |= b.words[i];
    return a;
}
State state_without(State a, State b) {
    for (int i = 0; i < 4; ++i)
        a.words[i] &= ~b.words[i];
    return a;
}
State state_intersection(State a, State b) {
    for (int i = 0; i < 4; ++i)
        a.words[i] &= b.words[i];
    return a;
}
bool state_contains(State a, State b) {
    for (int i = 0; i < 4; ++i)
        if ((a.words[i] & b.words[i]) != b.words[i])
            return false;
    return true;
}
bool state_intersects(State a, State b) {
    for (int i = 0; i < 4; ++i)
        if (a.words[i] & b.words[i])
            return true;
    return false;
}
bool state_equal(State a, State b) {
    for (int i = 0; i < 4; ++i)
        if (a.words[i] != b.words[i])
            return false;
    return true;
}
IntList state_numbers(State state) {
    IntList out = {0};
    for (int i = 0; i < 256; ++i)
        if (state_has(state, i))
            int_push(&out, i);
    return out;
}
int state_count(State state) {
    int count = 0;
    for (int i = 0; i < 4; ++i) {
        uint64_t word = state.words[i];
        while (word) {
            word &= word - 1;
            ++count;
        }
    }
    return count;
}
uint64_t state_hash(State state) {
    uint64_t hash = UINT64_C(1469598103934665603);
    for (int i = 0; i < 4; ++i) {
        hash ^= state.words[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}
static void state_table_rehash(StateTable *table, int size) {
    free(table->slots);
    table->slots = allocate((size_t)size * sizeof *table->slots);
    table->slot_count = size;
    for (int i = 0; i < table->count; ++i) {
        int slot = (int)(state_hash(table->data[i].state) & (uint64_t)(size - 1));
        while (table->slots[slot])
            slot = (slot + 1) & (size - 1);
        table->slots[slot] = i + 1;
    }
}
bool state_table_get(const StateTable *table, State state, Value *value) {
    if (!table->slot_count)
        return false;
    int slot = (int)(state_hash(state) & (uint64_t)(table->slot_count - 1));
    while (table->slots[slot]) {
        int index = table->slots[slot] - 1;
        if (state_equal(table->data[index].state, state)) {
            if (value)
                *value = table->data[index].value;
            return true;
        }
        slot = (slot + 1) & (table->slot_count - 1);
    }
    return false;
}
void state_table_set(StateTable *table, State state, Value value) {
    if (!table->slot_count || (table->count + 1) * 10 > table->slot_count * 7)
        state_table_rehash(table, table->slot_count ? table->slot_count * 2 : 128);
    int slot = (int)(state_hash(state) & (uint64_t)(table->slot_count - 1));
    while (table->slots[slot]) {
        int index = table->slots[slot] - 1;
        if (state_equal(table->data[index].state, state)) {
            table->data[index].value = value;
            return;
        }
        slot = (slot + 1) & (table->slot_count - 1);
    }
    if (table->count == table->capacity) {
        table->capacity = table->capacity ? table->capacity * 2 : 64;
        table->data = resize(table->data, (size_t)table->capacity * sizeof *table->data);
    }
    table->slots[slot] = table->count + 1;
    table->data[table->count++] = (StateEntry){state, value};
}
void state_table_free(StateTable *table) {
    free(table->data);
    free(table->slots);
    *table = (StateTable){0};
}
int typed_find(const TypedList *types, int name) {
    for (int i = 0; i < types->count; ++i)
        if (types->data[i].name == name)
            return types->data[i].type;
    return -1;
}
int predicate_index(const Domain *domain, int name) {
    for (int i = 0; i < domain->predicate_count; ++i)
        if (domain->predicates[i].name == name)
            return i;
    return -1;
}
bool subtype(const Domain *domain, int type, int expected) {
    int object = symbol("object");
    while (type != expected) {
        if (type == object)
            return false;
        type = typed_find(&domain->parents, type);
    }
    return true;
}
void classify(Domain *domain) {
    memset(domain->fluent, 0, sizeof domain->fluent);
    for (int i = 0; i < domain->action_count; ++i)
        for (int j = 0; j < domain->actions[i].effects.count; ++j)
            domain->fluent[predicate_index(
                domain, get_atom(domain->actions[i].effects.data[j].atom)->predicate)] = true;
}
int substitute_atom(int id, const TypedList *assignment) {
    Atom atom = *get_atom(id);
    IntList terms = {0};
    for (int i = 0; i < atom.terms.count; ++i)
        int_push(&terms, typed_find(assignment, atom.terms.data[i]));
    int result = intern_atom(atom.predicate, &terms);
    int_free(&terms);
    return result;
}
IntList objects_of_type(const Domain *domain, const Problem *problem, int type) {
    IntList out = {0};
    for (int i = 0; i < problem->objects.count; ++i)
        if (subtype(domain, problem->objects.data[i].type, type))
            int_push(&out, problem->objects.data[i].name);
    return out;
}
typedef struct {
    int schema;
    IntList arguments, pre, neg, add, del;
    bool reachable;
} Candidate;
typedef struct {
    const Domain *domain;
    const Problem *problem;
    GroundProblem *ground;
    Candidate *candidates;
    int count, capacity;
    IntList *choices, arguments;
    TypedList assignment;
    int schema;
} Grounding;
static void candidate_free(Candidate *candidate) {
    int_free(&candidate->arguments);
    int_free(&candidate->pre);
    int_free(&candidate->neg);
    int_free(&candidate->add);
    int_free(&candidate->del);
}
static void enumerate(Grounding *work, int at) {
    const Schema *schema = &work->domain->actions[work->schema];
    if (at < schema->parameters.count) {
        for (int i = 0; i < work->choices[at].count; ++i) {
            int object = work->choices[at].data[i];
            work->arguments.data[at] = object;
            work->assignment.data[at].type = object;
            enumerate(work, at + 1);
        }
        return;
    }
    Candidate candidate = {0};
    candidate.schema = work->schema;
    candidate.arguments = int_copy(&work->arguments);
    for (int i = 0; i < schema->conditions.count; ++i) {
        Literal literal = schema->conditions.data[i];
        int id = substitute_atom(literal.atom, &work->assignment);
        const Atom *atom = get_atom(id);
        int predicate = predicate_index(work->domain, atom->predicate);
        if (!strcmp(symbol_name(atom->predicate), "=") || !work->domain->fluent[predicate]) {
            bool truth = !strcmp(symbol_name(atom->predicate), "=")
                             ? atom->terms.data[0] == atom->terms.data[1]
                             : int_has(&work->problem->initial, id);
            if (truth == literal.negative) {
                candidate_free(&candidate);
                return;
            }
        } else
            int_add(literal.negative ? &candidate.neg : &candidate.pre, id);
    }
    for (int i = 0; i < schema->effects.count; ++i) {
        Literal literal = schema->effects.data[i];
        int_add(literal.negative ? &candidate.del : &candidate.add,
                substitute_atom(literal.atom, &work->assignment));
    }
    int kept = 0;
    for (int i = 0; i < candidate.del.count; ++i)
        if (!int_has(&candidate.add, candidate.del.data[i]))
            candidate.del.data[kept++] = candidate.del.data[i];
    candidate.del.count = kept;
    if (work->count == work->capacity) {
        work->capacity = work->capacity ? work->capacity * 2 : 128;
        work->candidates =
            resize(work->candidates, (size_t)work->capacity * sizeof *work->candidates);
    }
    work->candidates[work->count++] = candidate;
    ++work->ground->counts[work->schema].candidates;
}
static bool contains_atoms(const IntList *set, const IntList *required) {
    for (int i = 0; i < required->count; ++i)
        if (!int_has(set, required->data[i]))
            return false;
    return true;
}
static State to_state(const GroundProblem *ground, const IntList *atoms) {
    State out = {0};
    for (int i = 0; i < ground->facts.count; ++i)
        if (int_has(atoms, ground->facts.data[i]))
            state_put(&out, i);
    return out;
}
static int object_number(const Problem *problem, int name) {
    for (int i = 0; i < problem->objects.count; ++i)
        if (problem->objects.data[i].name == name)
            return i;
    return -1;
}
static bool fact_before(const Domain *domain, const Problem *problem, int left, int right) {
    const Atom *a = get_atom(left), *b = get_atom(right);
    int ap = predicate_index(domain, a->predicate), bp = predicate_index(domain, b->predicate);
    if (ap != bp)
        return ap < bp;
    for (int i = 0; i < a->terms.count; ++i) {
        int av = object_number(problem, a->terms.data[i]),
            bv = object_number(problem, b->terms.data[i]);
        if (av != bv)
            return av < bv;
    }
    return false;
}
GroundProblem ground(const Domain *domain, const Problem *problem) {
    GroundProblem out = {0};
    out.domain = domain;
    out.problem = problem;
    IntList reachable = {0};
    for (int i = 0; i < problem->initial.count; ++i) {
        int id = problem->initial.data[i];
        if (domain->fluent[predicate_index(domain, get_atom(id)->predicate)])
            int_add(&reachable, id);
        else
            ++out.static_facts;
    }
    Grounding work = {0};
    work.domain = domain;
    work.problem = problem;
    work.ground = &out;
    for (int i = 0; i < domain->action_count; ++i) {
        work.schema = i;
        const Schema *schema = &domain->actions[i];
        out.counts[i].assignments = 1;
        work.choices = allocate((size_t)schema->parameters.count * sizeof *work.choices);
        work.assignment = (TypedList){0};
        work.assignment.count = work.assignment.capacity = schema->parameters.count;
        work.assignment.data =
            allocate((size_t)work.assignment.count * sizeof *work.assignment.data);
        work.arguments = (IntList){0};
        for (int j = 0; j < schema->parameters.count; ++j) {
            work.choices[j] = objects_of_type(domain, problem, schema->parameters.data[j].type);
            out.counts[i].assignments *= work.choices[j].count;
            work.assignment.data[j] = (Typed){schema->parameters.data[j].name, 0};
            int_push(&work.arguments, 0);
        }
        enumerate(&work, 0);
        for (int j = 0; j < schema->parameters.count; ++j)
            int_free(&work.choices[j]);
        free(work.choices);
        free(work.assignment.data);
        int_free(&work.arguments);
    }
    out.candidate_count = work.count;
    for (;;) {
        bool changed = false;
        for (int i = 0; i < work.count; ++i) {
            Candidate *candidate = &work.candidates[i];
            if (!candidate->reachable && contains_atoms(&reachable, &candidate->pre)) {
                candidate->reachable = true;
                changed = true;
                for (int j = 0; j < candidate->add.count; ++j)
                    int_add(&reachable, candidate->add.data[j]);
            }
        }
        if (!changed)
            break;
    }
    out.facts = reachable;
    for (int i = 1; i < out.facts.count; ++i) {
        int value = out.facts.data[i], j = i;
        while (j && fact_before(domain, problem, value, out.facts.data[j - 1])) {
            out.facts.data[j] = out.facts.data[j - 1];
            --j;
        }
        out.facts.data[j] = value;
    }
    out.initial = to_state(&out, &problem->initial);
    for (int i = 0; i < work.count; ++i) {
        Candidate *candidate = &work.candidates[i];
        if (candidate->reachable) {
            GroundAction *action = &out.actions[out.action_count++];
            *action = (GroundAction){candidate->schema,
                                     candidate->arguments,
                                     domain->actions[candidate->schema].cost,
                                     to_state(&out, &candidate->pre),
                                     to_state(&out, &candidate->neg),
                                     to_state(&out, &candidate->add),
                                     to_state(&out, &candidate->del)};
            candidate->arguments = (IntList){0};
            ++out.counts[candidate->schema].reachable;
        }
        candidate_free(candidate);
    }
    free(work.candidates);
    for (int i = 0; i < problem->goals.count; ++i) {
        int id = problem->goals.data[i], fact = -1;
        for (int j = 0; j < out.facts.count; ++j)
            if (out.facts.data[j] == id) {
                fact = j;
                break;
            }
        if (fact >= 0)
            state_put(&out.goal, fact);
        else if (domain->fluent[predicate_index(domain, get_atom(id)->predicate)] ||
                 !int_has(&problem->initial, id))
            int_push(&out.unreachable, id);
    }
    return out;
}
void ground_free(GroundProblem *ground) {
    int_free(&ground->facts);
    int_free(&ground->unreachable);
    for (int i = 0; i < ground->action_count; ++i)
        int_free(&ground->actions[i].arguments);
    for (int i = 0; i < ground->cache_count; ++i) {
        Heuristic *heuristic = ground->cache[i].heuristic;
        int_free(&heuristic->relaxed);
        int_free(&heuristic->helpful);
        free(heuristic);
    }
    free(ground->cache);
    free(ground->cache_slots);
}
