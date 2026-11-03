#include "policy.h"
struct MemoryBlock {
    MemoryBlock *next;
    size_t used, capacity;
    max_align_t alignment;
    unsigned char data[];
};
Memory permanent = {0};
Memory *memory = &permanent;
void *allocate(size_t size) {
    size_t alignment = _Alignof(max_align_t);
    size = (size + alignment - 1) / alignment * alignment;
    if (!memory->head || memory->head->capacity - memory->head->used < size) {
        size_t capacity = size > 65536 ? size : 65536;
        MemoryBlock *block = malloc(sizeof(*block) + capacity);
        if (!block)
            exit(1);
        block->next = memory->head;
        block->used = 0;
        block->capacity = capacity;
        memory->head = block;
    }
    void *result = memory->head->data + memory->head->used;
    memory->head->used += size;
    memset(result, 0, size);
    return result;
}
void clear_memory(Memory *pool) {
    while (pool->head) {
        MemoryBlock *next = pool->head->next;
        free(pool->head);
        pool->head = next;
    }
}
char *substring(const char *source, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, source, length);
    return result;
}
char *copy_text(const char *source) { return substring(source, strlen(source)); }
char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern);
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}
Names split(const char *source, const char *separator) {
    Names out = {0};
    size_t length = strlen(separator);
    const char *start = source;
    for (;;) {
        const char *end = strstr(start, separator);
        Names_add(&out, end ? substring(start, (size_t)(end - start)) : copy_text(start));
        if (!end)
            return out;
        start = end + length;
    }
}
char *join(Names values, const char *separator) {
    size_t length = 1;
    for (size_t i = 0; i < values.count; ++i)
        length += strlen(values.items[i]) + (i ? strlen(separator) : 0);
    char *out = allocate(length), *at = out;
    for (size_t i = 0; i < values.count; ++i) {
        if (i) {
            size_t n = strlen(separator);
            memcpy(at, separator, n);
            at += n;
        }
        size_t n = strlen(values.items[i]);
        memcpy(at, values.items[i], n);
        at += n;
    }
    return out;
}
char *trim(const char *source) {
    while (*source == ' ')
        ++source;
    size_t length = strlen(source);
    while (length && source[length - 1] == ' ')
        --length;
    return substring(source, length);
}
Names read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(1);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *source = allocate((size_t)length + 1);
    fread(source, 1, (size_t)length, file);
    fclose(file);
    Names lines = split(source, "\n");
    if (length && source[length - 1] == '\n')
        --lines.count;
    return lines;
}
Value number_value(int n) { return (Value){.kind = V_INTEGER, .integer = n}; }
Value word_value(char *s) { return (Value){.kind = V_STRING, .string = s}; }
Value bool_value(bool b) { return (Value){.kind = V_BOOLEAN, .boolean = b}; }
Value bag_value(Names a) { return (Value){.kind = V_BAG, .bag = a}; }
Value error_value(char *s) { return (Value){.kind = V_ERROR, .string = s}; }
Value *attribute(Attributes values, const char *name) {
    for (size_t i = 0; i < values.count; ++i)
        if (!strcmp(values.items[i].name, name))
            return &values.items[i].value;
    return NULL;
}
void set_attribute(Attributes *values, char *name, Value value) {
    Value *old = attribute(*values, name);
    if (old)
        *old = value;
    else
        Attributes_add(values, (Attribute){name, value});
}
static Value input_value(char *source) {
    if (!strcmp(source, "true") || !strcmp(source, "false"))
        return bool_value(!strcmp(source, "true"));
    if (*source == '[')
        return bag_value(!strcmp(source, "[]")
                             ? (Names){0}
                             : split(substring(source + 1, strlen(source) - 2), ","));
    if (*source == '-' || (*source >= '0' && *source <= '9'))
        return number_value(atoi(source));
    return word_value(source);
}
static Attributes attributes(Names fields, size_t start) {
    Attributes result = {0};
    for (size_t i = start; i < fields.count; ++i) {
        char *equal = strchr(fields.items[i], '=');
        set_attribute(&result, substring(fields.items[i], (size_t)(equal - fields.items[i])),
                      input_value(equal + 1));
    }
    return result;
}
static char *value_notation(Value value) {
    if (value.kind == V_INTEGER)
        return format("%d", value.integer);
    if (value.kind == V_STRING)
        return format("\"%s\"", value.string);
    if (value.kind == V_BOOLEAN)
        return value.boolean ? "true" : "false";
    Names items = {0};
    for (size_t i = 0; i < value.bag.count; ++i)
        Names_add(&items, format("\"%s\"", value.bag.items[i]));
    return format("[%s]", join(items, ","));
}
static Value boolean_result(Values values, bool veto, const char *name) {
    bool found = false;
    char *error = NULL;
    for (size_t i = 0; i < values.count; ++i) {
        Value v = values.items[i];
        if (v.kind == V_BOOLEAN)
            found |= v.boolean == veto;
        else if (!error)
            error = v.kind == V_ERROR ? v.string : format("type %s", name);
    }
    if (found)
        return bool_value(veto);
    if (error)
        return error_value(error);
    return bool_value(!veto);
}
static Value operation(const char *name, Values values) {
    for (size_t i = 0; i < values.count; ++i)
        if (values.items[i].kind == V_ERROR)
            return values.items[i];
    Value a = values.items[0], b = values.items[values.count > 1 ? 1 : 0];
    bool integers = a.kind == V_INTEGER && b.kind == V_INTEGER;
    if (integers) {
        if (!strcmp(name, "+"))
            return number_value(a.integer + b.integer);
        if (!strcmp(name, "-"))
            return number_value(values.count == 1 ? -a.integer : a.integer - b.integer);
        if (!strcmp(name, "*"))
            return number_value(a.integer * b.integer);
        if (!strcmp(name, "<"))
            return bool_value(a.integer < b.integer);
        if (!strcmp(name, "<="))
            return bool_value(a.integer <= b.integer);
        if (!strcmp(name, ">"))
            return bool_value(a.integer > b.integer);
        if (!strcmp(name, ">="))
            return bool_value(a.integer >= b.integer);
    }
    if ((!strcmp(name, "==") || !strcmp(name, "!=")) && a.kind == b.kind &&
        (integers || a.kind == V_STRING || a.kind == V_BOOLEAN)) {
        bool equal = integers             ? a.integer == b.integer
                     : a.kind == V_STRING ? !strcmp(a.string, b.string)
                                          : a.boolean == b.boolean;
        return bool_value(!strcmp(name, "==") ? equal : !equal);
    }
    if (!strcmp(name, "in") && a.kind == V_STRING && b.kind == V_BAG) {
        for (size_t i = 0; i < b.bag.count; ++i)
            if (!strcmp(a.string, b.bag.items[i]))
                return bool_value(true);
        return bool_value(false);
    }
    if (!strcmp(name, "not") && a.kind == V_BOOLEAN)
        return bool_value(!a.boolean);
    if ((!strcmp(name, "starts_with") || !strcmp(name, "^=")) && a.kind == V_STRING &&
        b.kind == V_STRING)
        return bool_value(!strncmp(a.string, b.string, strlen(b.string)));
    if (!strcmp(name, "size") && a.kind == V_BAG)
        return number_value((int)a.bag.count);
    return error_value(format("type %s", name));
}
static Value expression(Expression *tree, Attributes values, char *current) {
    char *name = tree->operation;
    Expressions arguments = tree->arguments;
    if (!strcmp(name, "literal"))
        return tree->literal;
    if (!strcmp(name, "attribute")) {
        Value *value = attribute(values, tree->literal.string);
        return value ? *value : error_value(format("missing %s", tree->literal.string));
    }
    if (!strcmp(name, "it"))
        return word_value(current);
    if (!strcmp(name, "present"))
        return bool_value(attribute(values, arguments.items[0]->literal.string) != NULL);
    if (!strcmp(name, "any_of") || !strcmp(name, "all_of")) {
        Value bag = expression(arguments.items[0], values, current);
        if (bag.kind == V_ERROR)
            return bag;
        if (bag.kind != V_BAG)
            return error_value(format("type %s", name));
        Values checked = {0};
        for (size_t i = 0; i < bag.bag.count; ++i)
            Values_add(&checked, expression(arguments.items[1], values, bag.bag.items[i]));
        return boolean_result(checked, !strcmp(name, "any_of"), name);
    }
    Values operands = {0};
    for (size_t i = 0; i < arguments.count; ++i)
        Values_add(&operands, expression(arguments.items[i], values, current));
    if (!strcmp(name, "and") || !strcmp(name, "or"))
        return boolean_result(operands, !strcmp(name, "or"), name);
    return operation(name, operands);
}
typedef struct {
    TargetResult *items;
    size_t count;
} TargetResults;
static TargetResult target_group(TargetResults values, bool conjunction) {
    bool all = true;
    for (size_t i = 0; i < values.count; ++i) {
        TargetKind kind = values.items[i].kind;
        if (conjunction && kind == T_NO_MATCH)
            return (TargetResult){T_NO_MATCH, NULL};
        if (!conjunction && kind == T_MATCH)
            return (TargetResult){T_MATCH, NULL};
        all &= kind == T_MATCH;
    }
    if (conjunction && all)
        return (TargetResult){T_MATCH, NULL};
    for (size_t i = 0; i < values.count; ++i)
        if (values.items[i].kind == T_INDETERMINATE)
            return values.items[i];
    return (TargetResult){T_NO_MATCH, NULL};
}
static TargetResult match_clause(Clause clause, Attributes values) {
    Value *source = attribute(values, clause.reference);
    if (!source)
        return clause.mandatory
                   ? (TargetResult){T_INDETERMINATE, format("missing %s", clause.reference)}
                   : (TargetResult){T_NO_MATCH, NULL};
    Values items = {0};
    if (source->kind == V_BAG) {
        for (size_t i = 0; i < source->bag.count; ++i)
            Values_add(&items, word_value(source->bag.items[i]));
    } else
        Values_add(&items, *source);
    Value literal = expression(clause.literal, values, "");
    char *error = NULL;
    bool matches = false;
    for (size_t i = 0; i < items.count; ++i) {
        Value operands[2] = {items.items[i], literal};
        Value result = operation(clause.operation, (Values){operands, 2, 2});
        if (result.kind == V_BOOLEAN && result.boolean)
            matches = true;
        else if (result.kind == V_ERROR && !error)
            error = result.string;
    }
    if (matches)
        return (TargetResult){T_MATCH, NULL};
    if (error)
        return (TargetResult){T_INDETERMINATE, error};
    return (TargetResult){T_NO_MATCH, NULL};
}
TargetResult evaluate_target(Evaluator *evaluator, Element *element) {
    TargetResults lines = {.count = element->targets.count};
    lines.items = allocate(lines.count * sizeof(TargetResult));
    for (size_t i = 0; i < lines.count; ++i) {
        TargetLine line = element->targets.items[i];
        TargetResults alternatives = {.count = line.count};
        alternatives.items = allocate(alternatives.count * sizeof(TargetResult));
        for (size_t j = 0; j < line.count; ++j) {
            Alternative alternative = line.items[j];
            TargetResults clauses = {.count = alternative.count};
            clauses.items = allocate(clauses.count * sizeof(TargetResult));
            for (size_t k = 0; k < clauses.count; ++k)
                clauses.items[k] = match_clause(alternative.items[k], evaluator->values);
            alternatives.items[j] = target_group(clauses, true);
        }
        lines.items[i] = target_group(alternatives, false);
    }
    return target_group(lines, true);
}
static void attachments(Evaluator *evaluator, Evaluation *result) {
    for (size_t i = 0; i < result->children.count; ++i) {
        ChildState state = result->children.items[i];
        if (state.kind != C_EVALUATED || state.evaluation->decision != result->decision)
            continue;
        Evaluation *supporter = state.evaluation;
        for (size_t j = 0; j < supporter->obligations.count; ++j)
            Items_add(&result->obligations, supporter->obligations.items[j]);
        for (size_t j = 0; j < supporter->advice.count; ++j)
            Items_add(&result->advice, supporter->advice.items[j]);
    }
    char *effect = decision_name(result->decision);
    for (int obligatory = 1; obligatory >= 0; --obligatory) {
        Attachments definitions =
            obligatory ? result->element->obligations : result->element->advice;
        for (size_t i = 0; i < definitions.count; ++i) {
            Attachment definition = definitions.items[i];
            if (strcmp(definition.effect, effect))
                continue;
            char *error = NULL;
            Names parts = {0};
            Names_add(&parts, definition.identifier);
            for (size_t j = 0; j < definition.arguments.count; ++j) {
                Argument argument = definition.arguments.items[j];
                Value value = expression(argument.expression, evaluator->values, "");
                if (value.kind == V_ERROR) {
                    if (!error)
                        error = value.string;
                } else
                    Names_add(&parts, format("%s=%s", argument.name, value_notation(value)));
            }
            if (error) {
                if (obligatory) {
                    result->decision = !strcmp(effect, "DENY") ? D_ID : D_IP;
                    result->reason = format("obligation %s: %s", definition.identifier, error);
                    result->decisive = NULL;
                    result->obligations.count = result->advice.count = 0;
                    return;
                }
                continue;
            }
            Items_add(obligatory ? &result->obligations : &result->advice,
                      (Item){definition.identifier, join(parts, " ")});
        }
    }
}
static Evaluation *rule(Evaluator *evaluator, Element *element, bool with_obligations) {
    Evaluation *result = allocate(sizeof(*result));
    result->element = element;
    result->target = evaluate_target(evaluator, element);
    result->decision = D_NA;
    Decision error = !strcmp(element->behavior, "DENY") ? D_ID : D_IP;
    if (result->target.kind == T_INDETERMINATE) {
        result->decision = error;
        result->reason = result->target.reason;
    } else if (result->target.kind == T_MATCH) {
        result->condition = element->condition
                                ? expression(element->condition, evaluator->values, "")
                                : bool_value(true);
        if (result->condition.kind != V_BOOLEAN && result->condition.kind != V_ERROR)
            result->condition = error_value("type condition");
        if (result->condition.kind == V_ERROR) {
            result->decision = error;
            result->reason = result->condition.string;
        } else if (result->condition.boolean) {
            result->decision = !strcmp(element->behavior, "DENY") ? D_DENY : D_PERMIT;
            result->decisive = element;
            if (with_obligations)
                attachments(evaluator, result);
        }
    }
    if (evaluator->coverage)
        evaluator->coverage[element->index] = result->decision == D_PERMIT ? 'P'
                                              : result->decision == D_DENY ? 'D'
                                              : result->decision == D_NA   ? '-'
                                                                           : 'I';
    return result;
}
Evaluation *evaluate(Evaluator *evaluator, Element *element) {
    if (!strcmp(element->kind, "rule"))
        return rule(evaluator, element, true);
    Evaluation *result = allocate(sizeof(*result));
    result->element = element;
    result->target = evaluate_target(evaluator, element);
    result->decision = D_NA;
    if (result->target.kind == T_NO_MATCH)
        return result;
    Combined combined = combine(evaluator, element);
    result->decision = combined.decision;
    result->reason = combined.reason;
    result->children = combined.children;
    if (result->target.kind == T_INDETERMINATE) {
        if (definite(result->decision))
            result->decision = result->decision == D_PERMIT ? D_IP : D_ID;
        if (indeterminate(result->decision))
            result->reason = result->target.reason;
    }
    if (definite(result->decision)) {
        result->decisive = element;
        for (size_t i = 0; i < result->children.count; ++i) {
            ChildState state = result->children.items[i];
            if (state.kind == C_EVALUATED && state.evaluation->decision == result->decision) {
                result->decisive = state.evaluation->decisive;
                break;
            }
        }
        attachments(evaluator, result);
    }
    return result;
}
static char *final_notation(Evaluation *result) {
    return definite(result->decision)
               ? format("%s by %s", notation(result->decision, result->reason),
                        result->decisive->identifier)
               : notation(result->decision, result->reason);
}
static void tree_lines(FILE *file, Evaluation *result, int depth) {
    Element *e = result->element;
    int indentation = 2 + 2 * depth;
    fprintf(file, "%*s%s %s %s target %s", indentation, "", e->kind, e->identifier, e->behavior,
            target_name(result->target.kind));
    if (!strcmp(e->kind, "rule") && result->target.kind == T_MATCH)
        fprintf(file, " condition %s",
                result->condition.kind == V_ERROR ? "INDETERMINATE"
                : result->condition.boolean       ? "TRUE"
                                                  : "FALSE");
    fprintf(file, " -> %s\n", notation(result->decision, result->reason));
    if (strcmp(e->kind, "rule") && result->target.kind != T_NO_MATCH)
        for (size_t i = 0; i < e->children.count; ++i) {
            Element *child = e->children.items[i];
            ChildState state = result->children.items[i];
            if (state.kind == C_EVALUATED)
                tree_lines(file, state.evaluation, depth + 1);
            else if (state.kind == C_SKIPPED)
                fprintf(file, "%*s%s %s skipped\n", indentation + 2, "", child->kind,
                        child->identifier);
            else {
                fprintf(file, "%*s%s %s %s target %s", indentation + 2, "", child->kind,
                        child->identifier, child->behavior, target_name(state.checked.kind));
                if (state.checked.kind == T_INDETERMINATE)
                    fprintf(file, " (%s)", state.checked.reason);
                fputc('\n', file);
            }
        }
}
typedef struct {
    char *name;
    Attributes attributes;
} Subject;
typedef struct {
    char *name, *type;
    Attributes attributes;
} Resource;
typedef struct {
    char *identifier, *user, *roles, *action, *resource;
    Attributes environment;
    bool explain;
} Request;
typedef struct {
    char *role, *reason;
} Activation;
VECTOR(Activations, Activation)
typedef struct {
    Activations activations;
    Roles roles;
    int grant;
    Attributes values;
} Prepared;
typedef struct {
    char *name;
    int count;
} Counter;
VECTOR(Counters, Counter)
typedef struct {
    RBAC rbac;
    Policies policies;
    Elements rules;
    Subject subjects[100];
    int subject_count;
    Resource resources[200];
    int resource_count;
    Domains domains;
    Attributes reference;
    Request requests[300];
    int request_count;
    char coverage[100][301];
    int decisive[100], decisions[5], grants[300], refused;
    Counters obligations, advice;
} Engine;
static Subject *find_subject(Engine *e, const char *name) {
    for (int i = 0; i < e->subject_count; ++i)
        if (!strcmp(e->subjects[i].name, name))
            return &e->subjects[i];
    return NULL;
}
static Resource *find_resource(Engine *e, const char *name) {
    for (int i = 0; i < e->resource_count; ++i)
        if (!strcmp(e->resources[i].name, name))
            return &e->resources[i];
    return NULL;
}
static void count_item(Counters *counters, char *name) {
    for (size_t i = 0; i < counters->count; ++i)
        if (!strcmp(counters->items[i].name, name)) {
            ++counters->items[i].count;
            return;
        }
    Memory *previous = memory;
    memory = &permanent;
    Counters_add(counters, (Counter){name, 1});
    memory = previous;
}
static void read_inputs(Engine *e) {
    read_rbac(&e->rbac);
    e->policies = read_policies();
    for (size_t i = 0; i < e->policies.elements.count; ++i)
        if (!strcmp(e->policies.elements.items[i]->kind, "rule"))
            Elements_add(&e->rules, e->policies.elements.items[i]);
    Names lines = read_lines("input/attributes.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        char **s = f.items;
        if (!strcmp(s[0], "SUBJECT"))
            e->subjects[e->subject_count++] = (Subject){s[1], attributes(f, 2)};
        else if (!strcmp(s[0], "RESOURCE"))
            e->resources[e->resource_count++] = (Resource){s[1], s[2], attributes(f, 3)};
        else if (!strcmp(s[0], "DOMAIN")) {
            Domain d = {.reference = s[1]};
            for (size_t j = 2; j < f.count; ++j)
                Values_add(&d.candidates, input_value(s[j]));
            Domains_add(&e->domains, d);
        } else
            e->reference = attributes(f, 1);
    }
    lines = read_lines("input/requests.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        bool explain = !strcmp(f.items[f.count - 1], "EXPLAIN");
        if (explain)
            --f.count;
        char **s = f.items;
        e->requests[e->request_count++] =
            (Request){s[0], s[1], s[2], s[3], s[4], attributes(f, 5), explain};
    }
}
static char *check(Engine *e, Request request) {
    if (!find_subject(e, request.user))
        return format("unknown user %s", request.user);
    if (!find_resource(e, request.resource))
        return format("unknown resource %s", request.resource);
    Value *day = attribute(request.environment, "day");
    if (!day || day->kind != V_INTEGER || day->integer < 1 || day->integer > 365)
        return "bad day";
    return NULL;
}
static Prepared prepare(Engine *e, Request request) {
    Prepared out = {.grant = -1};
    RBAC *r = &e->rbac;
    int day = attribute(request.environment, "day")->integer;
    Roles allowed = authorized(r, request.user, day), active = 0;
    Names candidates = !strcmp(request.roles, "-")   ? (Names){0}
                       : !strcmp(request.roles, "*") ? role_names(r, allowed)
                                                     : split(request.roles, ",");
    for (size_t i = 0; i < candidates.count; ++i) {
        char *candidate = candidates.items[i], *reason = NULL;
        int role = find_role(r, candidate);
        bool seen = false;
        for (size_t j = 0; j < i; ++j)
            seen |= !strcmp(candidates.items[j], candidate);
        if (role < 0)
            reason = "unknown";
        else if (seen)
            reason = "duplicate";
        else if (!(allowed & bit(role)))
            reason = "unauthorized";
        else
            for (int j = 0; j < r->dsd_count; ++j)
                if (cardinality(r->dsd[j].roles & closure(r, active | bit(role))) >=
                    r->dsd[j].cardinality) {
                    reason = format("dsd %s", r->dsd[j].name);
                    break;
                }
        if (!reason)
            active |= bit(role);
        Activations_add(&out.activations, (Activation){candidate, reason});
    }
    out.roles = closure(r, active);
    Resource *resource = find_resource(e, request.resource);
    Names roles = role_names(r, out.roles);
    for (size_t i = 0; i < roles.count; ++i) {
        int role = find_role(r, roles.items[i]);
        if (permits(r, role, request.action, resource->type)) {
            out.grant = role;
            break;
        }
    }
    Attributes subject = find_subject(e, request.user)->attributes;
    for (size_t i = 0; i < subject.count; ++i)
        set_attribute(&out.values, format("subject.%s", subject.items[i].name),
                      subject.items[i].value);
    set_attribute(&out.values, "subject.id", word_value(request.user));
    set_attribute(&out.values, "subject.role", bag_value(roles));
    set_attribute(&out.values, "subject.rbac", bool_value(out.grant >= 0));
    for (size_t i = 0; i < resource->attributes.count; ++i)
        set_attribute(&out.values, format("resource.%s", resource->attributes.items[i].name),
                      resource->attributes.items[i].value);
    set_attribute(&out.values, "resource.id", word_value(request.resource));
    set_attribute(&out.values, "resource.type", word_value(resource->type));
    set_attribute(&out.values, "action.id", word_value(request.action));
    for (size_t i = 0; i < request.environment.count; ++i)
        set_attribute(&out.values, format("environment.%s", request.environment.items[i].name),
                      request.environment.items[i].value);
    return out;
}
static void process_requests(Engine *e, FILE *decisions, FILE *traces) {
    bool explained = false;
    for (int q = 0; q < e->request_count; ++q) {
        Memory work = {0};
        memory = &work;
        Request request = e->requests[q];
        char symbols[100];
        memset(symbols, '.', sizeof(symbols));
        char *error = check(e, request);
        if (request.explain) {
            if (explained)
                fputc('\n', traces);
            explained = true;
            fprintf(traces, "request %s\n", request.identifier);
        }
        if (error) {
            fprintf(decisions, "%s ERROR %s\n", request.identifier, error);
            ++e->decisions[4];
            if (request.explain)
                fprintf(traces, "  error %s\n", error);
        } else {
            Prepared prepared = prepare(e, request);
            Evaluator evaluator = {prepared.values, symbols};
            Evaluation *result = evaluate(&evaluator, e->policies.root);
            fprintf(decisions, "%s %s\n", request.identifier, final_notation(result));
            for (size_t i = 0; i < prepared.activations.count; ++i) {
                Activation a = prepared.activations.items[i];
                if (a.reason) {
                    fprintf(decisions, "  refused %s %s\n", a.role, a.reason);
                    ++e->refused;
                }
            }
            for (size_t i = 0; i < result->obligations.count; ++i) {
                Item item = result->obligations.items[i];
                fprintf(decisions, "  obligation %s\n", item.text);
                count_item(&e->obligations, item.identifier);
            }
            for (size_t i = 0; i < result->advice.count; ++i) {
                Item item = result->advice.items[i];
                fprintf(decisions, "  advice %s\n", item.text);
                count_item(&e->advice, item.identifier);
            }
            Resource *resource = find_resource(e, request.resource);
            if (prepared.grant >= 0)
                for (int i = 0; i < e->rbac.grant_count; ++i) {
                    Grant g = e->rbac.grants[i];
                    if (g.role == prepared.grant && !strcmp(g.action, request.action) &&
                        !strcmp(g.type, resource->type)) {
                        ++e->grants[i];
                        break;
                    }
                }
            ++e->decisions[indeterminate(result->decision) ? 3 : result->decision];
            if (definite(result->decision))
                ++e->decisive[result->decisive->index];
            if (request.explain) {
                fprintf(traces, "  user %s resource %s type %s action %s day %d\n", request.user,
                        request.resource, resource->type, request.action,
                        attribute(request.environment, "day")->integer);
                for (size_t i = 0; i < prepared.activations.count; ++i) {
                    Activation a = prepared.activations.items[i];
                    fprintf(traces, "  activate %s %s\n", a.role,
                            a.reason ? format("refused %s", a.reason) : "ok");
                }
                fprintf(traces, "  roles %s\n",
                        prepared.roles ? join(role_names(&e->rbac, prepared.roles), ",") : "-");
                fprintf(traces, "  rbac %s\n",
                        prepared.grant >= 0 ? format("yes %s", e->rbac.roles[prepared.grant])
                                            : "no");
                tree_lines(traces, result, 0);
                fprintf(traces, "  decision %s\n", final_notation(result));
            }
        }
        for (size_t i = 0; i < e->rules.count; ++i) {
            int index = e->rules.items[i]->index;
            e->coverage[index][q] = symbols[index];
        }
        clear_memory(&work);
        memory = &permanent;
    }
}
typedef struct {
    char *action, *type;
    Roles roles;
} Permission;
static int permission_order(const void *a, const void *b) {
    const Permission *x = a, *y = b;
    int c = strcmp(x->action, y->action);
    return c ? c : strcmp(x->type, y->type);
}
static int name_order(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}
static void permission_report(Engine *e, FILE *file) {
    RBAC *r = &e->rbac;
    Names users = {0};
    for (int i = 0; i < r->assignment_count; ++i) {
        char *user = r->assignments[i].user;
        bool seen = false;
        for (size_t j = 0; j < users.count; ++j)
            seen |= !strcmp(users.items[j], user);
        if (!seen)
            Names_add(&users, user);
    }
    qsort(users.items, users.count, sizeof(char *), name_order);
    for (size_t u = 0; u < users.count; ++u) {
        char *user = users.items[u];
        if (u)
            fputc('\n', file);
        fprintf(file, "user %s\n", user);
        Days assigned_days[40] = {0}, authorized_days[40] = {0};
        Roles present = 0;
        for (int i = 0; i < r->assignment_count; ++i) {
            Assignment a = r->assignments[i];
            if (strcmp(a.user, user))
                continue;
            present |= bit(a.role);
            for (int day = a.first; day <= a.last; ++day)
                assigned_days[a.role].days[day] = true;
        }
        Roles all = closure(r, present);
        for (int role = 0; role < r->role_count; ++role)
            if (present & bit(role)) {
                Roles inherited = closure(r, bit(role));
                for (int target = 0; target < r->role_count; ++target)
                    if (inherited & bit(target))
                        for (int day = 1; day <= 365; ++day)
                            authorized_days[target].days[day] |= assigned_days[role].days[day];
            }
        Names names = role_names(r, present);
        for (size_t i = 0; i < names.count; ++i)
            fprintf(file, "  assigned %s %s\n", names.items[i],
                    day_notation(assigned_days[find_role(r, names.items[i])]));
        names = role_names(r, all);
        for (size_t i = 0; i < names.count; ++i)
            fprintf(file, "  authorized %s %s\n", names.items[i],
                    day_notation(authorized_days[find_role(r, names.items[i])]));
        Permission permissions[300];
        int count = 0;
        for (int i = 0; i < r->grant_count; ++i) {
            Grant g = r->grants[i];
            if (!(all & bit(g.role)))
                continue;
            int j = 0;
            while (j < count &&
                   (strcmp(permissions[j].action, g.action) || strcmp(permissions[j].type, g.type)))
                ++j;
            if (j == count)
                permissions[count++] = (Permission){g.action, g.type, 0};
            permissions[j].roles |= bit(g.role);
        }
        qsort(permissions, (size_t)count, sizeof(Permission), permission_order);
        for (int i = 0; i < count; ++i) {
            Permission permission = permissions[i];
            Days days = {0};
            for (int role = 0; role < r->role_count; ++role)
                if (permission.roles & bit(role))
                    for (int day = 1; day <= 365; ++day)
                        days.days[day] |= authorized_days[role].days[day];
            char *effective = "-";
            if (find_subject(e, user)) {
                int permitted = 0, total = 0;
                for (int j = 0; j < e->resource_count; ++j)
                    if (!strcmp(e->resources[j].type, permission.type)) {
                        ++total;
                        Memory work = {0};
                        memory = &work;
                        Request request = {.user = user,
                                           .roles = "*",
                                           .action = permission.action,
                                           .resource = e->resources[j].name,
                                           .environment = e->reference};
                        Prepared prepared = prepare(e, request);
                        Evaluator evaluator = {prepared.values, NULL};
                        permitted += evaluate(&evaluator, e->policies.root)->decision == D_PERMIT;
                        clear_memory(&work);
                        memory = &permanent;
                    }
                effective = format("%d/%d", permitted, total);
            }
            fprintf(file, "  permission %s %s %s via %s effective %s\n", permission.action,
                    permission.type, day_notation(days), join(role_names(r, permission.roles), ","),
                    effective);
        }
    }
}
typedef struct {
    Element *policy, *earlier, *later;
} ConflictPair;
VECTOR(ConflictPairs, ConflictPair)
static void domain_analysis(Engine *e, FILE *file) {
    int counts[100] = {0}, conflicts[100][100] = {0};
    char *examples[100] = {0};
    bool shadowed[100] = {0}, blockers[100][100] = {0};
    ConflictPairs pairs = {0};
    for (size_t i = 0; i < e->rules.count; ++i) {
        Element *rule_element = e->rules.items[i];
        shadowed[rule_element->index] = !strcmp(rule_element->parent->behavior, "first-applicable");
    }
    for (size_t p = 0; p < e->policies.elements.count; ++p) {
        Element *policy = e->policies.elements.items[p];
        if (strcmp(policy->kind, "policy"))
            continue;
        for (size_t i = 0; i < policy->children.count; ++i)
            for (size_t j = i + 1; j < policy->children.count; ++j)
                if (strcmp(policy->children.items[i]->behavior,
                           policy->children.items[j]->behavior))
                    ConflictPairs_add(&pairs, (ConflictPair){policy, policy->children.items[i],
                                                             policy->children.items[j]});
    }
    int points = point_count(e->domains);
    for (int ordinal = 0; ordinal < points; ++ordinal) {
        Memory work = {0};
        memory = &work;
        Attributes values = domain_point(e->domains, ordinal);
        Evaluator evaluator = {values, NULL};
        TargetKind targets[100] = {0};
        Decision standalone[100] = {0};
        bool applies[100] = {0};
        for (size_t i = 0; i < e->policies.elements.count; ++i) {
            Element *element = e->policies.elements.items[i];
            if (strcmp(element->kind, "rule"))
                targets[element->index] = evaluate_target(&evaluator, element).kind;
        }
        for (size_t i = 0; i < e->rules.count; ++i) {
            Element *element = e->rules.items[i];
            standalone[element->index] = rule(&evaluator, element, false)->decision;
        }
        for (size_t i = 0; i < e->rules.count; ++i) {
            Element *element = e->rules.items[i];
            int index = element->index;
            bool applicable = definite(standalone[index]);
            for (Element *parent = element->parent; parent; parent = parent->parent)
                applicable &= targets[parent->index] == T_MATCH;
            if (!applicable)
                continue;
            applies[index] = true;
            ++counts[index];
            if (!examples[index]) {
                Names parts = {0};
                for (size_t j = 0; j < e->domains.count; ++j) {
                    Domain d = e->domains.items[j];
                    if (d.candidates.count >= 2)
                        Names_add(&parts, format("%s=%s", d.reference,
                                                 value_notation(*attribute(values, d.reference))));
                }
                char *example = join(parts, " ");
                memory = &permanent;
                examples[index] = copy_text(example);
                memory = &work;
            }
            if (shadowed[index]) {
                Element *earlier = blocker(element, standalone);
                if (earlier)
                    blockers[index][earlier->index] = true;
                else
                    shadowed[index] = false;
            }
        }
        for (size_t i = 0; i < pairs.count; ++i) {
            ConflictPair pair = pairs.items[i];
            if (applies[pair.earlier->index] && applies[pair.later->index])
                ++conflicts[pair.earlier->index][pair.later->index];
        }
        clear_memory(&work);
        memory = &permanent;
    }
    fprintf(file, "applicability %d\n", points);
    int dead = 0, shadows = 0, conflict_count = 0;
    for (size_t i = 0; i < e->rules.count; ++i) {
        Element *element = e->rules.items[i];
        int index = element->index;
        fprintf(file, "  %s %d %s\n", element->identifier, counts[index],
                counts[index] ? examples[index] : "-");
        if (!counts[index]) {
            ++dead;
            shadowed[index] = false;
        }
        shadows += shadowed[index];
    }
    fprintf(file, "dead %d\n", dead);
    for (size_t i = 0; i < e->rules.count; ++i)
        if (!counts[e->rules.items[i]->index])
            fprintf(file, "  %s\n", e->rules.items[i]->identifier);
    fprintf(file, "shadowed %d\n", shadows);
    for (size_t i = 0; i < e->rules.count; ++i) {
        Element *element = e->rules.items[i];
        if (!shadowed[element->index])
            continue;
        Names names = {0};
        for (size_t j = 0; j < e->rules.count; ++j)
            if (blockers[element->index][e->rules.items[j]->index])
                Names_add(&names, e->rules.items[j]->identifier);
        fprintf(file, "  %s by %s\n", element->identifier, join(names, ","));
    }
    for (size_t i = 0; i < pairs.count; ++i)
        conflict_count += conflicts[pairs.items[i].earlier->index][pairs.items[i].later->index] > 0;
    fprintf(file, "conflicts %d\n", conflict_count);
    for (size_t i = 0; i < pairs.count; ++i) {
        ConflictPair pair = pairs.items[i];
        int count = conflicts[pair.earlier->index][pair.later->index];
        if (count)
            fprintf(file, "  %s %s %s %d %s\n", pair.policy->identifier, pair.earlier->identifier,
                    pair.later->identifier, count,
                    conflict_winner(pair.policy, pair.earlier, pair.later)->identifier);
    }
}
static const RBAC *sorting_rbac;
static int grant_order(const void *a, const void *b) {
    const Grant *x = &sorting_rbac->grants[*(const int *)a],
                *y = &sorting_rbac->grants[*(const int *)b];
    int c = strcmp(sorting_rbac->roles[x->role], sorting_rbac->roles[y->role]);
    if (!c)
        c = strcmp(x->action, y->action);
    return c ? c : strcmp(x->type, y->type);
}
static int counter_order(const void *a, const void *b) {
    return strcmp(((const Counter *)a)->name, ((const Counter *)b)->name);
}
static void analysis_report(Engine *e, FILE *file) {
    RBAC *r = &e->rbac;
    fprintf(file, "rbac %d\n", r->diagnostic_count);
    for (int i = 0; i < r->diagnostic_count; ++i) {
        Diagnostic d = r->diagnostics[i];
        fprintf(file, "  line %d %s %s\n", d.number, d.keyword, d.message);
    }
    int order[300];
    for (int i = 0; i < r->grant_count; ++i)
        order[i] = i;
    sorting_rbac = r;
    qsort(order, (size_t)r->grant_count, sizeof(int), grant_order);
    fprintf(file, "grants %d\n", r->grant_count);
    for (int i = 0; i < r->grant_count; ++i) {
        int index = order[i];
        Grant g = r->grants[index];
        fprintf(file, "  %s %s %s %d\n", r->roles[g.role], g.action, g.type, e->grants[index]);
    }
    domain_analysis(e, file);
    fprintf(file, "coverage %d\n", e->request_count);
    bool uncovered[100] = {0};
    int uncovered_count = 0;
    for (size_t i = 0; i < e->rules.count; ++i) {
        Element *element = e->rules.items[i];
        int index = element->index, count = 0;
        for (int q = 0; q < e->request_count; ++q)
            count += e->coverage[index][q] == 'P' || e->coverage[index][q] == 'D';
        fprintf(file, "  %s %s %d\n", element->identifier, e->coverage[index], count);
        if (!count) {
            uncovered[index] = true;
            ++uncovered_count;
        }
    }
    fprintf(file, "uncovered %d\n", uncovered_count);
    for (size_t i = 0; i < e->rules.count; ++i)
        if (uncovered[e->rules.items[i]->index])
            fprintf(file, "  %s\n", e->rules.items[i]->identifier);
    fputs("summary\n", file);
    char *names[] = {"PERMIT", "DENY", "NOT_APPLICABLE", "INDETERMINATE", "ERROR"};
    for (int i = 0; i < 5; ++i)
        fprintf(file, "  decision %s %d\n", names[i], e->decisions[i]);
    fprintf(file, "  refused %d\n", e->refused);
    for (size_t i = 0; i < e->policies.elements.count; ++i) {
        Element *element = e->policies.elements.items[i];
        if (e->decisive[element->index])
            fprintf(file, "  decisive %s %d\n", element->identifier, e->decisive[element->index]);
    }
    qsort(e->obligations.items, e->obligations.count, sizeof(Counter), counter_order);
    qsort(e->advice.items, e->advice.count, sizeof(Counter), counter_order);
    for (size_t i = 0; i < e->obligations.count; ++i)
        fprintf(file, "  obligation %s %d\n", e->obligations.items[i].name,
                e->obligations.items[i].count);
    for (size_t i = 0; i < e->advice.count; ++i)
        fprintf(file, "  advice %s %d\n", e->advice.items[i].name, e->advice.items[i].count);
}
int main(void) {
    Engine *engine = allocate(sizeof(*engine));
    read_inputs(engine);
    mkdir("output", 0777);
    FILE *decisions = fopen("output/decisions.txt", "wb"),
         *traces = fopen("output/traces.txt", "wb");
    process_requests(engine, decisions, traces);
    fclose(decisions);
    fclose(traces);
    FILE *permissions = fopen("output/permissions.txt", "wb");
    permission_report(engine, permissions);
    fclose(permissions);
    FILE *analysis = fopen("output/analysis.txt", "wb");
    analysis_report(engine, analysis);
    fclose(analysis);
    clear_memory(&permanent);
    return 0;
}
