#include <ctype.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int number, count;
    char *words[64];
} Line;
typedef struct {
    char *port, *signal;
} Connection;
typedef struct {
    char *name, *output, *inputs[8];
    int type, count, delay;
} Gate;
typedef struct {
    int instance, module, line, count;
    char *name;
    Gate gate;
    Connection connections[50];
} Body;
typedef struct {
    int input_count, output_count, gate_count, signal_count, order_count, dff_count;
    char *inputs[50], *outputs[50], *signals[550];
    Gate gates[500];
    int in[500][8], out[500], output_indices[50], driver[550], order[500];
    int *readers[550], reader_count[550];
} Circuit;
typedef struct {
    char *name, *inputs[50], *outputs[50];
    int input_count, output_count, count, gates, instances;
    Body *body;
    Circuit *circuit;
} Module;
typedef struct {
    long long time, serial;
    int signal;
    char value;
} Event;
typedef struct {
    long long time;
    char value;
} Change;
typedef struct {
    Change *items;
    size_t count, capacity;
} History;

static const char *types[] = {"AND",  "OR",  "NAND", "NOR",  "XOR",
                              "XNOR", "NOT", "BUF",  "MUX2", "DFF"};
static Module modules[1000];
static int module_count, error_line;
static jmp_buf command_end;
static Circuit *simulation;
static char *simulation_name;
static char values[550];
static int watched[550], watch_count, halted;
static History history[550];
static Event *events;
static size_t event_count, event_capacity;
static long long now, processed, serial;

static void error(const char *format, ...) {
    va_list args;
    printf("error: line %d: ", error_line);
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    putchar('\n');
    longjmp(command_end, 1);
}

static char *copy(const char *s) {
    char *result = malloc(strlen(s) + 1);
    if (!result)
        exit(1);
    strcpy(result, s);
    return result;
}

static char *join(const char *a, const char *b, const char *c) {
    char *result = malloc(strlen(a) + strlen(b) + strlen(c) + 1);
    if (!result)
        exit(1);
    strcpy(result, a);
    strcat(result, b);
    strcat(result, c);
    return result;
}

static int index_of(char **items, int n, const char *value) {
    for (int i = 0; i < n; ++i)
        if (!strcmp(items[i], value))
            return i;
    return -1;
}

static int module_index(const char *name) {
    for (int i = 0; i < module_count; ++i)
        if (!strcmp(modules[i].name, name))
            return i;
    return -1;
}

static int gate_type(const char *name) {
    for (int i = 0; i < 10; ++i)
        if (!strcmp(types[i], name))
            return i;
    return -1;
}

static int name_valid(const char *word, int upper) {
    size_t n = strlen(word);
    if (!n || n > 16 || word[0] < (upper ? 'A' : 'a') || word[0] > (upper ? 'Z' : 'z'))
        return 0;
    for (size_t i = 1; i < n; ++i)
        if (!((word[i] >= (upper ? 'A' : 'a') && word[i] <= (upper ? 'Z' : 'z')) ||
              isdigit((unsigned char)word[i]) || word[i] == '_'))
            return 0;
    return 1;
}

static int is_number(const char *word) {
    size_t n = strlen(word);
    if (!n || n > 9 || (n > 1 && word[0] == '0'))
        return 0;
    for (size_t i = 0; i < n; ++i)
        if (word[i] < '0' || word[i] > '9')
            return 0;
    return 1;
}

static long long number(const char *word, int positive) {
    if (!is_number(word) || (positive && !strcmp(word, "0")))
        error("bad number %s", word);
    return strtoll(word, NULL, 10);
}

static char value(const char *word) {
    if (strlen(word) != 1 || !strchr("01X", word[0]))
        error("bad value %s", word);
    return word[0];
}

static int reads(Circuit *c, int g, int s) {
    for (int i = 0; i < c->gates[g].count; ++i)
        if (c->in[g][i] == s)
            return 1;
    return 0;
}

static void prepare_circuit(Circuit *c) {
    c->signal_count = c->input_count + c->gate_count;
    for (int i = 0; i < c->input_count; ++i)
        c->signals[i] = c->inputs[i];
    for (int i = 0; i < c->gate_count; ++i)
        c->signals[c->input_count + i] = c->gates[i].output;
    for (int s = 0; s < c->signal_count; ++s)
        c->driver[s] = s < c->input_count ? -1 : s - c->input_count;
    for (int g = 0; g < c->gate_count; ++g) {
        c->out[g] = c->input_count + g;
        for (int i = 0; i < c->gates[g].count; ++i)
            c->in[g][i] = index_of(c->signals, c->signal_count, c->gates[g].inputs[i]);
        if (c->gates[g].type == 9)
            ++c->dff_count;
    }
    for (int i = 0; i < c->output_count; ++i)
        c->output_indices[i] = index_of(c->signals, c->signal_count, c->outputs[i]);
    for (int s = 0; s < c->signal_count; ++s) {
        for (int g = 0; g < c->gate_count; ++g)
            if (reads(c, g, s))
                ++c->reader_count[s];
        c->readers[s] = malloc((size_t)(c->reader_count[s] + 1) * sizeof(int));
        int n = 0;
        for (int g = 0; g < c->gate_count; ++g)
            if (reads(c, g, s))
                c->readers[s][n++] = g;
    }
    int done[500] = {0}, progress = 1;
    while (progress) {
        progress = 0;
        for (int g = 0; g < c->gate_count; ++g)
            if (!done[g] && c->gates[g].type != 9) {
                int ready = 1;
                for (int i = 0; i < c->gates[g].count; ++i) {
                    int source = c->driver[c->in[g][i]];
                    if (source >= 0 && c->gates[source].type != 9 && !done[source])
                        ready = 0;
                }
                if (ready) {
                    done[g] = 1;
                    c->order[c->order_count++] = g;
                    progress = 1;
                }
            }
    }
}

static char *mapped(Body *body, const char *signal) {
    for (int i = 0; i < body->count; ++i)
        if (!strcmp(body->connections[i].port, signal))
            return body->connections[i].signal;
    return join(body->name, ".", signal);
}

static Circuit *flatten(Module *m) {
    Circuit *c = calloc(1, sizeof *c);
    c->input_count = m->input_count;
    c->output_count = m->output_count;
    memcpy(c->inputs, m->inputs, sizeof c->inputs);
    memcpy(c->outputs, m->outputs, sizeof c->outputs);
    for (int i = 0; i < m->count; ++i) {
        Body *b = &m->body[i];
        if (!b->instance)
            c->gates[c->gate_count++] = b->gate;
        else {
            Circuit *child = modules[b->module].circuit;
            for (int j = 0; j < child->gate_count; ++j) {
                Gate g = child->gates[j];
                g.name = join(b->name, ".", g.name);
                g.output = mapped(b, g.output);
                for (int k = 0; k < g.count; ++k)
                    g.inputs[k] = mapped(b, g.inputs[k]);
                c->gates[c->gate_count++] = g;
            }
        }
    }
    prepare_circuit(c);
    return c;
}

static void define_module(Line *lines, int first, int end) {
    Line *header = &lines[first];
    char **w = header->words;
    int n = header->count, out = -1, outs = 0;
    for (int i = 3; i < n; ++i)
        if (!strcmp(w[i], "OUT")) {
            out = i;
            ++outs;
        }
    if (n < 5 || strcmp(w[2], "IN") || outs != 1 || out == n - 1)
        error("bad module header");
    if (!name_valid(w[1], 1))
        error("bad module name %s", w[1]);
    if (module_index(w[1]) >= 0)
        error("duplicate module %s", w[1]);
    Module m = {0};
    m.name = w[1];
    m.input_count = out - 3;
    m.output_count = n - out - 1;
    char *ports[100], *driven[50000], *used[1000];
    int port_count = 0, driven_count = 0, used_count = 0;
    for (int i = 3; i < n; ++i)
        if (i != out) {
            if (!name_valid(w[i], 0))
                error("bad name %s", w[i]);
            if (index_of(ports, port_count, w[i]) >= 0)
                error("duplicate port %s", w[i]);
            ports[port_count++] = w[i];
            if (i < out) {
                m.inputs[i - 3] = w[i];
                driven[driven_count++] = w[i];
            } else
                m.outputs[i - out - 1] = w[i];
        }
    m.body = calloc((size_t)(end - first), sizeof *m.body);
    for (int l = first + 1; l < end; ++l) {
        error_line = lines[l].number;
        w = lines[l].words;
        n = lines[l].count;
        Body *b = &m.body[m.count++];
        b->line = error_line;
        int type = gate_type(w[0]);
        if (type >= 0) {
            int arrows = 0;
            for (int i = 0; i < n; ++i)
                arrows += !strcmp(w[i], "->");
            if (n < 5 || strcmp(w[n - 3], "->") || arrows != 1)
                error("bad gate syntax");
            if (!name_valid(w[1], 0))
                error("bad name %s", w[1]);
            int count = n - 5, minimum = type < 6 ? 2 : type == 8 ? 3 : type == 9 ? 2 : 1;
            int maximum = type < 6 ? 8 : minimum;
            if (count < minimum || count > maximum)
                error("bad input count %d for %s", count, w[0]);
            for (int i = 2; i < n - 3; ++i)
                if (!name_valid(w[i], 0))
                    error("bad name %s", w[i]);
            if (!name_valid(w[n - 2], 0))
                error("bad name %s", w[n - 2]);
            if (!is_number(w[n - 1]) || strtoll(w[n - 1], NULL, 10) > 1000)
                error("bad delay %s", w[n - 1]);
            if (index_of(used, used_count, w[1]) >= 0)
                error("duplicate name %s", w[1]);
            if (index_of(driven, driven_count, w[n - 2]) >= 0)
                error("multiple drivers for %s", w[n - 2]);
            b->name = w[1];
            b->gate = (Gate){.name = w[1],
                             .output = w[n - 2],
                             .type = type,
                             .count = count,
                             .delay = atoi(w[n - 1])};
            for (int i = 0; i < count; ++i)
                b->gate.inputs[i] = w[i + 2];
            driven[driven_count++] = b->gate.output;
            ++m.gates;
        } else if (!strcmp(w[0], "INST")) {
            if (n < 3)
                error("bad instance syntax");
            if (!name_valid(w[1], 0))
                error("bad name %s", w[1]);
            int child = module_index(w[2]);
            if (child < 0)
                error("unknown module %s", w[2]);
            Module *target = &modules[child];
            b->instance = 1;
            b->name = w[1];
            b->module = child;
            for (int i = 3; i < n; ++i) {
                char *equal = strchr(w[i], '=');
                if (!equal || equal == w[i] || !equal[1] || strchr(equal + 1, '='))
                    error("bad connection %s", w[i]);
                char *port = copy(w[i]);
                port[equal - w[i]] = 0;
                char *signal = equal + 1;
                if (index_of(target->inputs, target->input_count, port) < 0 &&
                    index_of(target->outputs, target->output_count, port) < 0)
                    error("unknown port %s", port);
                for (int k = 0; k < b->count; ++k)
                    if (!strcmp(b->connections[k].port, port))
                        error("duplicate connection %s", port);
                if (!name_valid(signal, 0))
                    error("bad name %s", signal);
                b->connections[b->count++] = (Connection){port, signal};
            }
            for (int i = 0; i < target->input_count; ++i) {
                int found = 0;
                for (int j = 0; j < b->count; ++j)
                    if (!strcmp(target->inputs[i], b->connections[j].port))
                        found = 1;
                if (!found)
                    error("unconnected input %s", target->inputs[i]);
            }
            if (index_of(used, used_count, b->name) >= 0)
                error("duplicate name %s", b->name);
            for (int j = 0; j < b->count; ++j)
                if (index_of(target->outputs, target->output_count, b->connections[j].port) >= 0) {
                    char *s = b->connections[j].signal;
                    if (index_of(driven, driven_count, s) >= 0)
                        error("multiple drivers for %s", s);
                    driven[driven_count++] = s;
                }
            ++m.instances;
        } else
            error("unknown statement %s", w[0]);
        used[used_count++] = b->name;
    }
    for (int i = 0; i < m.count; ++i) {
        Body *b = &m.body[i];
        error_line = b->line;
        if (!b->instance) {
            for (int j = 0; j < b->gate.count; ++j)
                if (index_of(driven, driven_count, b->gate.inputs[j]) < 0)
                    error("undriven signal %s", b->gate.inputs[j]);
        } else {
            Module *target = &modules[b->module];
            for (int j = 0; j < b->count; ++j)
                if (index_of(target->inputs, target->input_count, b->connections[j].port) >= 0 &&
                    index_of(driven, driven_count, b->connections[j].signal) < 0)
                    error("undriven signal %s", b->connections[j].signal);
        }
    }
    error_line = header->number;
    for (int i = 0; i < m.output_count; ++i)
        if (index_of(driven, driven_count, m.outputs[i]) < 0)
            error("undriven signal %s", m.outputs[i]);
    m.circuit = flatten(&m);
    modules[module_count++] = m;
    printf("defined %s inputs %d outputs %d gates %d instances %d\n", m.name, m.input_count,
           m.output_count, m.gates, m.instances);
}

static char gate_value(Gate *g, const char *v) {
    char result = 'X';
    int zeros = 0, ones = 0, unknowns = 0;
    for (int i = 0; i < g->count; ++i) {
        zeros += v[i] == '0';
        ones += v[i] == '1';
        unknowns += v[i] == 'X';
    }
    switch (g->type) {
    case 0:
    case 2:
        result = zeros ? '0' : unknowns ? 'X' : '1';
        break;
    case 1:
    case 3:
        result = ones ? '1' : unknowns ? 'X' : '0';
        break;
    case 4:
    case 5:
        result = unknowns ? 'X' : (char)('0' + ones % 2);
        break;
    case 6:
    case 7:
        result = v[0];
        break;
    case 8:
        result = v[0] == '0' ? v[1] : v[0] == '1' ? v[2] : v[1] == v[2] ? v[1] : 'X';
        break;
    }
    if ((g->type == 2 || g->type == 3 || g->type == 5 || g->type == 6) && result != 'X')
        result = result == '0' ? '1' : '0';
    return result;
}

static void bits(int row, int width, char *result) {
    for (int i = 0; i < width; ++i)
        result[i] = (char)('0' + ((row >> (width - i - 1)) & 1));
    result[width] = 0;
}

static void evaluate(Circuit *c, int row, int fault, char stuck, char *result) {
    char v[550], input[51];
    bits(row, c->input_count, input);
    for (int i = 0; i < c->input_count; ++i)
        v[i] = i == fault ? stuck : input[i];
    for (int i = 0; i < c->order_count; ++i) {
        int g = c->order[i], output = c->out[g];
        char args[8];
        for (int j = 0; j < c->gates[g].count; ++j)
            args[j] = v[c->in[g][j]];
        v[output] = output == fault ? stuck : gate_value(&c->gates[g], args);
    }
    for (int i = 0; i < c->output_count; ++i)
        result[i] = v[c->output_indices[i]];
    result[c->output_count] = 0;
}

static Circuit *get_circuit(const char *name) {
    int i = module_index(name);
    if (i < 0)
        error("unknown module %s", name);
    return modules[i].circuit;
}

static int has_loop(Circuit *c) {
    return c->order_count + c->dff_count != c->gate_count;
}

static void check_combinational(Circuit *c, const char *name) {
    if (c->dff_count)
        error("%s is not combinational", name);
    if (has_loop(c))
        error("%s has a combinational loop", name);
    if (c->input_count > 8)
        error("too many inputs %d", c->input_count);
}

static void hierarchy(int module, int depth) {
    Module *m = &modules[module];
    for (int i = 0; i < m->count; ++i)
        if (m->body[i].instance) {
            Body *b = &m->body[i];
            printf("%*s%s %s\n", 2 * depth, "", b->name, modules[b->module].name);
            hierarchy(b->module, depth + 1);
        }
}

static void path(Circuit *c, int *previous, int endpoint) {
    int reverse[550], n = 0;
    for (int s = endpoint; s >= 0; s = previous[s])
        reverse[n++] = s;
    for (int i = n - 1; i >= 0; --i)
        printf("%s%s", i == n - 1 ? "" : " -> ", c->signals[reverse[i]]);
    putchar('\n');
}

static void timing(Circuit *c, const char *name, int period) {
    if (period && !c->dff_count)
        error("%s has no flip-flops", name);
    if (has_loop(c))
        error("%s has a combinational loop", name);
    long long latest[550], earliest[550];
    int previous[550];
    for (int s = 0; s < c->signal_count; ++s) {
        latest[s] = earliest[s] = -1;
        previous[s] = -1;
    }
    if (!period)
        for (int s = 0; s < c->input_count; ++s)
            latest[s] = earliest[s] = 0;
    if (period)
        for (int g = 0; g < c->gate_count; ++g)
            if (c->gates[g].type == 9)
                latest[c->out[g]] = earliest[c->out[g]] = c->gates[g].delay;
    for (int i = 0; i < c->order_count; ++i) {
        int g = c->order[i], s = c->out[g];
        for (int j = 0; j < c->gates[g].count; ++j) {
            int source = c->in[g][j];
            if (latest[source] < 0)
                continue;
            long long l = latest[source] + c->gates[g].delay,
                      e = earliest[source] + c->gates[g].delay;
            if (l > latest[s]) {
                latest[s] = l;
                previous[s] = source;
            }
            if (earliest[s] < 0 || e < earliest[s])
                earliest[s] = e;
        }
    }
    int endpoint = -1;
    if (period) {
        for (int g = 0; g < c->gate_count; ++g)
            if (c->gates[g].type == 9) {
                int s = c->in[g][1];
                if (latest[s] >= 0 && (endpoint < 0 || latest[s] > latest[endpoint]))
                    endpoint = s;
            }
        printf("flip-flops %d period ", c->dff_count);
        if (endpoint < 0)
            puts("none");
        else {
            printf("%lld: ", latest[endpoint]);
            path(c, previous, endpoint);
        }
    } else {
        for (int i = 0; i < c->output_count; ++i) {
            int s = c->output_indices[i];
            if (latest[s] < 0)
                printf("%s unreachable\n", c->outputs[i]);
            else {
                printf("%s min %lld max %lld\n", c->outputs[i], earliest[s], latest[s]);
                if (endpoint < 0 || latest[s] > latest[endpoint])
                    endpoint = s;
            }
        }
        if (endpoint < 0)
            puts("critical none");
        else {
            printf("critical %lld: ", latest[endpoint]);
            path(c, previous, endpoint);
        }
    }
}

static void inspect(int command, char **a) {
    if (command == 16) {
        printf("modules %d\n", module_count);
        for (int i = 0; i < module_count; ++i)
            printf("%s inputs %d outputs %d gates %d\n", modules[i].name, modules[i].input_count,
                   modules[i].output_count, modules[i].circuit->gate_count);
        return;
    }
    Circuit *c = get_circuit(a[0]);
    if (command == 17) {
        printf("netlist %s gates %d signals %d\n", a[0], c->gate_count, c->signal_count);
        for (int i = 0; i < c->gate_count; ++i) {
            Gate *g = &c->gates[i];
            printf("%s %s", g->name, types[g->type]);
            for (int j = 0; j < g->count; ++j)
                printf(" %s", g->inputs[j]);
            printf(" -> %s %d\n", g->output, g->delay);
        }
    } else if (command == 18) {
        puts(a[0]);
        hierarchy(module_index(a[0]), 1);
    } else if (command == 19) {
        int levels[550] = {0}, depth = 0, counts[10] = {0}, max_fanout = 0;
        for (int g = 0; g < c->gate_count; ++g)
            ++counts[c->gates[g].type];
        for (int i = 0; i < c->order_count; ++i) {
            int g = c->order[i], level = 0;
            for (int j = 0; j < c->gates[g].count; ++j)
                if (levels[c->in[g][j]] > level)
                    level = levels[c->in[g][j]];
            levels[c->out[g]] = level + 1;
            if (level + 1 > depth)
                depth = level + 1;
        }
        for (int s = 1; s < c->signal_count; ++s)
            if (c->reader_count[s] > c->reader_count[max_fanout])
                max_fanout = s;
        printf("stats %s gates %d signals %d depth ", a[0], c->gate_count, c->signal_count);
        if (has_loop(c))
            puts("-");
        else
            printf("%d\n", depth);
        printf("types");
        for (int i = 0; i < 10; ++i)
            if (counts[i])
                printf(" %s %d", types[i], counts[i]);
        printf("\nmax fanout %s %d\n", c->signals[max_fanout], c->reader_count[max_fanout]);
    } else if (command == 23 || command == 24)
        timing(c, a[0], command == 24);
    else if (command == 21) {
        Circuit *other = get_circuit(a[1]);
        check_combinational(c, a[0]);
        check_combinational(other, a[1]);
        if (c->input_count != other->input_count || c->output_count != other->output_count)
            error("port mismatch");
        char left[51], right[51], input[51];
        for (int r = 0; r < (1 << c->input_count); ++r) {
            evaluate(c, r, -1, 'X', left);
            evaluate(other, r, -1, 'X', right);
            if (strcmp(left, right)) {
                bits(r, c->input_count, input);
                printf("not equivalent at %s: %s vs %s\n", input, left, right);
                return;
            }
        }
        puts("equivalent");
    } else {
        check_combinational(c, a[0]);
        char outputs[256][51], input[51];
        int rows = 1 << c->input_count;
        for (int r = 0; r < rows; ++r)
            evaluate(c, r, -1, 'X', outputs[r]);
        if (command == 20) {
            for (int i = 0; i < c->input_count; ++i)
                printf("%s ", c->inputs[i]);
            putchar('|');
            for (int i = 0; i < c->output_count; ++i)
                printf(" %s", c->outputs[i]);
            putchar('\n');
            for (int r = 0; r < rows; ++r) {
                bits(r, c->input_count, input);
                for (int i = 0; i < c->input_count; ++i)
                    printf("%c ", input[i]);
                putchar('|');
                for (int i = 0; i < c->output_count; ++i)
                    printf(" %c", outputs[r][i]);
                putchar('\n');
            }
        } else {
            int found[550][2], tests[256] = {0}, detected = 0;
            for (int s = 0; s < c->signal_count; ++s)
                for (int v = 0; v < 2; ++v) {
                    found[s][v] = -1;
                    for (int r = 0; r < rows; ++r) {
                        char faulty[51];
                        evaluate(c, r, s, (char)('0' + v), faulty);
                        if (strcmp(faulty, outputs[r])) {
                            found[s][v] = r;
                            tests[r] = 1;
                            ++detected;
                            break;
                        }
                    }
                }
            printf("faults %d detected %d\n", 2 * c->signal_count, detected);
            for (int s = 0; s < c->signal_count; ++s)
                for (int v = 0; v < 2; ++v)
                    if (found[s][v] < 0)
                        printf("undetected %s/%d\n", c->signals[s], v);
            printf("tests");
            for (int r = 0; r < rows; ++r)
                if (tests[r]) {
                    bits(r, c->input_count, input);
                    printf(" %s", input);
                }
            putchar('\n');
        }
    }
}

static int event_before(Event a, Event b) {
    return a.time < b.time || (a.time == b.time && a.serial < b.serial);
}

static void schedule(long long time, int signal, char v) {
    if (event_count == event_capacity) {
        event_capacity = event_capacity ? 2 * event_capacity : 128;
        Event *grown = realloc(events, event_capacity * sizeof *events);
        if (!grown)
            exit(1);
        events = grown;
    }
    Event event = {time, serial++, signal, v};
    size_t i = event_count++;
    while (i && event_before(event, events[(i - 1) / 2])) {
        events[i] = events[(i - 1) / 2];
        i = (i - 1) / 2;
    }
    events[i] = event;
}

static Event pop_event(void) {
    Event first = events[0], last = events[--event_count];
    if (event_count) {
        size_t i = 0;
        while (2 * i + 1 < event_count) {
            size_t child = 2 * i + 1;
            if (child + 1 < event_count && event_before(events[child + 1], events[child]))
                ++child;
            if (!event_before(events[child], last))
                break;
            events[i] = events[child];
            i = child;
        }
        events[i] = last;
    }
    return first;
}

static void record(int s, long long time) {
    History *h = &history[s];
    if (h->count == h->capacity) {
        h->capacity = h->capacity ? h->capacity * 2 : 16;
        Change *grown = realloc(h->items, h->capacity * sizeof *h->items);
        if (!grown)
            exit(1);
        h->items = grown;
    }
    h->items[h->count++] = (Change){time, values[s]};
}

static void reset(void) {
    now = processed = serial = 0;
    event_count = 0;
    halted = 0;
    memset(values, 'X', sizeof values);
    for (int s = 0; s < 550; ++s)
        history[s].count = 0;
}

static void run(long long time) {
    if (time <= now)
        error("time %lld is not after %lld", time, now);
    long long command_events = 0, glitches = 0;
    Circuit *c = simulation;
    while (event_count && events[0].time < time) {
        long long step_time = events[0].time;
        char before[550];
        int changed[550] = {0}, step_count = 0;
        memcpy(before, values, sizeof before);
        while (event_count && events[0].time == step_time) {
            if (step_count == 1000) {
                printf("halted: oscillation at time %lld\n", step_time);
                event_count = 0;
                now = step_time;
                halted = 1;
                return;
            }
            Event e = pop_event();
            ++step_count;
            ++command_events;
            ++processed;
            int s = e.signal;
            char old = values[s];
            if (old == e.value)
                continue;
            values[s] = e.value;
            changed[s] = 1;
            for (int i = 0; i < c->reader_count[s]; ++i) {
                int g = c->readers[s][i];
                Gate *gate = &c->gates[g];
                if (gate->type == 9) {
                    if (c->in[g][0] == s && old == '0' && e.value == '1')
                        schedule(step_time + gate->delay, c->out[g], values[c->in[g][1]]);
                } else {
                    char args[8];
                    for (int j = 0; j < gate->count; ++j)
                        args[j] = values[c->in[g][j]];
                    schedule(step_time + gate->delay, c->out[g], gate_value(gate, args));
                }
            }
        }
        for (int s = 0; s < c->signal_count; ++s) {
            if (values[s] != before[s])
                record(s, step_time);
            else if (changed[s])
                ++glitches;
        }
        for (int i = 0; i < watch_count; ++i) {
            int s = watched[i];
            if (values[s] != before[s])
                printf("%lld %s %c\n", step_time, c->signals[s], values[s]);
        }
    }
    now = time;
    printf("run %lld events %lld glitches %lld pending %zu\n", time, command_events, glitches,
           event_count);
}

static int signal_index(const char *name, int input) {
    int s = index_of(simulation->signals,
                     input ? simulation->input_count : simulation->signal_count, name);
    if (s < 0)
        error(input ? "not an input %s" : "unknown signal %s", name);
    return s;
}

static long long stimulus_time(const char *word) {
    long long time = number(word, 0);
    if (time < now)
        error("time %lld is in the past", time);
    return time;
}

static void show_watches(void) {
    printf("watching");
    if (!watch_count)
        printf(" nothing");
    for (int i = 0; i < watch_count; ++i)
        printf(" %s", simulation->signals[watched[i]]);
    putchar('\n');
}

static int activity_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    if (history[x].count != history[y].count)
        return history[x].count > history[y].count ? -1 : 1;
    return strcmp(simulation->signals[x], simulation->signals[y]);
}

static void execute(Line *line) {
    const char *commands[] = {"BUILD",      "RESET",   "SET",     "APPLY",     "PULSE",
                              "CLOCK",      "RUN",     "WATCH",   "UNWATCH",   "SHOW",
                              "CHECK",      "PROBE",   "WAVE",    "HISTORY",   "ACTIVITY",
                              "STATUS",     "MODULES", "NETLIST", "HIERARCHY", "STATS",
                              "TRUTHTABLE", "EQUIV",   "FAULTS",  "CRITICAL",  "PERIOD"};
    const int counts[] = {1, 0, 3, 2, 3, 4, 1, 1, 1, 0, 2, 1, 2,
                          1, 1, 0, 0, 1, 1, 1, 1, 2, 1, 1, 1};
    int id = -1, n = line->count - 1;
    char **a = line->words + 1;
    for (int i = 0; i < 25; ++i)
        if (!strcmp(line->words[0], commands[i]))
            id = i;
    if (id < 0)
        error("unknown command %s", line->words[0]);
    if ((id == 7 || id == 8 || id == 9) ? n < counts[id] : n != counts[id])
        error("wrong argument count");
    if (id >= 1 && id <= 15 && !simulation)
        error("no circuit");
    if (id >= 2 && id <= 6 && halted)
        error("simulation halted");
    if (id >= 16) {
        inspect(id, a);
        return;
    }
    if (id == 0) {
        Circuit *c = get_circuit(a[0]);
        simulation = c;
        simulation_name = modules[module_index(a[0])].name;
        watch_count = 0;
        reset();
        printf("built %s signals %d gates %d\n", a[0], c->signal_count, c->gate_count);
    } else if (id == 1) {
        reset();
        puts("reset");
    } else if (id == 2) {
        long long t = stimulus_time(a[0]);
        int s = signal_index(a[1], 1);
        char v = value(a[2]);
        schedule(t, s, v);
        printf("set %s %c at %lld\n", a[1], v, t);
    } else if (id == 3) {
        long long t = stimulus_time(a[0]);
        if ((int)strlen(a[1]) != simulation->input_count || strspn(a[1], "01X") != strlen(a[1]))
            error("bad vector %s", a[1]);
        for (int i = 0; i < simulation->input_count; ++i)
            schedule(t, i, a[1][i]);
        printf("apply %s at %lld\n", a[1], t);
    } else if (id == 4) {
        int s = signal_index(a[0], 1);
        long long t = stimulus_time(a[1]), width = number(a[2], 1);
        schedule(t, s, '1');
        schedule(t + width, s, '0');
        printf("pulse %s %lld %lld\n", a[0], t, t + width);
    } else if (id == 5) {
        int s = signal_index(a[0], 1);
        long long start = stimulus_time(a[1]), half = number(a[2], 1), count = number(a[3], 1);
        for (long long i = 0; i < count; ++i)
            schedule(start + i * half, s, (char)('0' + i % 2));
        printf("clock %s events %lld last %lld\n", a[0], count, start + (count - 1) * half);
    } else if (id == 6)
        run(number(a[0], 0));
    else if (id == 7 || id == 8) {
        int selected[64];
        for (int i = 0; i < n; ++i) {
            int s = signal_index(a[i], 0), in_watch = 0, duplicate = 0;
            for (int j = 0; j < watch_count; ++j)
                in_watch |= watched[j] == s;
            for (int j = 0; j < i; ++j)
                duplicate |= selected[j] == s;
            if (id == 7 && (in_watch || duplicate))
                error("already watched %s", a[i]);
            if (id == 8 && (!in_watch || duplicate))
                error("not watched %s", a[i]);
            selected[i] = s;
        }
        if (id == 7)
            for (int i = 0; i < n; ++i)
                watched[watch_count++] = selected[i];
        else {
            int retained = 0;
            for (int i = 0; i < watch_count; ++i) {
                int remove = 0;
                for (int j = 0; j < n; ++j)
                    remove |= watched[i] == selected[j];
                if (!remove)
                    watched[retained++] = watched[i];
            }
            watch_count = retained;
        }
        show_watches();
    } else if (id == 9) {
        if (n) {
            int selected[64];
            for (int i = 0; i < n; ++i)
                selected[i] = signal_index(a[i], 0);
            for (int i = 0; i < n; ++i)
                printf("%s%s=%c", i ? " " : "", a[i], values[selected[i]]);
        } else {
            for (int i = 0; i < simulation->input_count; ++i)
                printf("%s=%c ", simulation->inputs[i], values[i]);
            putchar('|');
            for (int i = 0; i < simulation->output_count; ++i)
                printf(" %s=%c", simulation->outputs[i], values[simulation->output_indices[i]]);
        }
        putchar('\n');
    } else if (id == 10) {
        int s = signal_index(a[0], 0);
        char v = value(a[1]);
        printf("check %s=%c ", a[0], v);
        if (values[s] == v)
            puts("ok");
        else
            printf("failed (%c)\n", values[s]);
    } else if (id == 11) {
        int s = signal_index(a[0], 0), g = simulation->driver[s];
        printf("%s=%c driven by ", a[0], values[s]);
        if (g < 0)
            puts("input");
        else {
            Gate *gate = &simulation->gates[g];
            printf("%s %s", gate->name, types[gate->type]);
            for (int j = 0; j < gate->count; ++j)
                printf(" %s=%c", gate->inputs[j], values[simulation->in[g][j]]);
            printf(" delay %d\n", gate->delay);
        }
        printf("fanout %d", simulation->reader_count[s]);
        for (int i = 0; i < simulation->reader_count[s]; ++i)
            printf(" %s", simulation->gates[simulation->readers[s][i]].name);
        putchar('\n');
    } else if (id == 12) {
        long long start = number(a[0], 0), end = number(a[1], 0);
        if (!(start < end && end <= now))
            error("bad range %lld %lld", start, end);
        if (!watch_count)
            error("nothing watched");
        for (int i = 0; i < watch_count; ++i) {
            int s = watched[i];
            History *h = &history[s];
            size_t next = 0;
            char v = 'X';
            printf("%s ", simulation->signals[s]);
            for (long long t = start; t < end; ++t) {
                while (next < h->count && h->items[next].time <= t)
                    v = h->items[next++].value;
                putchar(v);
            }
            putchar('\n');
        }
    } else if (id == 13) {
        int s = signal_index(a[0], 0);
        History *h = &history[s];
        printf("history %s changes %zu", a[0], h->count);
        for (size_t i = 0; i < h->count; ++i)
            printf(" %lld:%c", h->items[i].time, h->items[i].value);
        putchar('\n');
    } else if (id == 14) {
        long long k = number(a[0], 1);
        int order[550];
        for (int i = 0; i < simulation->signal_count; ++i)
            order[i] = i;
        qsort(order, (size_t)simulation->signal_count, sizeof *order, activity_compare);
        for (int i = 0; i < simulation->signal_count && i < k; ++i)
            printf("%s %zu\n", simulation->signals[order[i]], history[order[i]].count);
    } else {
        int zero = 0, one = 0, unknown = 0;
        for (int i = 0; i < simulation->signal_count; ++i) {
            zero += values[i] == '0';
            one += values[i] == '1';
            unknown += values[i] == 'X';
        }
        printf("circuit %s time %lld pending %zu events %lld halted %s\n", simulation_name, now,
               event_count, processed, halted ? "yes" : "no");
        printf("values 0:%d 1:%d X:%d\n", zero, one, unknown);
    }
}

int main(void) {
    Line lines[1000];
    int count = 0;
    char buffer[128];
    while (count < 1000 && fgets(buffer, sizeof buffer, stdin)) {
        Line *line = &lines[count];
        line->number = count + 1;
        line->count = 0;
        char *storage = copy(buffer);
        for (char *word = strtok(storage, " \r\n"); word; word = strtok(NULL, " \r\n"))
            line->words[line->count++] = word;
        ++count;
    }
    int index = 0;
    while (index < count) {
        int first = index++, end = -1;
        Line *line = &lines[first];
        if (line->count == 1 && !strcmp(line->words[0], "END"))
            break;
        if (!strcmp(line->words[0], "MODULE")) {
            end = index;
            while (end < count &&
                   !(lines[end].count == 1 && !strcmp(lines[end].words[0], "ENDMODULE")))
                ++end;
            index = end + 1;
        }
        error_line = line->number;
        if (!setjmp(command_end)) {
            if (end >= 0)
                define_module(lines, first, end);
            else
                execute(line);
        }
    }
    return 0;
}
