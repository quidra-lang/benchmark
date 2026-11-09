#include "parser.h"
typedef struct {
    const char *symbol;
    Tree *node;
} Entry;
static void stack_push(Entry **stack, int *n, int *capacity, Entry entry) {
    if (*n == *capacity) {
        const int size = *capacity ? *capacity * 2 : 16;
        *stack = grow(*stack, (size_t)*n * sizeof **stack, (size_t)size * sizeof **stack);
        *capacity = size;
    }
    (*stack)[(*n)++] = entry;
}
static void step_add(Parse *out, Step step) {
    if (out->nsteps == out->capacity) {
        const int capacity = out->capacity ? out->capacity * 2 : 32;
        out->steps =
            grow(out->steps, (size_t)out->nsteps * sizeof *out->steps, (size_t)capacity * sizeof *out->steps);
        out->capacity = capacity;
    }
    out->steps[out->nsteps++] = step;
}
Parse drive(const Grammar *grammar, const Sets *sets, const Table *table, const InputToken *input,
            int ntokens) {
    InputToken *tokens = allocate((size_t)(ntokens + 1) * sizeof *tokens);
    if (ntokens)
        memcpy(tokens, input, (size_t)ntokens * sizeof *tokens);
    tokens[ntokens] = (InputToken){"$", 0};
    Parse out = {0};
    out.tree = allocate(sizeof *out.tree);
    out.tree->symbol = grammar->start;
    Entry *stack = NULL;
    int nstack = 0, stack_capacity = 0;
    stack_push(&stack, &nstack, &stack_capacity, (Entry){"$", NULL});
    stack_push(&stack, &nstack, &stack_capacity, (Entry){grammar->start, out.tree});
    int current = 0;
    while (true) {
        Step step = {.production = -1};
        for (int i = 0; i < nstack; ++i)
            strings_add(&step.stack, stack[i].symbol);
        for (int i = current; i <= ntokens; ++i)
            strings_add(&step.input, tokens[i].name);
        if (nstack > out.max_stack)
            out.max_stack = nstack;
        const Entry top = stack[nstack - 1];
        step.top = top.symbol;
        step.current = tokens[current].name;
        step.position = tokens[current].position;
        if (strcmp(top.symbol, "$") == 0 && strcmp(step.current, "$") == 0) {
            step.action = ACCEPT;
            step_add(&out, step);
            break;
        }
        if (strcmp(top.symbol, "$") == 0) {
            step.action = SKIP;
            ++out.skip;
            ++current;
        } else if (!nonterminal(top.symbol)) {
            --nstack;
            if (strcmp(top.symbol, step.current) == 0) {
                step.action = MATCH;
                ++out.matches;
                ++current;
            } else {
                step.action = MISSING;
                ++out.missing;
                top.node->mark = "missing";
            }
        } else {
            const int lhs = rule_index(grammar, top.symbol), terminal = terminal_index(table, step.current),
                      chosen = table->chosen[lhs * table->terminals.n + terminal];
            if (chosen >= 0) {
                step.action = PREDICT;
                step.production = chosen;
                ints_add(&out.left_parse, chosen);
                --nstack;
                const Strings rhs = table->productions[chosen].rhs;
                if (!rhs.n) {
                    top.node->children = allocate(sizeof *top.node->children);
                    top.node->nchildren = 1;
                    top.node->children[0] = allocate(sizeof(Tree));
                    top.node->children[0]->symbol = "%empty";
                } else {
                    top.node->children = allocate((size_t)rhs.n * sizeof *top.node->children);
                    top.node->nchildren = rhs.n;
                    for (int i = 0; i < rhs.n; ++i) {
                        top.node->children[i] = allocate(sizeof(Tree));
                        top.node->children[i]->symbol = rhs.v[i];
                    }
                    for (int i = rhs.n - 1; i >= 0; --i)
                        stack_push(&stack, &nstack, &stack_capacity,
                                   (Entry){rhs.v[i], top.node->children[i]});
                }
            } else if (strcmp(step.current, "$") == 0 || strings_has(sets->follow[lhs], step.current)) {
                step.action = POP;
                ++out.pop;
                top.node->mark = "error";
                --nstack;
            } else {
                step.action = SKIP;
                ++out.skip;
                ++current;
            }
        }
        step_add(&out, step);
    }
    return out;
}
