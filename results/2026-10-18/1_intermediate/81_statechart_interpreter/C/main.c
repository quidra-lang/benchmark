#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef struct Allocation Allocation;
struct Allocation {
    void *pointer;
    Allocation *next;
};
static Allocation *allocations;

static void *allocate(size_t size) {
    void *pointer = calloc(1, size ? size : 1);
    Allocation *allocation = malloc(sizeof(*allocation));
    if (!pointer || !allocation) exit(EXIT_FAILURE);
    *allocation = (Allocation){pointer, allocations};
    allocations = allocation;
    return pointer;
}

static char *substring(const char *text, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, text, length);
    return result;
}

static char *copy_string(const char *text) {
    return substring(text, strlen(text));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int length = vsnprintf(NULL, 0, pattern, saved);
    va_end(saved);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}

static void release_chart(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *text = malloc(capacity);
    if (!text) exit(EXIT_FAILURE);
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *grown = realloc(text, capacity);
            if (!grown) exit(EXIT_FAILURE);
            text = grown;
        }
        text[length++] = (char)c;
    }
    if (length && text[length - 1] == '\r') length--;
    text[length] = '\0';
    return text;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool starts(const char *text, const char *prefix) {
    return strncmp(text, prefix, strlen(prefix)) == 0;
}

static char *word(const char **text) {
    while (**text == ' ') (*text)++;
    const char *start = *text;
    while (**text && **text != ' ') (*text)++;
    char *result = substring(start, (size_t)(*text - start));
    while (**text == ' ') (*text)++;
    return result;
}
typedef struct {
    char **items;
    int count;
} Words;

static Words words(const char *text) {
    Words result = {allocate((strlen(text) + 1) * sizeof(char *)), 0};
    while (*text) result.items[result.count++] = word(&text);
    return result;
}
typedef enum {
    STATE,
    PARALLEL,
    FINAL,
    HISTORY
} StateKind;
typedef enum {
    NUMBER,
    VARIABLE,
    IN_STATE,
    UNARY,
    BINARY
} NodeKind;
typedef struct Node Node;
struct Node {
    NodeKind kind;
    char *text;
    Node *left, *right;
};
typedef enum {
    ASSIGN,
    RAISE,
    SEND,
    CANCEL,
    LOG
} ActionKind;
typedef struct {
    ActionKind kind;
    char *name, *literal;
    Node *expression;
    int delay;
} Action;
typedef struct {
    Action *items;
    int count;
} Actions;
typedef enum {
    EVENT_TRIGGER,
    TIMER_TRIGGER,
    ALWAYS_TRIGGER,
    START_TRIGGER
} TriggerKind;
typedef enum {
    INTERNAL,
    EXTERNAL,
    LOCAL
} TransitionMode;
typedef struct Transition Transition;
struct Transition {
    int source, target;
    char *target_name;
    TriggerKind trigger;
    TransitionMode mode;
    char **descriptors;
    int descriptor_count, delay;
    Node *guard;
    Actions actions;
};
typedef struct {
    char *name, *initial_name, *default_name;
    StateKind kind;
    int parent, children[40], child_count, depth;
    bool deep, active, history_recorded;
    uint64_t history;
    Actions entries[120], exits[120];
    int entry_count, exit_count;
    Transition *transitions[120];
    int transition_count;
    long long entered, taken, dwell, entry_time;
} State;
typedef struct {
    char *name;
    long long value;
} Variable;
typedef struct {
    char *name;
    long long value;
} Event;
typedef struct {
    long long due, number;
    Transition *timer;
    Event event;
} Reservation;
typedef struct {
    TriggerKind kind;
    Event event;
    Transition *timer;
} Trigger;
typedef struct {
    Transition *transition;
    int scope;
    uint64_t exits;
} Choice;
typedef struct {
    Choice items[40];
    int count;
} Choices;
typedef struct {
    int number;
    char *text, *error;
    int state;
} Definition;
typedef struct {
    State states[41];
    int state_count, order[40], order_count;
    Variable variables[20];
    int variable_count;
    Event queue[10000];
    int queue_front, queue_count;
    Reservation reservations[5000];
    int reservation_count;
    long long time, data, creations, macrosteps, microsteps;
    int in_macro;
    bool trace, halted;
} Chart;

static uint64_t bit(int state) {
    return UINT64_C(1) << state;
}

static bool contains(uint64_t set, int state) {
    return (set & bit(state)) != 0;
}

static int find_state(const Chart *chart, const char *name) {
    for (int i = 1; i < chart->state_count; i++) if (equal(chart->states[i].name, name)) return i;
    return -1;
}

static int find_variable(const Chart *chart, const char *name) {
    for (int i = 0; i < chart->variable_count; i++) if (equal(chart->variables[i].name, name)) return i;
    return -1;
}

static int child_state_count(const Chart *chart, int state) {
    int count = 0;
    const State *s = &chart->states[state];
    for (int i = 0; i < s->child_count; i++) if (chart->states[s->children[i]].kind != HISTORY) count++;
    return count;
}

static bool compound(const Chart *chart, int state) {
    return state == 0 || (chart->states[state].kind == STATE && child_state_count(chart, state) != 0);
}

static bool parallel(const Chart *chart, int state) {
    return chart->states[state].kind == PARALLEL && child_state_count(chart, state) != 0;
}

static bool atomic(const Chart *chart, int state) {
    return chart->states[state].kind != HISTORY && child_state_count(chart, state) == 0;
}

static bool descendant(const Chart *chart, int state, int ancestor) {
    for (int p = chart->states[state].parent; p >= 0; p = chart->states[p].parent) if (p == ancestor) return true;
    return false;
}

static int initial(const Chart *chart, int state) {
    const State *s = &chart->states[state];
    if (s->initial_name) return find_state(chart, s->initial_name);
    for (int i = 0; i < s->child_count; i++) if (chart->states[s->children[i]].kind != HISTORY) return s->children[i];
    return -1;
}

static int default_target(const Chart *chart, int history) {
    const State *h = &chart->states[history];
    return h->default_name ? find_state(chart, h->default_name) : initial(chart, h->parent);
}

static void visit(Chart *chart, int state) {
    chart->order[chart->order_count++] = state;
    const State *s = &chart->states[state];
    for (int i = 0; i < s->child_count; i++) visit(chart, s->children[i]);
}

static Node *node(NodeKind kind, char *text, Node *left, Node *right) {
    Node *result = allocate(sizeof(*result));
    *result = (Node){kind, text, left, right};
    return result;
}
typedef struct {
    Words tokens;
    int position;
} ExpressionParser;

static bool name_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static bool two_character_operator(const char *text) {
    return starts(text, "||") || starts(text, "&&") || starts(text, "==") || starts(text, "!=") || starts(text, "<=") || starts(text, ">=");
}
static Node *parse_level(ExpressionParser *parser, int precedence);

static Node *parse_unary(ExpressionParser *parser) {
    char *token = parser->tokens.items[parser->position++];
    if (equal(token, "!") || equal(token, "-")) return node(UNARY, token, parse_unary(parser), NULL);
    if (equal(token, "(")) {
        Node *result = parse_level(parser, 0);
        parser->position++;
        return result;
    }
    if (equal(token, "in")) {
        parser->position++;
        char *state = parser->tokens.items[parser->position++];
        parser->position++;
        return node(IN_STATE, state, NULL, NULL);
    }
    return node(token[0] >= '0' && token[0] <= '9' ? NUMBER : VARIABLE, token, NULL, NULL);
}

static bool operator_at(const char *text, int precedence) {
    switch (precedence) {
        case 0: return equal(text, "||");
        case 1: return equal(text, "&&");
        case 2: return equal(text, "==") || equal(text, "!=") || equal(text, "<") || equal(text, "<=") || equal(text, ">") || equal(text, ">=");
        case 3: return equal(text, "+") || equal(text, "-");
        default:
            return equal(text, "*") || equal(text, "/") || equal(text, "%");
    }
}

static Node *parse_level(ExpressionParser *parser, int precedence) {
    if (precedence == 5) return parse_unary(parser);
    Node *result = parse_level(parser, precedence + 1);
    while (parser->position < parser->tokens.count && operator_at(parser->tokens.items[parser->position], precedence)) {
        char *operation = parser->tokens.items[parser->position++];
        Node *right = parse_level(parser, precedence + 1);
        result = node(BINARY, operation, result, right);
    }
    return result;
}

static Node *expression(const char *text) {
    ExpressionParser parser = {
        {allocate((strlen(text) + 1) * sizeof(char *)), 0}, 0
    };
    for (size_t i = 0; text[i];) {
        if (text[i] == ' ') {
            i++;
            continue;
        }
        size_t start = i;
        if (name_char(text[i])) while (name_char(text[i])) i++;
        else if (two_character_operator(text + i)) i += 2;
        else i++;
        parser.tokens.items[parser.tokens.count++] = substring(text + start, i - start);
    }
    return parse_level(&parser, 0);
}

static char *reference(const Chart *chart, const Node *n) {
    if (!n) return NULL;
    if (n->kind == VARIABLE) return equal(n->text, "_data") || find_variable(chart, n->text) >= 0 ? NULL : format("unknown variable %s", n->text);
    if (n->kind == IN_STATE) return find_state(chart, n->text) >= 0 ? NULL : format("unknown state %s", n->text);
    char *error = reference(chart, n->left);
    return error ? error : reference(chart, n->right);
}

static long long evaluate(Chart *chart, const Node *n, bool *success) {
    if (n->kind == NUMBER) return strtoll(n->text, NULL, 10);
    if (n->kind == VARIABLE) return equal(n->text, "_data") ? chart->data : chart->variables[find_variable(chart, n->text)].value;
    if (n->kind == IN_STATE) return chart->states[find_state(chart, n->text)].active ? 1 : 0;
    long long a = evaluate(chart, n->left, success);
    if (!*success) return 0;
    if (n->kind == UNARY) return equal(n->text, "-") ? -a : a == 0;
    if (equal(n->text, "&&") && a == 0) return 0;
    if (equal(n->text, "||") && a != 0) return 1;
    long long b = evaluate(chart, n->right, success);
    if (!*success) return 0;
    if ((equal(n->text, "/") || equal(n->text, "%")) && b == 0) {
        *success = false;
        return 0;
    }
    if (equal(n->text, "+")) return a + b;
    if (equal(n->text, "-")) return a - b;
    if (equal(n->text, "*")) return a * b;
    if (equal(n->text, "/")) return a / b;
    if (equal(n->text, "%")) return a % b;
    if (equal(n->text, "==")) return a == b;
    if (equal(n->text, "!=")) return a != b;
    if (equal(n->text, "<")) return a < b;
    if (equal(n->text, "<=")) return a <= b;
    if (equal(n->text, ">")) return a > b;
    if (equal(n->text, ">=")) return a >= b;
    return b != 0;
}

static Actions actions(const char *text) {
    Actions result = {allocate(10 * sizeof(Action)), 0};
    while (*text) {
        const char *separator = strstr(text, "; ");
        const char *rest = separator ? substring(text, (size_t)(separator - text)) : text;
        char *first = word(&rest);
        Action *a = &result.items[result.count++];
        a->literal = "";
        if (equal(first, "raise") || equal(first, "send")) {
            a->kind = equal(first, "raise") ? RAISE : SEND;
            a->name = word(&rest);
            if (a->kind == SEND) a->delay = atoi(word(&rest));
            if (*rest) a->expression = expression(rest);
        } else if (equal(first, "cancel")) {
            a->kind = CANCEL;
            a->name = copy_string(rest);
        } else if (equal(first, "log")) {
            a->kind = LOG;
            if (*rest == '"') {
                const char *end = strchr(rest + 1, '"');
                a->literal = substring(rest + 1, (size_t)(end - rest - 1));
                if (end[1]) a->expression = expression(end + 2);
            } else a->expression = expression(rest);
        } else {
            a->kind = ASSIGN;
            a->name = first;
            a->expression = expression(rest + 2);
        }
        if (!separator) break;
        text = separator + 2;
    }
    return result;
}

static char *action_references(const Chart *chart, Actions list) {
    for (int i = 0; i < list.count; i++) {
        Action *a = &list.items[i];
        if (a->kind == ASSIGN && find_variable(chart, a->name) < 0) return format("unknown variable %s", a->name);
        char *error = reference(chart, a->expression);
        if (error) return error;
    }
    return NULL;
}

static Transition *parse_transition(const Chart *chart, const char *text) {
    Transition *t = allocate(sizeof(*t));
    const char *rest = text + 3;
    t->source = find_state(chart, word(&rest));
    t->target = -1;
    char *trigger = word(&rest);
    if (equal(trigger, "after")) {
        t->trigger = TIMER_TRIGGER;
        t->delay = atoi(word(&rest));
    } else if (equal(trigger, "always")) t->trigger = ALWAYS_TRIGGER;
    else {
        t->trigger = EVENT_TRIGGER;
        t->descriptors = allocate(5 * sizeof(char *));
        char *start = trigger;
        for (char *p = trigger;; p++) if (*p == '|' || *p == '\0') {
            t->descriptors[t->descriptor_count++] = substring(start, (size_t)(p - start));
            if (!*p) break;
            start = p + 1;
        }
    }
    if (*rest == '[') {
        const char *close = strchr(rest, ']');
        t->guard = expression(substring(rest + 1, (size_t)(close - rest - 1)));
        rest = close + 1;
        while (*rest == ' ') rest++;
    }
    if (starts(rest, "-> ") || starts(rest, "~> ")) {
        t->mode = rest[0] == '~' ? LOCAL : EXTERNAL;
        rest += 3;
        t->target_name = word(&rest);
    }
    if (starts(rest, "/ ")) t->actions = actions(rest + 2);
    return t;
}

static bool define(Chart *chart, Definition *definitions, int count) {
    for (int i = 0; i < count; i++) {
        Definition *d = &definitions[i];
        Words a = words(d->text);
        const char *kind = a.items[0];
        d->state = -1;
        if (equal(kind, "state") || equal(kind, "parallel") || equal(kind, "final") || equal(kind, "history")) {
            char *parent_name = a.count > 2 && !equal(a.items[2], "initial") ? a.items[2] : NULL;
            int parent = parent_name ? find_state(chart, parent_name) : 0;
            if (find_state(chart, a.items[1]) >= 0) d->error = format("duplicate state %s", a.items[1]);
            else if (parent < 0) d->error = format("unknown state %s", parent_name);
            else if (chart->states[parent].kind == FINAL || chart->states[parent].kind == HISTORY) d->error = format("%s cannot have children", parent_name);
            else {
                int index = chart->state_count++;
                State *state = &chart->states[index];
                d->state = index;
                state->name = a.items[1];
                state->kind = equal(kind, "state") ? STATE : equal(kind, "parallel") ? PARALLEL : equal(kind, "final") ? FINAL : HISTORY;
                state->parent = parent;
                state->depth = chart->states[parent].depth + 1;
                chart->states[parent].children[chart->states[parent].child_count++] = index;
                if (state->kind == STATE) for (int j = 2; j < a.count; j++) if (equal(a.items[j], "initial")) state->initial_name = a.items[j + 1];
                if (state->kind == HISTORY) {
                    state->deep = equal(a.items[3], "deep");
                    if (a.count == 5) state->default_name = a.items[4];
                }
            }
        } else if (equal(kind, "var")) {
            if (find_variable(chart, a.items[1]) >= 0) d->error = format("duplicate variable %s", a.items[1]);
            else chart->variables[chart->variable_count++] = (Variable){a.items[1], strtoll(a.items[2], NULL, 10)};
        }
    }
    for (int i = 0; i < count; i++) {
        Definition *d = &definitions[i];
        if (d->error) continue;
        Words a = words(d->text);
        const char *kind = a.items[0];
        State *state = d->state >= 0 ? &chart->states[d->state] : NULL;
        if (equal(kind, "state") && state->initial_name) {
            int child = find_state(chart, state->initial_name);
            if (child < 0) d->error = format("unknown state %s", state->initial_name);
            else if (chart->states[child].parent != d->state || chart->states[child].kind == HISTORY) d->error = format("%s is not a child of %s", state->initial_name, state->name);
        } else if (equal(kind, "final") || equal(kind, "history")) {
            if (chart->states[state->parent].kind != STATE || child_state_count(chart, state->parent) == 0) d->error = format("%s needs a compound parent", state->name);
            else if (equal(kind, "history") && state->default_name) {
                int target = find_state(chart, state->default_name);
                if (target < 0) d->error = format("unknown state %s", state->default_name);
                else if (!descendant(chart, target, state->parent) || chart->states[target].kind == HISTORY) d->error = format("%s is not a descendant of %s", state->default_name, chart->states[state->parent].name);
            }
        } else if (equal(kind, "entry") || equal(kind, "exit")) {
            int source = find_state(chart, a.items[1]);
            if (source < 0) d->error = format("unknown state %s", a.items[1]);
            else if (chart->states[source].kind == HISTORY) d->error = format("%s cannot have actions", a.items[1]);
            else {
                Actions list = actions(strstr(d->text, " / ") + 3);
                d->error = action_references(chart, list);
                if (!d->error) {
                    State *s = &chart->states[source];
                    if (equal(kind, "entry")) s->entries[s->entry_count++] = list;
                    else s->exits[s->exit_count++] = list;
                }
            }
        } else if (equal(kind, "on")) {
            int source = find_state(chart, a.items[1]);
            if (source < 0) d->error = format("unknown state %s", a.items[1]);
            else if (chart->states[source].kind == FINAL || chart->states[source].kind == HISTORY) d->error = format("%s cannot have transitions", a.items[1]);
            else {
                Transition *t = parse_transition(chart, d->text);
                d->error = reference(chart, t->guard);
                if (!d->error && t->target_name && find_state(chart, t->target_name) < 0) d->error = format("unknown state %s", t->target_name);
                if (!d->error) d->error = action_references(chart, t->actions);
                if (!d->error) {
                    if (t->target_name) t->target = find_state(chart, t->target_name);
                    chart->states[source].transitions[chart->states[source].transition_count++] = t;
                }
            }
        }
    }
    bool valid = true;
    for (int i = 0; i < count; i++) if (definitions[i].error) {
        printf("error line %d: %s\n", definitions[i].number, definitions[i].error);
        valid = false;
    }
    if (!valid) return false;
    for (int i = 0; i < chart->states[0].child_count; i++) visit(chart, chart->states[0].children[i]);
    return true;
}

static void warnings(Chart *chart) {
    uint64_t reachable = bit(initial(chart, 0)), before;
    do {
        before = reachable;
        for (int i = 0; i < chart->order_count; i++) {
            int index = chart->order[i];
            if (!contains(before, index)) continue;
            State *s = &chart->states[index];
            if (s->parent != 0) reachable |= bit(s->parent);
            if (compound(chart, index)) reachable |= bit(initial(chart, index));
            if (parallel(chart, index)) for (int j = 0; j < s->child_count; j++) if (chart->states[s->children[j]].kind != HISTORY) reachable |= bit(s->children[j]);
            for (int j = 0; j < s->transition_count; j++) {
                int target = s->transitions[j]->target;
                if (target >= 0) reachable |= bit(chart->states[target].kind == HISTORY ? default_target(chart, target) : target);
            }
        }
    } while (reachable != before);
    for (int i = 0; i < chart->order_count; i++) {
        int index = chart->order[i];
        if (chart->states[index].kind != HISTORY && !contains(reachable, index)) printf("warning: unreachable state %s\n", chart->states[index].name);
    }
}

static uint64_t effective(const Chart *chart, const Transition *t) {
    const State *target = &chart->states[t->target];
    if (target->kind != HISTORY) return bit(t->target);
    return target->history_recorded ? target->history : bit(default_target(chart, t->target));
}

static bool all_descendants(const Chart *chart, uint64_t targets, int scope) {
    for (int i = 0; i < chart->order_count; i++) {
        int state = chart->order[i];
        if (contains(targets, state) && !descendant(chart, state, scope)) return false;
    }
    return true;
}

static Choice make_choice(const Chart *chart, Transition *t) {
    Choice choice = {t, -1, 0};
    if (t->target < 0) return choice;
    uint64_t targets = effective(chart, t);
    if (t->mode == LOCAL && compound(chart, t->source) && all_descendants(chart, targets, t->source)) choice.scope = t->source;
    else for (int ancestor = chart->states[t->source].parent; ancestor >= 0; ancestor = chart->states[ancestor].parent) {
        if (compound(chart, ancestor) && all_descendants(chart, targets, ancestor)) {
            choice.scope = ancestor;
            break;
        }
    }
    for (int i = 0; i < chart->order_count; i++) {
        int state = chart->order[i];
        if (chart->states[state].active && descendant(chart, state, choice.scope)) choice.exits |= bit(state);
    }
    return choice;
}

static bool matches(const Transition *t, Trigger trigger) {
    if (trigger.kind == ALWAYS_TRIGGER) return t->trigger == ALWAYS_TRIGGER;
    if (trigger.kind == TIMER_TRIGGER) return t == trigger.timer;
    if (t->trigger != EVENT_TRIGGER) return false;
    for (int i = 0; i < t->descriptor_count; i++) {
        const char *d = t->descriptors[i];
        size_t length = strlen(d);
        if (equal(d, "*") || equal(d, trigger.event.name) || (starts(trigger.event.name, d) && trigger.event.name[length] == '.')) return true;
    }
    return false;
}

static void enqueue(Chart *chart, const char *name, long long value) {
    chart->queue[chart->queue_count++] = (Event){(char *)name, value};
}

static Choices select_transitions(Chart *chart, Trigger trigger) {
    Transition *candidates[40];
    int count = 0;
    for (int i = 0; i < chart->order_count; i++) {
        int state = chart->order[i];
        if (!chart->states[state].active || !atomic(chart, state)) continue;
        Transition *selected = NULL;
        for (int source = state; source != 0 && !selected; source = chart->states[source].parent) {
            State *s = &chart->states[source];
            for (int j = 0; j < s->transition_count; j++) if (matches(s->transitions[j], trigger)) {
                Transition *t = s->transitions[j];
                bool success = true;
                long long guard = t->guard ? evaluate(chart, t->guard, &success) : 1;
                if (!success) enqueue(chart, "error.execution", 0);
                if (success && guard != 0) {
                    selected = t;
                    break;
                }
            }
        }
        if (selected) {
            bool seen = false;
            for (int j = 0; j < count; j++) if (candidates[j] == selected) seen = true;
            if (!seen) candidates[count++] = selected;
        }
    }
    Choices result = {0};
    uint64_t exited = 0;
    for (int i = 0; i < count; i++) {
        Choice choice = make_choice(chart, candidates[i]);
        if (!(choice.exits & exited)) {
            result.items[result.count++] = choice;
            exited |= choice.exits;
        }
    }
    return result;
}

static void reserve(Chart *chart, Transition *timer, Event event, int delay) {
    chart->reservations[chart->reservation_count++] = (Reservation){chart->time + delay, ++chart->creations, timer, event};
}

static void remove_reservation(Chart *chart, int index) {
    memmove(chart->reservations + index, chart->reservations + index + 1, (size_t)(chart->reservation_count - index - 1) * sizeof(Reservation));
    chart->reservation_count--;
}

static void perform(Chart *chart, Actions list) {
    for (int i = 0; i < list.count; i++) {
        Action *a = &list.items[i];
        bool success = true;
        long long value = a->expression ? evaluate(chart, a->expression, &success) : 0;
        if (!success) {
            enqueue(chart, "error.execution", 0);
            return;
        }
        switch (a->kind) {
            case ASSIGN:
                chart->variables[find_variable(chart, a->name)].value = value;
                break;
            case RAISE:
                enqueue(chart, a->name, value);
                break;
            case SEND:
                reserve(chart, NULL, (Event){a->name, value}, a->delay);
                break;
            case CANCEL:
                for (int j = 0; j < chart->reservation_count;) {
                    Reservation *r = &chart->reservations[j];
                    if (!r->timer && equal(r->event.name, a->name)) remove_reservation(chart, j);
                    else j++;
                }
                break;
            case LOG:
                fputs(a->literal, stdout);
                if (a->expression) printf("%lld", value);
                putchar('\n');
                break;
        }
    }
}

static uint64_t expand(const Chart *chart, uint64_t entry) {
    uint64_t before;
    do {
        before = entry;
        for (int i = 0; i < chart->order_count; i++) {
            int state = chart->order[i];
            if (!contains(entry, state)) continue;
            const State *s = &chart->states[state];
            bool has_child = false;
            for (int j = 0; j < s->child_count; j++) {
                int child = s->children[j];
                if (chart->states[child].kind == HISTORY) continue;
                if (parallel(chart, state)) entry |= bit(child);
                if (contains(entry, child)) has_child = true;
            }
            if (compound(chart, state) && !has_child) entry |= bit(initial(chart, state));
        }
    } while (entry != before);
    return entry;
}

static bool complete(const Chart *chart, int state) {
    const State *s = &chart->states[state];
    if (compound(chart, state)) {
        for (int i = 0; i < s->child_count; i++) {
            const State *child = &chart->states[s->children[i]];
            if (child->kind == FINAL && child->active) return true;
        }
        return false;
    }
    if (!parallel(chart, state)) return false;
    for (int i = 0; i < s->child_count; i++) if (chart->states[s->children[i]].kind != HISTORY && !complete(chart, s->children[i])) return false;
    return true;
}

static void enter(Chart *chart, uint64_t entry) {
    for (int i = 0; i < chart->order_count; i++) {
        int state = chart->order[i];
        if (!contains(entry, state)) continue;
        State *s = &chart->states[state];
        s->active = true;
        s->entered++;
        s->entry_time = chart->time;
        for (int j = 0; j < s->transition_count; j++) if (s->transitions[j]->trigger == TIMER_TRIGGER) reserve(chart, s->transitions[j], (Event){0}, s->transitions[j]->delay);
        for (int j = 0; j < s->entry_count; j++) perform(chart, s->entries[j]);
        if (s->kind == FINAL) {
            int parent = s->parent;
            enqueue(chart, format("done.state.%s", chart->states[parent].name), 0);
            int grandparent = chart->states[parent].parent;
            if (grandparent >= 0 && parallel(chart, grandparent) && complete(chart, grandparent)) enqueue(chart, format("done.state.%s", chart->states[grandparent].name), 0);
        }
    }
}

static void print_states(const Chart *chart, uint64_t set, bool reverse) {
    bool any = false;
    for (int i = 0; i < chart->order_count; i++) {
        int state = chart->order[reverse ? chart->order_count - i - 1 : i];
        if (contains(set, state)) {
            if (any) putchar(',');
            fputs(chart->states[state].name, stdout);
            any = true;
        }
    }
    if (!any) putchar('-');
}

static void print_trigger(const Chart *chart, Trigger trigger) {
    if (trigger.kind == ALWAYS_TRIGGER) fputs("always", stdout);
    else if (trigger.kind == TIMER_TRIGGER) printf("after(%d)@%s", trigger.timer->delay, chart->states[trigger.timer->source].name);
    else {
        fputs(trigger.event.name, stdout);
        if (trigger.event.value != 0) printf("=%lld", trigger.event.value);
    }
}

static bool micro(Chart *chart, Choices selected, Trigger trigger) {
    if (chart->in_macro == 1000) {
        printf("LIVELOCK t=%lld\n", chart->time);
        chart->halted = true;
        return false;
    }
    chart->in_macro++;
    chart->microsteps++;
    uint64_t exits = 0;
    for (int i = 0; i < selected.count; i++) exits |= selected.items[i].exits;
    for (int i = 0; i < chart->order_count; i++) {
        State *history = &chart->states[chart->order[i]];
        if (history->kind != HISTORY || !contains(exits, history->parent)) continue;
        history->history_recorded = true;
        history->history = 0;
        for (int j = 0; j < chart->order_count; j++) {
            int state = chart->order[j];
            if (chart->states[state].active && (history->deep ? atomic(chart, state) && descendant(chart, state, history->parent) : chart->states[state].parent == history->parent && chart->states[state].kind != HISTORY)) history->history |= bit(state);
        }
    }
    uint64_t entry = 0;
    for (int i = 0; i < selected.count; i++) {
        Choice choice = selected.items[i];
        if (choice.transition->target < 0) continue;
        uint64_t targets = effective(chart, choice.transition);
        for (int j = 0; j < chart->order_count; j++) {
            int target = chart->order[j];
            if (contains(targets, target)) for (int state = target; state != choice.scope; state = chart->states[state].parent) entry |= bit(state);
        }
    }
    entry = expand(chart, entry);
    if (chart->trace) {
        printf("[t=%lld] ", chart->time);
        print_trigger(chart, trigger);
        fputs(" (", stdout);
        for (int i = 0; i < selected.count; i++) {
            if (i) putchar(',');
            fputs(chart->states[selected.items[i].transition->source].name, stdout);
        }
        fputs("): exit ", stdout);
        print_states(chart, exits, true);
        fputs("; enter ", stdout);
        print_states(chart, entry, false);
        putchar('\n');
    }
    for (int i = chart->order_count - 1; i >= 0; i--) {
        int state = chart->order[i];
        if (!contains(exits, state)) continue;
        State *s = &chart->states[state];
        for (int j = 0; j < s->exit_count; j++) perform(chart, s->exits[j]);
        s->active = false;
        s->dwell += chart->time - s->entry_time;
        for (int j = 0; j < chart->reservation_count;) {
            if (chart->reservations[j].timer && chart->reservations[j].timer->source == state) remove_reservation(chart, j);
            else j++;
        }
    }
    for (int i = 0; i < selected.count; i++) {
        Transition *t = selected.items[i].transition;
        perform(chart, t->actions);
        chart->states[t->source].taken++;
    }
    enter(chart, entry);
    return true;
}

static void macro(Chart *chart, Trigger trigger) {
    chart->macrosteps++;
    chart->in_macro = 0;
    if (trigger.kind == START_TRIGGER) {
        chart->data = 0;
        enter(chart, expand(chart, bit(initial(chart, 0))));
    } else {
        chart->data = trigger.kind == TIMER_TRIGGER ? 0 : trigger.event.value;
        Choices selected = select_transitions(chart, trigger);
        if (selected.count && !micro(chart, selected, trigger)) return;
    }
    while (!chart->halted) {
        chart->data = 0;
        Trigger always = {
            ALWAYS_TRIGGER, {0}, NULL
        };
        Choices selected = select_transitions(chart, always);
        if (selected.count) {
            if (!micro(chart, selected, always)) return;
            continue;
        }
        if (chart->queue_front == chart->queue_count) return;
        Event event = chart->queue[chart->queue_front++];
        chart->data = event.value;
        Trigger internal = {EVENT_TRIGGER, event, NULL};
        selected = select_transitions(chart, internal);
        if (selected.count && !micro(chart, selected, internal)) return;
    }
}

static int compare_reservations(const void *a, const void *b) {
    const Reservation *x = a, *y = b;
    if (x->due != y->due) return x->due < y->due ? -1 : 1;
    return (x->number > y->number) - (x->number < y->number);
}

static void dump(Chart *chart) {
    printf("dump t=%lld\n", chart->time);
    for (int i = 0; i < chart->order_count; i++) {
        State *s = &chart->states[chart->order[i]];
        if (s->active) printf("%*s%s\n", 2 * s->depth, "", s->name);
    }
    int variables[20];
    for (int i = 0; i < chart->variable_count; i++) {
        int j = i;
        while (j > 0 && strcmp(chart->variables[variables[j - 1]].name, chart->variables[i].name) > 0) {
            variables[j] = variables[j - 1];
            j--;
        }
        variables[j] = i;
    }
    for (int i = 0; i < chart->variable_count; i++) printf("  var %s = %lld\n", chart->variables[variables[i]].name, chart->variables[variables[i]].value);
    for (int i = 0; i < chart->order_count; i++) {
        State *s = &chart->states[chart->order[i]];
        if (s->kind == HISTORY && s->history_recorded) {
            printf("  history %s = ", s->name);
            print_states(chart, s->history, false);
            putchar('\n');
        }
    }
    qsort(chart->reservations, (size_t)chart->reservation_count, sizeof(Reservation), compare_reservations);
    for (int i = 0; i < chart->reservation_count; i++) {
        Reservation *r = &chart->reservations[i];
        if (r->timer) printf("  timer %lld after(%d)@%s\n", r->due, r->timer->delay, chart->states[r->timer->source].name);
        else printf("  send %lld %s %lld\n", r->due, r->event.name, r->event.value);
    }
}

static void script(Chart *chart, const char *text) {
    if (chart->halted) return;
    const char *rest = text;
    char *command = word(&rest);
    if (equal(command, "event")) {
        char *name = word(&rest);
        macro(chart, (Trigger) {
            EVENT_TRIGGER, {name, *rest ? strtoll(rest, NULL, 10) : 0}, NULL
        });
    } else if (equal(command, "tick")) {
        long long finish = chart->time + strtoll(rest, NULL, 10);
        while (!chart->halted) {
            int next = -1;
            for (int i = 0; i < chart->reservation_count; i++) {
                Reservation *r = &chart->reservations[i];
                if (r->due <= finish && (next < 0 || compare_reservations(r, &chart->reservations[next]) < 0)) next = i;
            }
            if (next < 0) break;
            Reservation r = chart->reservations[next];
            remove_reservation(chart, next);
            chart->time = r.due;
            macro(chart, (Trigger){r.timer ? TIMER_TRIGGER : EVENT_TRIGGER, r.event, r.timer});
        }
        if (!chart->halted) chart->time = finish;
    } else if (equal(command, "set")) {
        char *name = word(&rest);
        int index = find_variable(chart, name);
        if (index < 0) printf("error: unknown variable %s\n", name);
        else chart->variables[index].value = strtoll(rest, NULL, 10);
    } else if (equal(command, "trace")) chart->trace = equal(rest, "on");
    else if (equal(command, "eval")) {
        Node *n = expression(rest);
        char *error = reference(chart, n);
        if (error) printf("error: %s\n", error);
        else {
            chart->data = 0;
            bool success = true;
            long long value = evaluate(chart, n, &success);
            if (!success) puts("error: division by zero");
            else printf("%s -> %lld\n", rest, value);
        }
    } else if (equal(command, "dump")) dump(chart);
}

static void statistics(const Chart *chart) {
    printf("end t=%lld macrosteps=%lld microsteps=%lld\n", chart->time, chart->macrosteps, chart->microsteps);
    for (int i = 0; i < chart->order_count; i++) {
        const State *s = &chart->states[chart->order[i]];
        if (s->kind != HISTORY) printf("  %s entered=%lld taken=%lld time=%lld\n", s->name, s->entered, s->taken, s->dwell + (s->active ? chart->time - s->entry_time : 0));
    }
}

int main(void) {
    char *line = read_line();
    int count = atoi(line), number = 1;
    free(line);
    for (int chart_index = 0; chart_index < count; chart_index++) {
        line = read_line();
        number++;
        printf("chart %s\n", line + 6);
        free(line);
        Definition definitions[120] = {0};
        int definition_count = 0, script_count = 0;
        char *commands[300];
        while (true) {
            line = read_line();
            number++;
            if (equal(line, "RUN")) {
                free(line);
                break;
            }
            definitions[definition_count++] = (Definition){number, copy_string(line), NULL, -1};
            free(line);
        }
        while (true) {
            line = read_line();
            number++;
            if (equal(line, "END")) {
                free(line);
                break;
            }
            commands[script_count++] = copy_string(line);
            free(line);
        }
        Chart *chart = allocate(sizeof(*chart));
        chart->state_count = 1;
        chart->states[0].name = "";
        chart->states[0].parent = -1;
        if (define(chart, definitions, definition_count)) {
            warnings(chart);
            macro(chart, (Trigger) {
                START_TRIGGER, {0}, NULL
            });
            for (int i = 0; i < script_count; i++) script(chart, commands[i]);
            statistics(chart);
        }
        release_chart();
    }
    return 0;
}
